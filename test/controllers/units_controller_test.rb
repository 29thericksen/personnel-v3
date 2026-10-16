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

  test "guests lists the unit's past events with guest counts" do
    busy = create(:event, unit: @squad, starts_at: 1.week.ago)
    quiet = create(:event, unit: @squad, starts_at: 2.weeks.ago)
    create(:event, unit: @squad, starts_at: 1.week.from_now)
    create_list(:event_guest, 2, event: busy)

    sign_in_as @member
    get unit_guests_url(@company)

    assert_response :success
    assert_select "nav a[href=?]", unit_guests_path(@company), text: "Guests"
    assert_select ".unit-guests-tabs .nav-link.active", text: /Guests at our drills\s+2/
    assert_select ".user-attendance-stats dd", text: "2", count: 4
    assert_select "tbody tr", 2
    assert_equal %w[2 0], css_select("tbody td.unit-guests__count-col").map { |td| td.text.strip }
    assert_select "a[href=?]", event_path(busy)
    assert_select "a[href=?]", event_path(quiet)
  end

  test "guests elsewhere tab counts members guesting at other units' events" do
    other_unit = create(:unit, abbr: "Baker Co. HQ")
    [5.days.ago, 45.days.ago, 100.days.ago].each do |starts_at|
      create(:event_guest, user: @member, event: create(:event, unit: other_unit, starts_at:))
    end
    create(:event_guest, event: create(:event, unit: other_unit, starts_at: 5.days.ago))

    sign_in_as @member
    get unit_guests_url(@company, tab: "elsewhere")

    assert_response :success
    assert_select ".unit-guests-tabs .nav-link.active", text: /Our members guesting elsewhere\s+3/
    assert_select "tbody tr", 1
    assert_select "a[href=?]", user_attendance_path(@member, filter: "guested"), text: @member.short_name
    assert_equal %w[1 2 2 3], css_select("tbody td.unit-guests__count-col").map { |td| td.text.strip }
  end

  test "guests counts guesting between sub-units on the parent's page" do
    sister = create(:unit, parent: @company, abbr: "Able 1-2")
    create(:event_guest, user: @member, event: create(:event, unit: sister, starts_at: 3.days.ago))

    sign_in_as @member
    get unit_guests_url(@company)

    assert_select ".unit-guests-tabs .nav-link", text: /Guests at our drills\s+1/
    assert_select ".unit-guests-tabs .nav-link", text: /Our members guesting elsewhere\s+1/
  end

  test "guests elsewhere tab without guesting shows an empty state" do
    sign_in_as @member
    get unit_guests_url(@company, tab: "elsewhere")

    assert_response :success
    assert_match "No members have guested at other drills.", response.body
  end

  test "guest stats tab is only for platoon HQ or higher" do
    sign_in_as @member
    get unit_guests_url(@company)
    assert_select ".unit-guests-tabs .nav-link", text: "Guest stats", count: 0

    get unit_guests_url(@company, tab: "stats")
    assert_redirected_to root_url
  end

  test "guest stats breaks down guesting by unit and ranks guesters and hosts" do
    leader = create(:user)
    leader_unit = create(:unit, abbr: "Baker Co. HQ")
    create(:permission, abbr: "note_view_co", unit: leader_unit)
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
    get unit_guests_url(@company, tab: "stats")

    assert_response :success
    assert_select ".unit-guests-tabs .nav-link.active", text: "Guest stats"
    rows = css_select("tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
    assert_equal [%w[Able\ 1-1 1 1 1 1], %w[Able\ 1-2 1 0 0 0]], rows
    assert_equal %w[2 1 1 1], css_select("tfoot td").map { |td| td.text.strip }

    top_guesters, top_hosts, _bottom_hosts = css_select(".unit-guest-stats__card")
    assert_match(/#{@member.short_name}\s+2/, top_guesters.text)
    refute_match quiet_member.short_name, top_guesters.text
    assert_match(/Able 1-1\s+1\.0\s+\(1 over 1 drill\)\s+Able 1-2\s+0\.5/, top_hosts.text.squish)

    get unit_guests_url(@company, tab: "stats", period: 30)

    top_guesters = css_select(".unit-guest-stats__card").first
    assert_match(/#{@member.short_name}\s+1/, top_guesters.text)
  end

  test "guest stats leaves units without guests out of the top hosts" do
    leader = create(:user)
    create(:permission, abbr: "note_view_pl", unit: @company)
    create(:assignment, user: leader, unit: @company)
    create(:event, unit: @squad, starts_at: 5.days.ago)

    sign_in_as leader
    get unit_guests_url(@company, tab: "stats")

    top_guesters, top_hosts, bottom_hosts = css_select(".unit-guest-stats__card")
    assert_match "No guesting in the last 90 days.", top_guesters.text
    assert_match "No guests in the last 90 days.", top_hosts.text
    assert_match(/Able 1-1\s+0\.0/, bottom_hosts.text)
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
end
