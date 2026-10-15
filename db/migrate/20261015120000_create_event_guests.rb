class CreateEventGuests < ActiveRecord::Migration[8.0]
  # Members from outside the event's unit who joined it. Kept out of the
  # attendance table on purpose: guests are informational only and must not
  # affect attendance stats, totals or AWOL counts.
  #
  # event_id and member_id must match events.id and members.id exactly
  # (MEDIUMINT UNSIGNED) or MySQL rejects the foreign keys.
  def change
    create_table :event_guests do |t|
      t.integer :event_id, limit: 3, unsigned: true, null: false
      t.integer :member_id, limit: 3, unsigned: true, null: false
      t.timestamps

      t.index [:event_id, :member_id], unique: true
      t.index :member_id
    end

    add_foreign_key :event_guests, :events, on_update: :cascade, on_delete: :cascade
    add_foreign_key :event_guests, :members, column: :member_id, on_update: :cascade
  end
end
