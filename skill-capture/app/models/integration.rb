# A business system this firm has actually connected: the catalogue entry it came from,
# the token its events arrive on, and whether it is listening right now.
#
# No credentials live here. Events are pushed to us on a Source token rather than pulled
# with the firm's ERP password, which means connecting one cannot read anything we were
# not sent, and switching it off is immediate and complete.
class Integration < ApplicationRecord
  encrypts :credentials

  belongs_to :source, optional: true
  belongs_to :connected_by, class_name: "User", optional: true

  validates :provider, presence: true, uniqueness: true
  validate { errors.add(:provider, "is not in the catalogue") unless definition }

  scope :on, -> { where(enabled: true) }
  scope :recent, -> { order(Arel.sql("last_event_at DESC NULLS LAST"), created_at: :desc) }

  LIVE_WITHIN = 1.hour

  def definition = Capture::Integrations.find(provider)
  def name = label.presence || definition&.name || provider
  def live? = enabled? && last_event_at.present? && last_event_at > LIVE_WITHIN.ago
  def state = enabled? ? (live? ? "live" : "quiet") : "off"
  def switch!(on) = update!(enabled: ActiveModel::Type::Boolean.new.cast(on) || false)

  # Connecting issues the token the vendor's webhook or middleware posts events to, and
  # teaches the system this provider's step vocabulary.
  def self.connect!(provider_key, user:, label: nil)
    definition = Capture::Integrations.find(provider_key) or raise ArgumentError, "unknown provider #{provider_key}"
    source, token = Source.issue!(name: label.presence || definition.name, kind: "integration", created_by: user)
    integration = create!(provider: definition.key, label: label.presence, source: source, connected_by: user)
    Capture::Integrations.register_vocabulary!(definition)
    AuditLog.record("integration.connected", user: user, subject: integration, provider: definition.key)
    [integration, token]
  end

  def disconnect!(user)
    source&.update!(active: false)
    AuditLog.record("integration.disconnected", user: user, subject: self, provider: provider)
    destroy!
  end

  def credentials_hash = credentials.present? ? (JSON.parse(credentials) rescue {}) : {}
  def connected_to_api? = credentials_hash["refresh_token"].present?

  # Intuit rotates the refresh token on every use. Storing the new one is not optional:
  # miss it once and the connection dies quietly a few weeks later.
  def store_tokens!(tokens)
    update!(credentials: JSON.generate({ "access_token" => tokens[:access_token], "refresh_token" => tokens[:refresh_token] }),
            token_expires_at: tokens[:expires_at])
  end

  # Kept in step with what has actually arrived on this integration's token.
  def refresh_counts!
    return if source.nil?
    update!(event_count: UsageEvent.where(source_id: source_id).count,
            last_event_at: UsageEvent.where(source_id: source_id).maximum(:occurred_at))
  end
end
