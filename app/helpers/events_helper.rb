module EventsHelper
  DATETIME_FORMAT = "%F %R %Z".freeze

  def safe_bbcode(input)
    sanitizer = Rails::Html::SafeListSanitizer.new
    html = input.bbcode_to_html({}, false)
    simple_format(sanitizer.sanitize(html))
  end

  # Where a guest is from: their current unit(s), or Retired / Discharged.
  # Expects active_assignments (with unit) and discharges to be preloaded.
  def guest_status_detail(user)
    if user.active_assignments.any?
      user.active_assignments.map { |assignment| assignment.unit.abbr }.uniq.join(", ")
    elsif (discharge = user.discharges.max_by(&:date))
      discharge.honorable? ? "Retired" : "Discharged"
    else
      "Inactive"
    end
  end

  ATTENDANCE_BADGES = {
    loa: ["LOA", "secondary"],
    extended_loa: ["Extended LOA", "secondary"],
    excused: ["Excused", "secondary"],
    awol: ["AWOL", "danger"],
    absent: ["Absent", "warning"]
  }.freeze

  # Badge for an EventRoster entry's status; attended members get none.
  def attendance_badge(status)
    label, style = ATTENDANCE_BADGES[status]
    tag.span(label, class: "badge badge-#{style}") if label
  end

  # segments: [[count, kind], ...] where kind picks the colour.
  def attendance_bar(total, segments)
    return if total.zero?

    spans = segments.filter_map do |count, kind|
      next if count.zero?
      tag.span(class: "attendance-bar-#{kind}", style: "width: #{(count * 100.0 / total).round(2)}%")
    end
    tag.div(safe_join(spans), class: "attendance-bar", "aria-hidden": "true")
  end

  def calendar_wrapper(options = {}, &block)
    if options[:view_by] == "month"
      month_calendar(options, &block)
    else
      week_calendar(options, &block)
    end
  end

  def timestamp_tag(starts_at, format = DATETIME_FORMAT)
    comparison = compare_timezones(starts_at)
    content = starts_at.strftime(format)
    tag.time(content, :datetime => starts_at.utc.iso8601, :title => comparison,
      "data-toggle" => "tooltip", "data-controller" => "tooltip")
  end

  def format_timestamp(timestamp)
    timestamp&.strftime(DATETIME_FORMAT)
  end

  def compare_timezones(starts_at)
    current_user_time_zone = starts_at.time_zone

    Event::TIMEZONES
      .map { |tz| ActiveSupport::TimeZone[tz] }
      .append(current_user_time_zone)
      .uniq
      .map { |tz| starts_at.in_time_zone(tz) }
      .sort
      .map do |time|
        str = time.strftime(DATETIME_FORMAT)
        (time.time_zone == current_user_time_zone) ? bolden(str) : str
      end
      .join(tag(:br))
  end

  def timezone_dropdown_options
    Event::TIMEZONES
  end

  def build_time(time_zone:, date_time: nil, date: nil, time: nil)
    tz = Time.find_zone(time_zone)

    if date_time.present?
      tz.parse(date_time)
    elsif date.present? && time.present?
      begin
        parsed_date = Date.parse(date)
        tz.parse(time, parsed_date)
      rescue Date::Error
        nil
      end
    end
  end

  private

  def bolden(str)
    content_tag(:b, str)
  end
end
