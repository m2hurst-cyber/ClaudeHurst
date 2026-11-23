class SkillPolicy < ApplicationPolicy
  # Published skills are institutional memory: everyone signed in can find and use them.
  def index? = signed_in?
  def show? = signed_in?
  def download? = signed_in?
  # Only the process owners for the skill's domain (or admins) change official skills.
  def update? = admin? || (user.present? && record.domain.present? && user.role == record.domain)
  def deprecate? = admin?
  def create? = false
  def destroy? = false
end
