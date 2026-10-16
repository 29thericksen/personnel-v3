# Arranges an event's members into its unit tree, in the same order as the
# roster: units in tree order, then position, then rank. Each member is
# placed by the assignment they held when the event started, so later
# transfers don't move them on past events.
#
# Before attendance is taken it lists everyone expected, tagging LOAs. After,
# it lists the attendance records; anyone who can't be placed in the tree is
# returned by #other rather than silently dropped.
class EventRoster
  Group = Struct.new(:unit, :entries, :children) do
    def all_entries
      entries + children.flat_map(&:all_entries)
    end

    def empty?
      all_entries.empty?
    end
  end

  # status is nil, :loa or :extended_loa before attendance is taken, and
  # AttendanceRecord#status (:attended, :excused, :extended_loa, :awol,
  # :absent) after.
  Entry = Struct.new(:user, :status)

  attr_reader :event

  def initialize(event)
    @event = event
    @placed_ids = Set.new
  end

  def attendance_taken?
    return @attendance_taken if defined?(@attendance_taken)
    @attendance_taken = records.any? { |record| !record.attended.nil? }
  end

  def root
    @root ||= begin
      unit, children = event.unit.subtree.arrange(order: :order).first
      build_group(unit, children)
    end
  end

  def other
    @other ||= begin
      root # place everyone in the tree first
      if attendance_taken?
        records.reject { |record| @placed_ids.include?(record.member_id) }
          .map { |record| Entry.new(record.user, record.status) }
      else
        []
      end
    end
  end

  def entries
    root.all_entries + other
  end

  def counts
    entries.map(&:status).tally
  end

  private

  def build_group(unit, children)
    entries = assignments_by_unit.fetch(unit.id, []).filter_map { |assignment| place(assignment.user) }
    groups = children.map { |child, grandchildren| build_group(child, grandchildren) }
    Group.new(unit, entries, groups.reject(&:empty?))
  end

  def place(user)
    return if @placed_ids.include?(user.id) # guard: list each member once
    return if attendance_taken? && !records_by_member_id.key?(user.id)

    @placed_ids << user.id
    Entry.new(user, status_for(user))
  end

  def status_for(user)
    record = records_by_member_id[user.id]
    if attendance_taken?
      record.status
    elsif extended_loa_member_ids.include?(user.id)
      :extended_loa
    elsif record&.excused
      :loa
    end
  end

  # Same date rule as Event#expected_users, so the two never disagree.
  def assignments_by_unit
    @assignments_by_unit ||= Assignment.active(event.starts_at).roster(event.unit.subtree.ids)
  end

  def records
    @records ||= event.attendance_records
      .without_cancelled_loas # TODO: remove this after v2 calendar is disabled
      .includes(:event, user: :extended_loas)
      .to_a
  end

  def records_by_member_id
    @records_by_member_id ||= records.index_by(&:member_id)
  end

  def extended_loa_member_ids
    @extended_loa_member_ids ||= event.extended_loas.pluck(:member_id).to_set
  end
end
