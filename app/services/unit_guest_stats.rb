# Guesting statistics across a unit's subtree, for the leaders' Guest stats
# tab. Members are the active members of the subtree's active units; guesting
# between sub-units counts.
#
# #unit_rows covers every unit with members assigned directly to it (squads,
# plus HQ elements), with how many drills its members guested in the last 30,
# 60 and 90 days. The guester and host rankings cover the chosen period only.
class UnitGuestStats
  PERIODS = EventGuest::COUNT_PERIODS
  RANKING_SIZE = 5

  # guested is {30 => count, 60 => count, 90 => count} of drills guested
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
      counts = EventGuest.past.at_drills
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

  # Every unit in the subtree that held drills in the period, ranked by
  # guests per drill
  def hosts
    @hosts ||= begin
      events = Event.for_unit(unit.subtree).past.drills.where(starts_at: since..)
      drills = events.group(:unit_id).count
      guests = EventGuest.joins(:event).merge(events).group("events.unit_id").count
      units = Unit.where(id: drills.keys).index_by(&:id)
      drills
        .map { |unit_id, count| Host.new(units[unit_id], guests.fetch(unit_id, 0), count) }
        .sort_by { |host| [-host.per_drill, -host.guests, host.unit.abbr] }
    end
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

  # {member_id => EventGuest.period_counts row}
  def counts_by_member
    @counts_by_member ||= EventGuest
      .where(member_id: all_member_ids)
      .period_counts
      .select(:member_id)
      .group(:member_id)
      .index_by(&:member_id)
  end

  def guested_counts(member_ids)
    PERIODS.index_with do |days|
      member_ids.sum { |id| counts_by_member[id]&.public_send(:"last_#{days}_days") || 0 }
    end
  end
end
