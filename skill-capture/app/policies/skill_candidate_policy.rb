class SkillCandidatePolicy < ApplicationPolicy
  def index? = signed_in?
  def show? = admin? || record.reviewable_by?(user) || requester?
  def create? = signed_in?
  def update? = record.open? && (record.reviewable_by?(user) || requester?)
  def generate_draft? = update?
  def approve? = record.open? && record.reviewable_by?(user)
  def reject? = approve?
  def dismiss? = approve?

  private

  def requester? = record.requested_by_id.present? && record.requested_by_id == user&.id

  class Scope < Scope
    def resolve
      return scope.all if user.admin?
      mine = scope.where(requested_by_id: user.id)
      user.reviewer? ? mine.or(scope.where(domain: user.domains)) : mine
    end
  end
end
