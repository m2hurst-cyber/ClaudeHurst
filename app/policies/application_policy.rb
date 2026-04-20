class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def admin?
    user&.admin?
  end

  def sales?
    user&.sales? || admin?
  end

  def ops?
    user&.ops? || admin?
  end

  def finance?
    user&.finance? || admin?
  end

  def index?; signed_in?; end
  def show?; signed_in?; end
  def create?; signed_in?; end
  def new?; create?; end
  def update?; signed_in?; end
  def edit?; update?; end
  def destroy?; admin?; end

  def signed_in?
    user.present?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.all
    end

    private

    attr_reader :user, :scope
  end
end
