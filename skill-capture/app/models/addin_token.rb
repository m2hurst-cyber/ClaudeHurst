class AddinToken < ApplicationRecord
  belongs_to :user

  scope :live, -> { where(revoked_at: nil) }

  def self.issue!(user:, host: nil, platform: nil)
    token = "sca_#{SecureRandom.urlsafe_base64(32)}"
    record = create!(user: user, host: host.to_s.first(40).presence, platform: platform.to_s.first(40).presence,
                     token_digest: Source.digest(token))
    [record, token]
  end

  def self.authenticate(token)
    return nil if token.blank?
    record = live.includes(:user).find_by(token_digest: Source.digest(token))
    return nil unless record&.user&.active?
    record.update_column(:last_used_at, Time.current) if record.last_used_at.nil? || record.last_used_at < 5.minutes.ago
    record
  end

  def revoke! = update!(revoked_at: Time.current)
end
