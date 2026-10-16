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

  test "guests is open to leaders on the units they're responsible for" do
    squad_leader = create(:user)
    create(:permission, abbr: "note_view_sq", unit: @squad)
    create(:assignment, user: squad_leader, unit: @squad)
    hq_leader = create(:user)
    create(:permission, abbr: "note_view_co", unit: @company)
    create(:assignment, user: hq_leader, unit: @company)

    sign_in_as squad_leader
    get unit_guests_url(@squad)
    assert_response :success
    get unit_guests_url(@company)
    assert_redirected_to root_url

    sign_in_as hq_leader
    get unit_guests_url(@squad)
    assert_response :success
    get unit_guests_url(@company)
    assert_response :success
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
    assert_equal [%w[Able\ 1-1 1.0 1 1], %w[Able\ 1-2 0.5 1 2]], table_rows(".unit-guest-stats__hosts")

    get unit_guests_url(@company, period: 30)

    assert_equal [[@member.short_name, "1"]], table_rows(".unit-guest-stats__guesters")
  end

  test "guests with no guesting shows empty states and every host" do
    create(:event, unit: @squad, starts_at: 5.days.ago)

    sign_in_as @member
    get unit_guests_url(@squad)

    assert_equal [["No guesting in the last 90 days."]], table_rows(".unit-guest-stats__guesters")
    assert_equal [%w[Able\ 1-1 0.0 0 1]], table_rows(".unit-guest-stats__hosts")
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

  def table_rows(table_selector)
    css_select("#{table_selector} tbody tr").map do |tr|
      tr.css("td").map { |td| td.text.strip }
    end
  end
end
