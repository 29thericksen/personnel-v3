require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "invalid without required fields" do
    required_fields = %i[type starts_at unit server]
    required_fields.each do |field|
      event = build(:event, field => nil)
      refute event.valid?, "#{field} is not required"
    end
  end

  test "expected_users includes subtree users" do
    platoon = create(:unit)
    create(:assignment, unit: platoon)
    squad = create(:unit, parent: platoon)
    user = create(:user)
    create(:assignment, user: user, unit: squad)
    event = create(:event, unit: platoon)

    expected_users = event.expected_users

    assert_equal 2, expected_users.size
    assert_includes expected_users, user
  end

  test "expected_users excludes users assigned after the event" do
    unit = create(:unit)
    event = create(:event, starts_at: 2.weeks.ago, unit: unit)
    create_list(:assignment, 3, start_date: 4.weeks.ago, unit: unit)
    new_user = create(:user)
    create(:assignment, start_date: 1.week.ago, user: new_user, unit: unit)

    expected_users = event.expected_users

    assert_equal 3, expected_users.size
    refute_includes expected_users, new_user
  end

  test "expected_users excludes users whose assignment ended before the event" do
    unit = create(:unit)
    event = create(:event, starts_at: 2.weeks.ago, unit: unit)
    create_list(:assignment, 3, start_date: 4.weeks.ago, unit: unit)
    new_user = create(:user)
    create(:assignment, start_date: 4.weeks.ago, end_date: 3.weeks.ago,
      user: new_user, unit: unit)

    expected_users = event.expected_users

    assert_equal 3, expected_users.size
    refute_includes expected_users, new_user
  end

  test "expected_users includes users whose assignment has since ended" do
    unit = create(:unit)
    event = create(:event, starts_at: 2.weeks.ago, unit: unit)
    create_list(:assignment, 3, start_date: 4.weeks.ago, unit: unit)
    subject_user = create(:user)
    create(:assignment, start_date: 4.week.ago, end_date: 1.week.ago, user: subject_user, unit: unit)

    expected_users = event.expected_users

    assert_equal 4, expected_users.size
    assert_includes expected_users, subject_user
  end

  # e.g. training platoons
  test "expected_users works even if unit is inactive" do
    unit = create(:unit, active: false)
    event = create(:event, starts_at: 2.weeks.ago, unit: unit)
    create_list(:assignment, 3, start_date: 3.weeks.ago, end_date: 1.week.ago, unit: unit)

    expected_users = event.expected_users

    assert_equal 3, expected_users.size
  end

  test "update_guests adds and removes guests" do
    event = create(:event)
    kept, removed, added = Array.new(3) { create_member }
    create(:event_guest, event: event, user: kept)
    create(:event_guest, event: event, user: removed)

    event.update_guests(["", kept.id.to_s, added.id.to_s])

    assert_equal [kept, added].map(&:id).sort, event.guests.reload.map(&:id).sort
  end

  test "update_guests ignores expected users, unknown ids and duplicates" do
    unit = create(:unit)
    event = create(:event, unit: unit)
    expected_user = create(:assignment, unit: unit).user
    guest = create_member

    event.update_guests([expected_user.id, guest.id, guest.id, User.maximum(:id) + 1000].map(&:to_s))

    assert_equal [guest.id], event.guests.reload.map(&:id)
  end

  test "update_guests only adds members guest_candidates would offer" do
    event = create(:event)
    former_member = create(:user, last_name: "Harper")
    create(:assignment, user: former_member, start_date: 1.year.ago, end_date: 1.month.ago)
    applicant = create(:user, last_name: "Harris") # never held an assignment

    event.update_guests([former_member.id, applicant.id].map(&:to_s))

    assert_equal [former_member.id], event.guests.reload.map(&:id)
    assert_equal [former_member.id], event.guest_candidates("Har").map(&:id)
  end

  test "update_guests records the change as one audit on the event" do
    event = create(:event)
    kept, removed, added = Array.new(3) { create_member }
    create(:event_guest, event: event, user: kept)
    create(:event_guest, event: event, user: removed)

    assert_difference(-> { event.audits.count } => 1,
      -> { Audited::Audit.where(auditable_type: "EventGuest").count } => 0) do
      event.update_guests([kept.id, added.id].map(&:to_s))
    end

    audit = event.audits.last
    assert_equal [[kept.id, removed.id].sort, [kept.id, added.id].sort], audit.audited_changes["guest_ids"]
    assert_equal "Guests: 1 added, 1 removed", audit.comment
  end

  test "update_guests writes nothing when the guest list hasn't changed" do
    event = create(:event)
    guest = create_member
    create(:event_guest, event: event, user: guest)

    assert_no_difference(-> { event.audits.count }) do
      assert_queries_match(/\A\s*(INSERT|UPDATE|DELETE)/i, count: 0) do
        event.update_guests([guest.id.to_s])
      end
    end
  end

  test "update_guests adds any number of guests with a single insert" do
    event = create(:event)
    guests = Array.new(15) { create_member }

    assert_queries_match(/INSERT INTO `event_guests`/, count: 1) do
      event.update_guests(guests.map { |guest| guest.id.to_s })
    end
    assert_equal 15, event.guests.reload.size
  end

  test "guest_candidates finds current and former members outside the event" do
    unit = create(:unit)
    event = create(:event, unit: unit)
    expected_user = create(:user, first_name: "Test", last_name: "Harding")
    create(:assignment, user: expected_user, unit: unit)
    current_member = create(:user, first_name: "Test", last_name: "Harlan")
    create(:assignment, user: current_member)
    former_member = create(:user, first_name: "Test", last_name: "Harper")
    create(:assignment, user: former_member, start_date: 1.year.ago, end_date: 1.month.ago)
    create(:user, first_name: "Test", last_name: "Harris") # never assigned, e.g. an applicant
    create(:assignment, user: create(:user, first_name: "Harold", last_name: "Smith")) # first name only

    results = event.guest_candidates("har")

    assert_equal [current_member, former_member].map(&:id).sort, results.map(&:id).sort
  end

  test "guest_candidates needs at least two characters" do
    event = create(:event)
    create(:assignment, user: create(:user, last_name: "Harlan"))

    assert_empty event.guest_candidates("h")
    assert_empty event.guest_candidates(nil)
  end

  class AttendanceTotalsTest < EventTest
    test "calculates attendance totals" do
      event = create_attended_event(1.week.ago, attended: 6, absent: 4)

      assert_equal 6, event.attendance_totals.total_attended
      assert_equal 10, event.attendance_totals.total_expected
      assert_equal 4, event.attendance_totals.total_absent
    end

    test "an event with no attendance records has no attendance_totals member" do
      event = create(:event)

      assert_nil event.attendance_totals
    end

    test "total_attended and total_absent coalesce to 0" do
      attended_event = create_attended_event(1.week.ago, attended: 1)
      unattended_event = create_attended_event(1.week.ago, absent: 1)
      legacy_cancelled_loa_event = create(:event)
      create(:attendance_record, event: legacy_cancelled_loa_event,
        attended: nil, excused: false)

      assert_equal 0, attended_event.attendance_totals.total_absent
      assert_equal 0, unattended_event.attendance_totals.total_attended
      assert_equal 0, legacy_cancelled_loa_event.attendance_totals.total_attended
      assert_equal 0, legacy_cancelled_loa_event.attendance_totals.total_absent
    end

    private

    def create_attended_event(starts_at, attended: 0, absent: 0, mandatory: true)
      event = create(:event, starts_at: starts_at, mandatory: mandatory)
      create_list(:attendance_record, attended, :attended, event: event)
      create_list(:attendance_record, absent, :absent, event: event)
      event
    end
  end

  private

  # Someone who has held an assignment, so is eligible to be a guest
  def create_member
    create(:assignment).user
  end
end
