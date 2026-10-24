require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @subject = create(:user)

    @user = create(:user)
    create(:assignment, user: @user)
  end

  test "should get profile" do
    get user_url(@subject)
    assert_response :success
  end

  test "service record shows each kind of record grouped by year" do
    create(:assignment, user: @subject, unit: create(:unit, name: "First Squad"),
      start_date: 6.months.ago)
    create(:user_award, user: @subject, award: create(:award, title: "Shiny medal"))
    create(:promotion, user: @subject, rank_abbr: "Cpl.")
    create(:demerit, user: @subject)
    create(:discharge, user: @subject, type: :honorable)
    create(:enlistment, user: @subject, status: :accepted)

    get user_service_record_url(@subject)

    assert_response :success
    assert_match "Assigned to", response.body
    assert_match "First Squad", response.body
    assert_match "Shiny medal", response.body
    assert_match "Promoted to", response.body
    assert_match "a demerit", response.body
    assert_match "Honorably discharged", response.body
    assert_match "Enlisted", response.body
    assert_select "h2", text: Date.current.year.to_s
  end

  test "should get attendance" do
    sign_in_as @user
    get user_attendance_url(@subject)
    assert_response :success
  end

  test "attendance lists own events and guested events together" do
    record = create(:attendance_record, :attended, user: @subject,
      event_starts_at: 3.days.ago)
    guested = create(:event, starts_at: 2.days.ago)
    create(:event_guest, event: guested, user: @subject)

    sign_in_as @user
    get user_attendance_url(@subject)

    assert_response :success
    assert_select "tbody tr", 2
    assert_select "a[href=?]", event_path(record.event)
    assert_select "a[href=?]", event_path(guested)
    assert_select "tbody .badge-success", text: "Attended"
    assert_select "tbody .badge-info", text: "Guest"
    assert_select ".user-attendance-filters .nav-link.active", text: /All Events\s+2/
    assert_select ".user-attendance-filters .nav-link", text: /Unit Events\s+1/
    assert_select ".user-attendance-filters .nav-link", text: /Guested Events\s+1/
  end

  test "attendance required filter leaves out guested events" do
    record = create(:attendance_record, :absent, user: @subject,
      event_starts_at: 3.days.ago)
    guested = create(:event, starts_at: 2.days.ago)
    create(:event_guest, event: guested, user: @subject)

    sign_in_as @user
    get user_attendance_url(@subject, filter: "required")

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "a[href=?]", event_path(record.event)
    assert_select ".badge-info", 0
    assert_select ".user-attendance-filters .nav-link.active", text: /Unit Events/
  end

  test "attendance guested filter shows only guested events" do
    record = create(:attendance_record, :attended, user: @subject,
      event_starts_at: 3.days.ago)
    guested = create(:event, starts_at: 2.days.ago, mandatory: true)
    create(:event_guest, event: guested, user: @subject)

    sign_in_as @user
    get user_attendance_url(@subject, filter: "guested")

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "a[href=?]", event_path(guested)
    assert_select "a[href=?]", event_path(record.event), 0
    assert_select "tbody td", text: "—"
    assert_select "tbody .badge-info", text: "Guest"
  end

  test "attendance ignores an unknown filter" do
    create(:attendance_record, :attended, user: @subject,
      event_starts_at: 3.days.ago)

    sign_in_as @user
    get user_attendance_url(@subject, filter: "bogus")

    assert_response :success
    assert_select "tbody tr", 1
    assert_select ".user-attendance-filters .nav-link.active", text: /All Events/
  end

  test "attendance guested filter with no guests shows an empty state" do
    create(:attendance_record, :attended, user: @subject,
      event_starts_at: 3.days.ago)

    sign_in_as @user
    get user_attendance_url(@subject, filter: "guested")

    assert_response :success
    assert_select "tbody tr", 1
    assert_match "No events to show.", response.body
  end

  test "should get qualifications" do
    sign_in_as @user
    get user_qualifications_url(@subject)
    assert_response :success
  end

  test "should get extended loas" do
    sign_in_as @user
    get user_extended_loas_url(@subject)
    assert_response :success
  end

  test "recruits lists accepted enlistments recruited by the user" do
    accepted_recruit = create(:user, last_name: "Acceptedson")
    create(:enlistment, status: :accepted, user: accepted_recruit,
      recruiter_user: @subject)
    pending_recruit = create(:user, last_name: "Pendingson")
    create(:enlistment, status: :pending, user: pending_recruit,
      recruiter_user: @subject)

    get user_recruits_url(@subject)

    assert_response :success
    assert_match "Total: 1", response.body
    assert_match accepted_recruit.short_name, response.body
    refute_match pending_recruit.short_name, response.body
  end

  test "reprimands lists demerits and awols" do
    demerit = create(:demerit, user: @subject, reason: "Insubordination")
    create(:attendance_record, :absent, :mandatory, user: @subject,
      event_starts_at: 3.days.ago)

    sign_in_as @user
    get user_reprimands_url(@subject)

    assert_response :success
    assert_match demerit.reason, response.body
    assert_select ".awols li", 1
  end

  test "reprimands is not available to non-members" do
    non_member = create(:user)

    sign_in_as non_member
    get user_reprimands_url(@subject)

    assert_redirected_to root_url
  end
end
