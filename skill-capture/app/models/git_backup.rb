# A person's own copy of their own skills, in their own repository.
#
# The token is theirs, encrypted at rest, and never shown again after it is saved. What
# gets pushed is bounded by firm policy, not by what the person can see: by default only
# work they wrote or contributed to, because a personal backup button is otherwise a tidy
# way to move the firm's library into a private account.
class GitBackup < ApplicationRecord
  REPO_FORMAT = %r{\A[\w.-]+/[\w.-]+\z}
  HOSTS = %w[github.com].freeze

  belongs_to :user
  encrypts :token

  validates :repo, presence: true, format: { with: REPO_FORMAT, message: "should look like owner/repository" }
  validates :branch, presence: true, format: { with: /\A[\w.\/-]+\z/ }
  validates :host, inclusion: { in: HOSTS }
  validates :path_prefix, format: { with: %r{\A[\w.\-/]*\z}, message: "should be a plain folder path" }
  validates :token, presence: true

  before_validation { self.token_hint = token.to_s.last(4) if token_changed? && token.present? }
  before_validation { self.repo = repo.to_s.strip.delete_prefix("https://github.com/").delete_suffix(".git") }

  scope :active, -> { where(enabled: true) }

  def owner = repo.split("/").first
  def name = repo.split("/").last
  def url = "https://#{host}/#{repo}"
  def commit_url = last_commit_sha && "#{url}/commit/#{last_commit_sha}"
  def ever_pushed? = last_pushed_at.present?

  # Firm policy, then personal scope. Both have to allow it.
  def self.allowed? = Protocol.for("git_backup").enabled
  def self.own_work_only? = Protocol.for("git_backup")["own_work_only"] == 1

  # What this person may take a copy of. Never the whole library unless the firm says so.
  def skills
    scope = Skill.published.visible_to(user)
    return scope.where(stage: %w[local firm market]).order(:name) unless self.class.own_work_only?

    scope.where("skills.published_by_id = :id OR jsonb_exists(COALESCE(skills.source->'contributor_keys', '[]'::jsonb), :actor)",
                id: user.id, actor: "user:#{user.id}").order(:name)
  end
end
