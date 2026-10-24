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

  # Members see their unit and every unit below it: a squad member their
  # squad, anyone in a platoon or company HQ (leaders and clerks alike)
  # everything under it, so every link on a page they can open works. MPs and
  # admins see every unit.
  def guests?
    return false unless user&.member?
    return true if user.has_permission?("admin") || user.has_permission?("note_view_mp")

    user.active_assignments.exists?(unit_id: record.path_ids)
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
