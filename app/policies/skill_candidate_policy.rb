class SkillCandidatePolicy < ApplicationPolicy
  def index? = signed_in?
  def show? = admin? || record.reviewable_by?(user) || contributor? || requester?
  def create? = signed_in?
  def update? = record.reviewable_by?(user) || (requester? && record.open?)
  def generate_draft? = update?
  def approve? = record.reviewable_by?(user)
  def reject? = approve?
  def dismiss? = approve?
  def destroy? = false

  private

  def contributor? = Array(record.contributor_ids).include?(user&.id)
  def requester? = record.requested_by_id.present? && record.requested_by_id == user&.id

  class Scope < Scope
    def resolve
      return scope.all if user.admin?
      scope.where(domain: user.role)
           .or(scope.where("skill_candidates.contributor_ids @> ?", [user.id].to_json))
           .or(scope.where(requested_by_id: user.id))
    end
  end
end
