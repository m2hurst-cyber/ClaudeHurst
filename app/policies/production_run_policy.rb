class ProductionRunPolicy < ApplicationPolicy
  def create?; ops?; end
  def update?; ops?; end
  def destroy?; admin?; end
end
