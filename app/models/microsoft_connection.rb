class MicrosoftConnection < ApplicationRecord
  include Discard::Model

  belongs_to :user

  validates :tenant_id, :microsoft_user_id, :email, presence: true
  validates :user_id, uniqueness: true

  def connected?
    integration_payload.present?
  end

  def expired?
    integration_expires_at.blank? || integration_expires_at <= 2.minutes.from_now
  end

  def scopes
    granted_scopes.to_s.split
  end
end
