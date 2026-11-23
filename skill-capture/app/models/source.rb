# A registered activity collector (Office add-in, Slack bot, IDE plugin, browser agent, chat log export...).
# Collectors authenticate to the ingest API with a bearer token shown once at creation.
class Source < ApplicationRecord
  KINDS = %w[office slack email ide browser chat custom].freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :usage_events, dependent: :delete_all

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(active: true) }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # Returns [source, raw_token]. Only the digest is stored.
  def self.issue!(**attrs)
    token = "sc_#{SecureRandom.urlsafe_base64(32)}"
    source = create!(**attrs, token_digest: digest(token), token_prefix: token.first(10))
    [source, token]
  end

  def self.authenticate(token)
    return nil if token.blank?
    active.find_by(token_digest: digest(token))
  end
end
