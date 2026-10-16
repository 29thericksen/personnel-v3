class UnitPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def attendance?
    user&.member?
  end

  # Members see the unit they're assigned to. Leaders also see the units
  # they're responsible for: a squad's leadership its squad, a platoon HQ its
  # platoon and squads, a company HQ its company. MPs and admins see every unit.
  def guests?
    return false unless user&.member?
    return true if user.has_permission?("admin") || user.has_permission?("note_view_mp")
    return true if user.active_assignments.exists?(unit_id: record.id)

    %w[note_view_sq note_view_pl note_view_co].any? do |permission|
      user.has_permission_on_unit?(permission, record)
    end
  end

  def awols?
    user&.member?
  end

  def missing_awards?
    user&.has_permission_on_unit?("awarding_add", record) ||
      user&.has_permission?("admin")
  end

  def stats?
    user&.member?
  end

  def recruits?
    user&.member?
  end

  def discharges?
    user&.member?
  end

  def new?
    user&.has_permission?("unit_add") ||
      user&.has_permission?("admin")
  end

  def create?
    new?
  end

  def update?
    new?
  end

  def destroy?
    user&.has_permission?("admin")
  end

  def graduate?
    user&.has_permission?("admin")
  end
end
