class EventGuest < ApplicationRecord
  audited associated_with: :event
  belongs_to :event
  belongs_to :user, foreign_key: "member_id"

  validates :member_id, uniqueness: {scope: :event_id}
end
