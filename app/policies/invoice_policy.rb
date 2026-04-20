class InvoicePolicy < ApplicationPolicy
  def create?; finance? || sales?; end
  def update?; finance? || sales?; end
  def void?; finance?; end
  def destroy?; admin?; end
end
