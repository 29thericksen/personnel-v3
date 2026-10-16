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

  test "guest_stats permits leaders on the units they're responsible for" do
    company = create(:unit, abbr: "Charlie Co. HQ")
    cp1 = create(:unit, abbr: "CP1 HQ", parent: company)
    cp1s1 = create(:unit, abbr: "CP1S1", parent: cp1)
    cp1s2 = create(:unit, abbr: "CP1S2", parent: cp1)
    cp2 = create(:unit, abbr: "CP2 HQ", parent: company)
    other_company = create(:unit, abbr: "Dog Co. HQ")

    leader_of = ->(unit, abbr) do
      create(:permission, :leader, abbr: abbr, unit: unit)
      create(:user).tap { |user| create(:assignment, :leader, user: user, unit: unit) }
    end
    squad_leader = leader_of.call(cp1s1, "note_view_sq")
    platoon_leader = leader_of.call(cp1, "note_view_pl")
    company_leader = leader_of.call(company, "note_view_co")
    rifleman = create(:user)
    create(:assignment, user: rifleman, unit: cp1s1)

    assert_permit squad_leader, cp1s1, :guest_stats
    [cp1s2, cp1, company].each { |unit| refute_permit squad_leader, unit, :guest_stats }

    [cp1, cp1s1, cp1s2].each { |unit| assert_permit platoon_leader, unit, :guest_stats }
    [cp2, company].each { |unit| refute_permit platoon_leader, unit, :guest_stats }

    [company, cp1, cp1s2, cp2].each { |unit| assert_permit company_leader, unit, :guest_stats }
    refute_permit company_leader, other_company, :guest_stats

    refute_permit rifleman, cp1s1, :guest_stats
    refute_permit nil, cp1s1, :guest_stats
  end

  test "guest_stats permits MPs and admins on every unit" do
    unit = create(:unit, abbr: "Dog Co. HQ")

    {"note_view_mp" => "MP", "admin" => "S1"}.each do |abbr, unit_abbr|
      user = create(:user)
      user_unit = create(:unit, abbr: unit_abbr)
      create(:permission, abbr: abbr, unit: user_unit)
      create(:assignment, user: user, unit: user_unit)

      assert_permit user, unit, :guest_stats
    end
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
