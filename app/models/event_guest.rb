# Written in bulk by Event#update_guests, which audits guest changes on the
# event itself rather than per row.
class EventGuest < ApplicationRecord
  belongs_to :event
  belongs_to :user, foreign_key: "member_id"

  validates :member_id, uniqueness: {scope: :event_id}
end
