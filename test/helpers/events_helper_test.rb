require "test_helper"

class EventsHelperTest < ActionView::TestCase
  test "guest_status_detail shows current unit, or discharge status for former members" do
    current_member = create(:user)
    create(:assignment, user: current_member, unit: create(:unit, abbr: "Bn. HQ"))
    retired = create(:user)
    create(:assignment, user: retired, start_date: 1.year.ago, end_date: 1.month.ago)
    create(:discharge, user: retired, type: :honorable)
    discharged = create(:user)
    create(:assignment, user: discharged, start_date: 1.year.ago, end_date: 1.month.ago)
    create(:discharge, user: discharged, type: :general)

    assert_equal "Bn. HQ", guest_status_detail(current_member)
    assert_equal "Retired", guest_status_detail(retired)
    assert_equal "Discharged", guest_status_detail(discharged)
  end

  test "safe_bbcode renders bb code as html" do
    text = %([b]Hello, world![/b])
    output = safe_bbcode(text)
    assert_dom_equal %(<p><strong>Hello, world!</strong></p>), output
  end

  test "safe_bbcode removes malicious tags" do
    text = %{<h1>Hello, <script>alert('malicious')</script>!</h1>}
    output = safe_bbcode(text)
    doc = Nokogiri::HTML::Document.parse(output)
    assert_select doc.root, "script", false
  end

  # test "safe_bbcode allows <center> tag" do
  #   text = %(<center>Text</center>)
  #   output = safe_bbcode(text)
  #   assert_dom_equal %(<p><center>Text</center></p>), output
  # end
end
