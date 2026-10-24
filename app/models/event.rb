class Event < ApplicationRecord
  self.inheritance_column = nil # don't treat type field as STI
  audited
  belongs_to :unit
  belongs_to :server
  belongs_to :reporter, foreign_key: "reporter_member_id", class_name: "User", optional: true
  has_many :attendance_records, -> { includes(user: :rank).order("ranks.order DESC", "members.last_name") } do
    def find_by_user(user)
      find_by(member_id: user.id)
    end
  end
  has_many :users, through: :attendance_records
  has_one :attendance_totals, -> { totals_by_event }, class_name: "AttendanceRecord"
  has_many :event_guests, dependent: :delete_all
  has_many :guests, -> { includes(:rank).order("ranks.order DESC", "members.last_name") },
    through: :event_guests, source: :user

  scope :for_user, ->(user) do
    for_unit(user.active_assignment_unit_path_ids)
  end

  scope :for_unit, ->(unit) { where(unit: unit) }

  scope :past, -> { where(starts_at: ..Date.current) }

  scope :asc, -> { order(starts_at: :asc) }
  scope :desc, -> { order(starts_at: :desc) }

  attr_accessor :bulk_dates
  attr_accessor :time
  attr_writer :starts_at_local

  TYPES = ["Squad Drills", "Platoon Drills", "Company Drills", "Battalion Drills", "Basic Combat Training",
    "Public Scrimmage", "Special Event"]
  validates :type, presence: true, inclusion: {in: TYPES}

  # What counts as a drill: the four unit drill types, mandatory or not.
  # Basic Combat Training, Public Scrimmages and Special Events are events,
  # not drills.
  DRILL_TYPES = ["Squad Drills", "Platoon Drills", "Company Drills", "Battalion Drills"].freeze
  scope :drills, -> { where(type: DRILL_TYPES) }

  def drill?
    DRILL_TYPES.include?(type)
  end

  TIMEZONES = [
    "Pacific Time (US & Canada)",
    "Eastern Time (US & Canada)",
    "UTC",
    "London"
  ]
  validates :time_zone, inclusion: {in: TIMEZONES}

  validates :starts_at, presence: true
  validates_datetime :starts_at
  validates :mandatory, inclusion: {in: [true, false]}
  validates :server, presence: true

  before_save :update_report_dates,
    if: proc { attendance_records.any? || will_save_change_to_report? }
  before_save :update_legacy_datetime

  self.skip_time_zone_conversion_for_attributes = [:datetime, :report_posting_date, :report_edit_date]

  def expected_users
    unit.subtree_users.active(starts_at).includes(:rank)
  end

  # Cached: an AAR save needs these ids for attendance, Extended LOAs and guests.
  def expected_user_ids
    @expected_user_ids ||= expected_users.ids
  end

  def extended_loas
    ExtendedLOA.active(starts_at)
      .where(member_id: expected_user_ids)
  end

  def title
    if unit
      "#{unit.subtree_abbr} #{type}"
    else
      type
    end
  end

  # Alias for simple_calendar
  def start_time
    starts_at
  end

  def update_attendance(attended_user_ids)
    attendance = expected_user_ids.collect do |user_id|
      {event_id: id, member_id: user_id,
       attended: attended_user_ids.include?(user_id)}
    end

    AttendanceRecord.upsert_all(attendance) if attendance.any?
  end

  def excuse_users_on_extended_loa
    attendance = extended_loas.collect do |eloa|
      {event_id: id, member_id: eloa.user.id, excused: true}
    end

    AttendanceRecord.upsert_all(attendance) if extended_loas.any?
  end

  def attended?(user)
    attendance_record = attendance_records.find { |ar| ar.user == user }
    attendance_record&.attended
  end

  def posted_loa?(user)
    attendance_record = attendance_records.find_by_user(user)
    attendance_record&.excused
  end

  def post_loa(user)
    AttendanceRecord.upsert({event_id: id, member_id: user.id, excused: true})
  end

  def cancel_loa(user)
    attendance_record = attendance_records.find_by_user(user)
    if attendance_record.attended.nil?
      attendance_record.destroy
    else
      attendance_record.update(excused: false)
    end
  end

  GUEST_SEARCH_LIMIT = 10

  # Replaces the guest list, ignoring unknown ids and anyone expected at the
  # event. Writes in bulk (one delete, one insert) and records the change as
  # a single audit on the event, so the cost doesn't grow with the guest list.
  def update_guests(user_ids)
    ids = user_ids.reject(&:blank?).map(&:to_i).uniq
    wanted = eligible_guests.where(id: ids).ids
    current = event_guests.pluck(:member_id)
    added = wanted - current
    removed = current - wanted
    return if added.empty? && removed.empty?

    transaction do
      event_guests.where(member_id: removed).delete_all if removed.any?
      if added.any?
        now = Time.current
        EventGuest.insert_all(added.map { |member_id|
          {event_id: id, member_id: member_id, created_at: now, updated_at: now}
        })
      end
      audits.create!(action: "update",
        audited_changes: {"guest_ids" => [current.sort, (current - removed + added).sort]},
        comment: "Guests: #{added.size} added, #{removed.size} removed")
    end
  end

  # Who can be a guest at this event: anyone who has ever held an assignment,
  # active or not, except those expected at it. The guest search and
  # update_guests both use this, so a save can't add anyone the search
  # wouldn't offer.
  def eligible_guests
    User.where(id: Assignment.select(:member_id)).where.not(id: expected_user_ids)
  end

  # Eligible guests whose last name starts with the query.
  def guest_candidates(query)
    term = query.to_s.strip
    return User.none if term.length < 2

    pattern = "#{User.sanitize_sql_like(term)}%"
    eligible_guests
      .where("members.last_name LIKE ?", pattern)
      .joins(:rank)
      .preload(:rank, :discharges, active_assignments: :unit)
      .order("ranks.order DESC", "members.last_name")
      .limit(GUEST_SEARCH_LIMIT)
  end

  def starts_at_local
    @starts_at_local ||= starts_at&.in_time_zone(time_zone)
  end

  def aar_posted?
    report_posting_date.present?
  end

  private_class_method :ransackable_attributes, :ransackable_associations

  def self.ransackable_attributes(_auth_object = nil)
    %w[id datetime type title mandatory]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[unit server reporter]
  end

  private

  def update_report_dates
    self.report_posting_date ||= Time.current
    self.report_edit_date = Time.current
  end

  # Personnel v2 uses the `datetime` column, which is stored in Eastern Time
  def update_legacy_datetime
    # Remove time zone so rails doesn't try to convert it
    self.datetime = starts_at.in_time_zone("Eastern Time (US & Canada)")
      .strftime("%F %R")
  end
end
