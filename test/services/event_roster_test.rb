require "test_helper"

class EventRosterTest < ActiveSupport::TestCase
  setup do
    @platoon = create(:unit, name: "First Platoon")
    @first_squad = create(:unit, parent: @platoon, name: "First Squad", order: 1)
    @second_squad = create(:unit, parent: @platoon, name: "Second Squad", order: 2)
  end

  test "groups members by unit in roster order: position, then rank" do
    platoon_leader = assign(@platoon, position: 80, rank: 12)
    squad_leader = assign(@first_squad, position: 60, rank: 6)  # Cpl. squad leader
    senior_rifleman = assign(@first_squad, position: 10, rank: 7) # outranks the SL
    junior_rifleman = assign(@first_squad, position: 10, rank: 3)
    second_squad_member = assign(@second_squad, position: 10, rank: 3)
    event = create(:event, unit: @platoon)

    roster = EventRoster.new(event)

    assert_equal [platoon_leader], roster.root.entries.map(&:user)
    assert_equal [@first_squad, @second_squad], roster.root.children.map(&:unit)
    assert_equal [squad_leader, senior_rifleman, junior_rifleman], roster.root.children.first.entries.map(&:user)
    assert_equal [second_squad_member], roster.root.children.last.entries.map(&:user)
  end

  test "before attendance is taken, lists everyone expected and tags LOAs" do
    on_loa = assign(@first_squad)
    on_extended_loa = assign(@first_squad)
    available = assign(@first_squad)
    event = create(:event, unit: @platoon)
    create(:attendance_record, event: event, user: on_loa, attended: nil, excused: true)
    create(:extended_loa, user: on_extended_loa, start_date: 1.day.ago)

    roster = EventRoster.new(event)

    refute roster.attendance_taken?
    statuses = roster.entries.to_h { |entry| [entry.user, entry.status] }
    assert_equal({on_loa => :loa, on_extended_loa => :extended_loa, available => nil}, statuses)
    assert_empty roster.other
  end

  test "places members by the assignment they held when the event started" do
    transferred = create(:user)
    create(:assignment, user: transferred, unit: @first_squad, start_date: 4.weeks.ago, end_date: 1.week.ago)
    create(:assignment, user: transferred, unit: @second_squad, start_date: 1.week.ago)
    event = create(:event, unit: @platoon, starts_at: 2.weeks.ago)

    roster = EventRoster.new(event)

    first_squad, second_squad = roster.root.children
    assert_equal @first_squad, first_squad.unit
    assert_equal [transferred], first_squad.entries.map(&:user)
    assert_nil second_squad, "Expected the empty Second Squad group to be dropped"
  end

  test "after attendance is taken, lists the records and keeps unplaceable members in other" do
    attended = assign(@first_squad)
    not_recorded = assign(@first_squad)
    outsider = create(:user) # record but no assignment in the platoon
    event = create(:event, unit: @platoon)
    create(:attendance_record, event: event, user: attended, attended: true)
    create(:attendance_record, event: event, user: outsider, attended: false, excused: false)

    roster = EventRoster.new(event)

    assert roster.attendance_taken?
    assert_equal [attended], roster.root.all_entries.map(&:user)
    refute_includes roster.entries.map(&:user), not_recorded
    assert_equal [[outsider, :absent]], roster.other.map { |entry| [entry.user, entry.status] }
    assert_equal({attended: 1, absent: 1}, roster.counts)
  end

  test "expected_only lists everyone expected even after attendance is taken" do
    attended = assign(@first_squad)
    on_loa = assign(@first_squad)
    not_recorded = assign(@first_squad)
    outsider = create(:user) # record but not expected
    event = create(:event, unit: @platoon)
    create(:attendance_record, event: event, user: attended, attended: true)
    create(:attendance_record, event: event, user: on_loa, attended: false, excused: true)
    create(:attendance_record, event: event, user: outsider, attended: true)

    roster = EventRoster.new(event, expected_only: true)

    statuses = roster.entries.to_h { |entry| [entry.user, entry.status] }
    assert_equal({attended => nil, on_loa => :loa, not_recorded => nil}, statuses)
    assert_empty roster.other, "Expected members who aren't expected to be left off the form"
  end

  test "includes members of inactive sub-units" do
    old_squad = create(:unit, parent: @platoon, active: false)
    member = assign(old_squad)
    event = create(:event, unit: @platoon)

    assert_includes EventRoster.new(event).entries.map(&:user), member
  end

  private

  def assign(unit, position: 10, rank: 3)
    user = create(:user, rank: create(:rank, order: rank))
    create(:assignment, user: user, unit: unit, position: create(:position, order: position))
    user
  end
end
