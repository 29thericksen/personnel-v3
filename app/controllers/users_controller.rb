class UsersController < ApplicationController
  before_action :find_and_authorize_user, :find_assignments
  layout "user"

  def show
    @donated = FinanceRecord.user_donated(@user)
  end

  def service_record
    user_awards = @user.user_awards.includes(:award).order(date: :desc)
    promotions = @user.promotions.includes(:new_rank, :old_rank).order(date: :desc)
    assignments = @user.assignments.includes(:unit, :position).select("*, start_date AS date").order(start_date: :desc)
    demerits = @user.demerits.order(date: :desc)
    discharges = @user.discharges.order(date: :desc)
    enlistments = @user.enlistments.includes(:unit).order(date: :desc)

    @items_by_year = (
      user_awards +
      promotions +
      assignments +
      demerits +
      discharges +
      enlistments)
      .sort_by(&:date)
      .reverse
      .group_by { |item| item.date.year }
  end

  # "required" is every event the member was expected at (their own unit's),
  # "guested" is every event they joined as a guest from outside the unit.
  ATTENDANCE_FILTERS = %w[all required guested].freeze

  def attendance
    @filter = ATTENDANCE_FILTERS.include?(params[:filter]) ? params[:filter] : "all"

    required_events = Event.where(id: @user.attendance_records.select(:event_id))
    guested_events = Event.where(id: @user.event_guests.select(:event_id))
    events_by_filter = {
      "all" => required_events.or(guested_events),
      "required" => required_events,
      "guested" => guested_events
    }

    @filter_counts = events_by_filter.transform_values(&:count)
    @events = events_by_filter[@filter]
      .includes(:unit)
      .desc
      .page(params[:page])

    # Events without a record here are ones the member guested
    @attendance_records = @user.attendance_records
      .includes(:user, :event)
      .where(event_id: @events.map(&:id))
      .index_by(&:event_id)

    @attendance_stats = @user.attendance_stats
  end

  def qualifications
    @ait_qualifications = @user.ait_qualifications
      .includes(author: :rank)
      .each_with_object({}) do |item, accum|
        accum[item.standard_id] = item
      end

    @ait_standards = AITStandard
      .all
      .each_with_object({}) do |item, accum|
        accum[item.game] ||= KeyedAITStandard.new(item.game)
        accum[item.game].append(item, @ait_qualifications.key?(item.id))
      end

    # Avoid having to check permission for every qualification,
    # as they'd all be the same result
    _key, qualification = @ait_qualifications.first
    qualification ||= AITQualification.new(user: @user)
    @can_create_qualifications = policy(qualification).create? if qualification
    @can_destroy_qualifications = policy(qualification).destroy? if qualification
  end

  def recruits
    @recruited_enlistments = @user.recruited_enlistments
      .accepted
      .includes(:unit, user: :rank)
      .order(date: :desc)
      .page(params[:page])
  end

  def reprimands
    @demerits = @user.demerits.includes(author: :rank).order(date: :desc)
    @awols = @user.attendance_records
      .awol
      .order("event.starts_at DESC")
  end

  def extended_loas
    @extended_loas = @user.extended_loas.order(start_date: :desc)
  end

  private

  def find_and_authorize_user
    @user = User.friendly.find(params[:user_id] || params[:id])
    authorize @user
  end

  def find_assignments
    @active_assignments = @user.assignments.active.includes(:unit, :position)
  end
end
