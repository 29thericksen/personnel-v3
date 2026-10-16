# Guesting statistics across a unit's subtree, for the leaders' Guest stats
# tab. Members are the active members of the subtree's active units; guesting
# between sub-units counts.
#
# #unit_rows covers every unit with members assigned directly to it (squads,
# plus HQ elements), with how many of them guested in the last 30, 60 and 90
# days. The guester and host rankings cover the chosen period only.
class UnitGuestStats
  PERIODS = EventGuest::COUNT_PERIODS
  RANKING_SIZE = 5

  # guested is {30 => count, 60 => count, 90 => count} of members who guested
  UnitRow = Struct.new(:unit, :members, :guested)
  Guester = Struct.new(:user, :count)
  Host = Struct.new(:unit, :guests, :drills) do
    def per_drill
      guests.fdiv(drills)
    end
  end

  attr_reader :unit, :period

  def initialize(unit, period:)
    @unit = unit
    @period = period
  end

  def unit_rows
    @unit_rows ||= tree_units.filter_map do |row_unit|
      member_ids = member_ids_by_unit[row_unit.id]
      next if member_ids.blank?

      UnitRow.new(row_unit, member_ids.size, guested_counts(member_ids))
    end
  end

  def total_row
    @total_row ||= UnitRow.new(unit, all_member_ids.size, guested_counts(all_member_ids))
  end

  def top_guesters
    @top_guesters ||= begin
      counts = EventGuest.past
        .where(member_id: all_member_ids)
        .where(events: {starts_at: since..})
        .group(:member_id)
        .count
      User.where(id: counts.keys).includes(:rank)
        .map { |user| Guester.new(user, counts[user.id]) }
        .sort_by { |guester| [-guester.count, -guester.user.rank.order, guester.user.last_name] }
        .first(RANKING_SIZE)
    end
  end

  # Units in the subtree that held drills in the period, ranked by guests per drill
  def top_hosts
    hosts
      .select { |host| host.guests.positive? }
      .sort_by { |host| [-host.per_drill, -host.guests, host.unit.abbr] }
      .first(RANKING_SIZE)
  end

  def bottom_hosts
    hosts.sort_by { |host| [host.per_drill, host.guests, host.unit.abbr] }.first(RANKING_SIZE)
  end

  private

  def since
    @since ||= period.days.ago
  end

  # Active units in roster order
  def tree_units
    flatten_tree(unit.subtree.active.arrange(order: :order))
  end

  def flatten_tree(tree)
    tree.flat_map { |tree_unit, children| [tree_unit, *flatten_tree(children)] }
  end

  def member_ids_by_unit
    @member_ids_by_unit ||= Assignment.active
      .where(unit_id: unit.subtree.active.ids)
      .distinct
      .pluck(:unit_id, :member_id)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last) }
  end

  def all_member_ids
    @all_member_ids ||= member_ids_by_unit.values.flatten.uniq
  end

  def last_guested_at
    @last_guested_at ||= EventGuest.past
      .where(member_id: all_member_ids)
      .group(:member_id)
      .maximum("events.starts_at")
  end

  def guested_counts(member_ids)
    PERIODS.index_with do |days|
      cutoff = days.days.ago
      member_ids.count { |id| last_guested_at.key?(id) && last_guested_at[id] >= cutoff }
    end
  end

  def hosts
    @hosts ||= begin
      events = Event.for_unit(unit.subtree).past.where(starts_at: since..)
      drills = events.group(:unit_id).count
      guests = EventGuest.joins(:event).merge(events).group("events.unit_id").count
      units = Unit.where(id: drills.keys).index_by(&:id)
      drills.map { |unit_id, count| Host.new(units[unit_id], guests.fetch(unit_id, 0), count) }
    end
  end
end
