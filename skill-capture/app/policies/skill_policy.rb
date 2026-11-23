class SkillPolicy < ApplicationPolicy
  # Published skills are institutional memory: everyone signed in can read them.
  def index? = signed_in?
  def show? = signed_in?
  def download? = signed_in?
  # Only the area's reviewers (or admins) change official skills.
  def update? = user.present? && user.reviews?(record.domain)
  def deprecate? = admin?
end
