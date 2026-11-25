# A person's own credential: the Office add-in signing them in, or an agent they
# connected over MCP. Two switches, deliberately different — `enabled` is a toggle they
# can flip back, `revoked_at` is final.
class AddinToken < ApplicationRecord
  KINDS = %w[office mcp].freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
  validates :name, length: { maximum: 60 }

  scope :live, -> { where(revoked_at: nil) }
  scope :on, -> { live.where(enabled: true) }
  scope :mcp, -> { where(kind: "mcp") }
  scope :office, -> { where(kind: "office") }
  scope :recent, -> { order(Arel.sql("last_used_at DESC NULLS LAST"), created_at: :desc) }

  # Used within the last quarter of an hour: close enough to call it connected.
  ONLINE_WITHIN = 15.minutes

  def self.issue!(user:, host: nil, platform: nil, kind: "office", name: nil)
    token = "sca_#{SecureRandom.urlsafe_base64(32)}"
    record = create!(user: user, host: host.to_s.first(40).presence, platform: platform.to_s.first(40).presence,
                     kind: kind, name: name.to_s.strip.first(60).presence, token_digest: Source.digest(token))
    [record, token]
  end

  def on? = revoked_at.nil? && enabled?
  def online? = on? && last_used_at.present? && last_used_at > ONLINE_WITHIN.ago
  def state = revoked_at ? "revoked" : enabled? ? (online? ? "online" : "on") : "off"
  def label = name.presence || platform.presence || host.presence || (kind == "mcp" ? "Agent" : "Office add-in")

  def self.authenticate(token)
    return nil if token.blank?
    record = on.includes(:user).find_by(token_digest: Source.digest(token))
    return nil unless record&.user&.active?
    record.update_column(:last_used_at, Time.current) if record.last_used_at.nil? || record.last_used_at < 5.minutes.ago
    record
  end

  def revoke! = update!(revoked_at: Time.current)
  def switch!(on) = update!(enabled: ActiveModel::Type::Boolean.new.cast(on) || false)
end
