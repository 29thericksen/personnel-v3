require "test_helper"

class UnitPolicyTest < ActiveSupport::TestCase
  test "show permits anonymous visitors" do
    unit = create(:unit)

    assert_permit nil, unit, :show
  end

  test "member-only pages permit members and deny non-members" do
    unit = create(:unit)

    member = create(:user)
    create(:assignment, user: member, unit: create(:unit, classification: :combat))
    non_member = create(:user)

    %i[attendance guests awols stats recruits discharges].each do |action|
      assert_permit member, unit, action
      refute_permit non_member, unit, action
    end
  end

  test "guest_stats permits platoon HQ or higher on any unit" do
    unit = create(:unit)

    platoon_leader = create(:user)
    platoon = create(:unit, abbr: "CP1 HQ")
    create(:permission, abbr: "note_view_pl", unit: platoon)
    create(:assignment, user: platoon_leader, unit: platoon)

    squad_leader = create(:user)
    squad = create(:unit, abbr: "CP1S1")
    create(:permission, abbr: "note_view_sq", unit: squad)
    create(:assignment, user: squad_leader, unit: squad)

    assert_permit platoon_leader, unit, :guest_stats
    refute_permit squad_leader, unit, :guest_stats
    refute_permit nil, unit, :guest_stats
  end

  test "missing_awards permits user with awarding_add on the unit or its subtree" do
    unit = create(:unit)
    child_unit = create(:unit, parent: unit)
    create(:permission, abbr: "awarding_add", unit: unit)

    user = create(:user)
    create(:assignment, user: user, unit: unit)

    assert_permit user, unit, :missing_awards
    assert_permit user, child_unit, :missing_awards
  end

  test "missing_awards denies member without awarding_add" do
    unit = create(:unit)

    member = create(:user)
    create(:assignment, user: member, unit: unit)

    refute_permit member, unit, :missing_awards
  end

  test "graduate permits admin only" do
    unit = create(:unit)
    admin_unit = create(:unit)
    create(:permission, abbr: "admin", unit: admin_unit)

    admin = create(:user)
    create(:assignment, user: admin, unit: admin_unit)

    member = create(:user)
    create(:assignment, user: member, unit: unit)

    assert_permit admin, unit, :graduate
    refute_permit member, unit, :graduate
  end
end
