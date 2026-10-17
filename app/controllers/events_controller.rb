class EventsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize Event

    date_param = params.fetch(:start_date, Date.today).to_date
    start_date = date_param.beginning_of_month.beginning_of_week
    end_date = date_param.end_of_month.end_of_week

    @events = Event.where(starts_at: start_date..end_date)
      .includes(:unit)
      .order(:starts_at)

    @view_by = params.fetch(:view_by, "week")
  end

  def show
    @event = Event.find(params[:id])
    @roster = EventRoster.new(@event)
    @guests = guests_for(@event)
    authorize @event
  end

  def edit_aar
    @event = Event.find(params[:id])
    @attended_user_ids = @event.attendance_records.where(attended: true).pluck(:member_id)
    @roster = EventRoster.new(@event, expected_only: true)
    @guests = guests_for(@event)
    authorize @event, :aar?
  end

  def guest_search
    @event = Event.find(params[:id])
    authorize @event, :aar?

    candidates = @event.guest_candidates(params[:q]).map do |user|
      {id: user.id, name: user.short_name, detail: helpers.guest_status_detail(user)}
    end

    render json: candidates
  end

  def update_aar
    @event = Event.find(params[:id])
    authorize @event, :aar?

    @event.report = params[:event][:report]
    @event.reporter = current_user unless @event.aar_posted?

    attended_ids = params[:event][:user_ids].reject(&:empty?).map(&:to_i)

    # One transaction, so a failed save leaves attendance and guests untouched
    # rather than half-written.
    saved = Event.transaction do
      @event.update_attendance(attended_ids)
      @event.excuse_users_on_extended_loa

      # Only touch guests when the form sent the field, so requests without
      # it leave existing guests alone.
      if params[:event].key?(:guest_ids)
        @event.update_guests(Array(params[:event][:guest_ids]))
      end

      @event.save || raise(ActiveRecord::Rollback)
    end

    if saved
      redirect_to @event, notice: "AAR was successfully updated."
    else
      @attended_user_ids = @event.attendance_records.where(attended: true).pluck(:member_id)
      @roster = EventRoster.new(@event, expected_only: true)
      @guests = guests_for(@event)
      render :edit_aar
    end
  end

  def loa
    @event = Event.find(params[:id])
    authorize @event

    if @event.posted_loa?(current_user)
      if @event.cancel_loa(current_user)
        redirect_to @event, notice: "LOA was successfully cancelled."
      end
    elsif @event.post_loa(current_user)
      redirect_to @event, notice: "LOA was successfully posted."
    end
  end

  private

  def guests_for(event)
    event.guests.preload(:discharges, active_assignments: :unit)
  end
end
