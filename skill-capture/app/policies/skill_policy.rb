class SkillPolicy < ApplicationPolicy
  # Published skills are institutional memory: everyone signed in can read them.
  def index? = signed_in?
  # Sandbox (local) skills are visible only to their people; firm and market to everyone.
  def show? = signed_in? && record.visible_to?(user)
  def download? = show?
  def vote? = show?
  def compare? = show?
  # Only the area's reviewers (or admins) change official skills.
  def update? = show? && user.reviews?(record.domain)
  def deprecate? = admin?
end
