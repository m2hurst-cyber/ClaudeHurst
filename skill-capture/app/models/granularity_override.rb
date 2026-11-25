# One area or one person wanting their work cut finer or coarser than the firm's setting.
# A person's own setting wins over their area's, and an area's over the firm's.
class GranularityOverride < ApplicationRecord
  SCOPES = %w[domain user].freeze

  validates :scope, inclusion: { in: SCOPES }
  validates :scope_key, presence: true, uniqueness: { scope: :scope }
  validates :level, inclusion: { in: Capture::Granularity::RANGE }

  scope :domains, -> { where(scope: "domain").order(:scope_key) }
  scope :users, -> { where(scope: "user") }

  def self.level_for(domain: nil, user: nil)
    if user
      personal = find_by(scope: "user", scope_key: user.id.to_s)&.level
      return personal if personal
    end
    find_by(scope: "domain", scope_key: domain)&.level if domain.present?
  end

  def self.set!(scope, key, level)
    return where(scope: scope, scope_key: key.to_s).delete_all if level.blank?
    find_or_initialize_by(scope: scope, scope_key: key.to_s).update!(level: level.to_i)
  end

  def label = Capture::Granularity.label(level)
end
