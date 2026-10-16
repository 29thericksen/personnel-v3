class EventGuest < ApplicationRecord
  audited associated_with: :event
  belongs_to :event
  belongs_to :user, foreign_key: "member_id"

  validates :member_id, uniqueness: {scope: :event_id}

  COUNT_PERIODS = [30, 60, 90].freeze

  scope :past, -> { joins(:event).merge(Event.past) }

  # Raw guest counts over the last 30, 60 and 90 days and in total, as
  # last_30_days, last_60_days, last_90_days and total. Add .group to count
  # per member or per event; otherwise use .take for a single row.
  scope :period_counts, -> {
    periods = COUNT_PERIODS.map do |days|
      sanitize_sql_array(["CAST(COALESCE(SUM(events.starts_at >= ?), 0) AS UNSIGNED) AS last_#{days}_days",
        days.days.ago])
    end
    past.select(*periods, "COUNT(*) AS total")
  }
end
