class SkillPolicy < ApplicationPolicy
  # Published skills are institutional memory: everyone signed in can read them.
  def index? = signed_in?
  # Sandbox (local) skills are visible only to their people; firm and market to everyone.
  def provenance? = show?

  def show? = signed_in? && record.visible_to?(user)
  def download? = show?
  def vote? = show?
  def compare? = show?
  # Only the area's reviewers (or admins) change official skills.
  def update? = show? && user.reviews?(record.domain)
  def deprecate? = admin?
  def audience? = admin? && record.stage == "market"
  # Classification (field, apps): the area's reviewers, the publisher, contributors, admins.
  def classify? = show? && (update? || record.published_by_id == user.id || Array(record.source["contributor_keys"]).include?(user.actor_key))
end
