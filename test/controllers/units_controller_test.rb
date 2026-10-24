require "test_helper"

class UnitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:unit, abbr: "Able Co. HQ", name: "Able Company", game: :rs2)
    @squad = create(:unit, parent: @company, abbr: "Able 1-1", name: "First Squad")

    @member = create(:user, last_name: "Memberton")
    create(:assignment, user: @member, unit: @squad)
  end

  test "show renders the roster for the unit subtree" do
    get unit_url(@company)

    assert_response :success
    assert_match @squad.name, response.body
    assert_match @member.short_name, response.body
  end

  test "attendance lists past events with stats" do
    event = create(:event, unit: @squad, mandatory: true,
      starts_at: 1.week.ago, type: "Squad Drills")
    create(:attendance_record, user: @member, event: event, attended: true)

    sign_in_as @member
    get unit_attendance_url(@company)

    assert_response :success
    assert_match "Squad Drills", response.body
    assert_match "Last 30 days:", response.body
  end

  test "attendance handles legacy cancelled LOA records" do
    event = create(:event, unit: @squad, starts_at: 1.week.ago)
    create(:attendance_record, user: @member, event: event,
      attended: nil, excused: false)

    sign_in_as @member
    get unit_attendance_url(@company)

    assert_response :success
  end

  test "guests is open to members on their own unit only" do
    sign_in_as @member
    get unit_guests_url(@squad)

    assert_response :success
    assert_select "nav a[href=?]", unit_guests_path(@squad), text: "Guests"
    assert_select "h2", text: "Guests"

    get unit_guests_url(@company)
    assert_redirected_to root_url

    get unit_url(@company)
    assert_select "nav a[href=?]", unit_guests_path(@company), count: 0
  end

  test "guests is open to HQ members on every unit below their HQ" do
    squad_leader = create(:user)
    create(:assignment, :leader, user: squad_leader, unit: @squad)
    company_clerk = create(:user)
    create(:assignment, :elevated, user: company_clerk, unit: @company)

    sign_in_as squad_leader
    get unit_guests_url(@squad)
    assert_response :success
    get unit_guests_url(@company)
    assert_redirected_to root_url

    sign_in_as company_clerk
    get unit_guests_url(@squad)
    assert_response :success
    get unit_guests_url(@company)
    assert_response :success
  end

  test "every unit linked from a Guests page opens for the viewer" do
    sister = create(:unit, parent: @company, abbr: "Able 1-2")
    create(:assignment, unit: sister)
    create(:event, unit: sister, starts_at: 3.days.ago)
    company_clerk = create(:user)
    create(:assignment, :elevated, user: company_clerk, unit: @company)

    sign_in_as company_clerk
    get unit_guests_url(@company)
    links = css_select("a[href^='/units/'][href$='/guests']").map { |a| a["href"] }.uniq

    assert links.size >= 2, "Expected the page to link to its sub-units"
    links.each do |href|
      get href
      assert_response :success, "Expected #{href} to open for a company clerk"
    end
  end

  test "guests breaks down guesting by unit and ranks guesters and hosts" do
    leader = create(:user)
    leader_unit = create(:unit, abbr: "MP")
    create(:permission, abbr: "note_view_mp", unit: leader_unit)
    create(:assignment, user: leader, unit: leader_unit)

    sister = create(:unit, parent: @company, abbr: "Able 1-2")
    quiet_member = create(:user, last_name: "Quietson")
    create(:assignment, user: quiet_member, unit: sister)

    # @member guests at a sister squad's drill and at another company's
    create(:event_guest, user: @member, event: create(:event, unit: sister, starts_at: 10.days.ago))
    create(:event, unit: sister, starts_at: 20.days.ago)
    create(:event_guest, user: @member,
      event: create(:event, unit: create(:unit, abbr: "Dog Co. HQ"), starts_at: 50.days.ago))
    # An outsider guests at @squad's only drill
    create(:event_guest, event: create(:event, unit: @squad, starts_at: 5.days.ago))

    sign_in_as leader
    get unit_guests_url(@company)

    assert_response :success
    assert_equal [%w[Able\ 1-1 1 1 2 2], %w[Able\ 1-2 1 0 0 0]], table_rows(".unit-guest-stats__by-unit")
    assert_equal %w[2 1 2 2], css_select(".unit-guest-stats__by-unit tfoot td").map { |td| td.text.strip }

    assert_equal [[@member.short_name, "2"]], table_rows(".unit-guest-stats__guesters")
    assert_equal [%w[Able\ 1-1 1.00 1 1], %w[Able\ 1-2 0.50 1 2]], table_rows(".unit-guest-stats__hosts")

    get unit_guests_url(@company, period: 30)

    assert_equal [[@member.short_name, "1"]], table_rows(".unit-guest-stats__guesters")
  end

  test "guests counts members once, under their combat post" do
    clerk_office = create(:unit, parent: @company, abbr: "Fin", classification: "Staff")
    training = create(:unit, parent: @company, abbr: "TP 2608", classification: "Training")
    create(:assignment, user: @member, unit: clerk_office) # dual-hatted: Able 1-1 + Fin
    staff_only = create(:user)
    create(:assignment, user: staff_only, unit: clerk_office)
    cadet = create(:user)
    create(:assignment, user: cadet, unit: training)
    elsewhere = create(:unit, abbr: "Dog Co. HQ")
    [@member, staff_only, cadet].each do |user|
      create(:event_guest, user: user, event: create(:event, unit: elsewhere, starts_at: 5.days.ago))
    end

    sign_in_as admin_user
    get unit_guests_url(@company)

    assert_equal [%w[Able\ 1-1 1 1 1 1]], table_rows(".unit-guest-stats__by-unit"),
      "Expected no staff office or training rows, and @member only under their squad"
    assert_equal %w[1 1 1 1], css_select(".unit-guest-stats__by-unit tfoot td").map { |td| td.text.strip }.last(4)
    assert_equal [[@member.short_name, "1"]], table_rows(".unit-guest-stats__guesters")
  end

  test "guests counts drills only" do
    sister = create(:unit, parent: @company, abbr: "Able 1-2")
    create(:event_guest, user: @member, event: create(:event, unit: sister, starts_at: 10.days.ago))
    ["Basic Combat Training", "Public Scrimmage", "Special Event"].each do |type|
      create(:event_guest, user: @member, event: create(:event, unit: sister, type: type, starts_at: 5.days.ago))
    end

    sign_in_as admin_user
    get unit_guests_url(@company)

    assert_equal [%w[Able\ 1-1 1 1 1 1]], table_rows(".unit-guest-stats__by-unit"), "Expected only the drill to count"
    assert_equal [[@member.short_name, "1"]], table_rows(".unit-guest-stats__guesters")
    assert_equal [%w[Able\ 1-2 1.00 1 1]], table_rows(".unit-guest-stats__hosts"), "Expected only the drill as a hosted drill"
  end

  test "guests with no guesting shows empty states and every host" do
    create(:event, unit: @squad, starts_at: 5.days.ago)

    sign_in_as @member
    get unit_guests_url(@squad)

    assert_equal [["No guesting in the last 90 days."]], table_rows(".unit-guest-stats__guesters")
    assert_equal [%w[Able\ 1-1 0.00 0 1]], table_rows(".unit-guest-stats__hosts")
  end

  test "guests shows per-drill averages to two decimal places" do
    create(:event_guest, event: create(:event, unit: @squad, starts_at: 1.day.ago))
    24.times { |i| create(:event, unit: @squad, starts_at: (i + 2).days.ago) }

    sign_in_as @member
    get unit_guests_url(@squad)

    assert_equal [%w[Able\ 1-1 0.04 1 25]], table_rows(".unit-guest-stats__hosts")
  end

  test "awols groups recent awols by user" do
    event = create(:event, unit: @squad, mandatory: true, starts_at: 1.week.ago)
    create(:attendance_record, user: @member, event: event,
      attended: false, excused: false)

    sign_in_as @member
    get unit_awols_url(@company)

    assert_response :success
    assert_match @member.short_name, response.body
  end

  test "missing_awards lists users owed service medals" do
    create(:permission, abbr: "awarding_add", unit: @company)
    awarder = create(:user)
    create(:assignment, user: awarder, unit: @company)

    veteran = create(:user, last_name: "Veteranson")
    create(:assignment, user: veteran, unit: @squad, start_date: 8.months.ago)

    sign_in_as awarder
    get unit_missing_awards_url(@company)

    assert_response :success
    assert_match veteran.short_name, response.body
    assert_match "Army of Occupation", response.body
  end

  test "missing_awards respects each user's latest non-honorable discharge" do
    create(:permission, abbr: "awarding_add", unit: @company)
    awarder = create(:user)
    create(:assignment, user: awarder, unit: @company)
    army_of_occupation = create(:award, code: "aocc")

    veteran = create(:user, last_name: "Veteranson")
    create(:assignment, user: veteran, unit: @squad,
      start_date: 3.years.ago, end_date: 2.years.ago)
    create(:discharge, user: veteran, date: 2.years.ago, type: :general)
    create(:assignment, user: veteran, unit: @squad, start_date: 8.months.ago)
    create(:user_award, user: veteran, award: army_of_occupation, date: 7.months.ago)

    another_veteran = create(:user)
    create(:assignment, user: another_veteran, unit: @squad,
      start_date: 18.months.ago, end_date: 1.year.ago)
    create(:discharge, user: another_veteran, date: 1.year.ago, type: :general)
    create(:assignment, user: another_veteran, unit: @squad, start_date: 1.month.ago)

    sign_in_as awarder
    get unit_missing_awards_url(@company)

    assert_response :success
    assert_no_match veteran.short_name, response.body
    assert_match "No missing awards found", response.body
  end

  test "missing_awards refuses members without awarding_add" do
    sign_in_as @member
    get unit_missing_awards_url(@company)

    assert_redirected_to root_url
    assert_match(/not authorized/, flash[:alert])
  end

  test "stats shows members with attendance and standards progress" do
    sign_in_as @member
    get unit_stats_url(@company)

    assert_response :success
    assert_match @member.short_name, response.body
    assert_match "Unit Statistics", response.body
  end

  test "discharges lists members discharged from the subtree" do
    dischargee = create(:user, last_name: "Dischargeson")
    date = 2.months.ago.to_date
    create(:assignment, user: dischargee, unit: @squad,
      start_date: 1.year.ago, end_date: date)
    create(:discharge, user: dischargee, date: date, type: :honorable)

    sign_in_as @member
    get unit_discharges_url(@company)

    assert_response :success
    assert_match dischargee.short_name, response.body
    assert_match "Honorable", response.body
  end

  test "recruits lists enlistments recruited by subtree members" do
    recruit = create(:user, last_name: "Recruitson")
    create(:enlistment, status: :accepted, user: recruit, recruiter_user: @member)

    sign_in_as @member
    get unit_recruits_url(@company)

    assert_response :success
    assert_match recruit.short_name, response.body
    assert_match "Accepted", response.body
  end

  test "member-only pages refuse non-members" do
    non_member = create(:user)

    sign_in_as non_member
    get unit_attendance_url(@company)

    assert_redirected_to root_url
    assert_match(/not authorized/, flash[:alert])
  end

  private

  def admin_user
    create(:user).tap do |user|
      admin_unit = create(:unit, abbr: "S1")
      create(:permission, abbr: "admin", unit: admin_unit)
      create(:assignment, user: user, unit: admin_unit)
    end
  end

  def table_rows(table_selector)
    css_select("#{table_selector} tbody tr").map do |tr|
      tr.css("td").map { |td| td.text.strip }
    end
  end
end
