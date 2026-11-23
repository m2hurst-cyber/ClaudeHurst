# Where events come from: one built-in source per Office app (the add-in authenticates
# each person with an AddinToken) plus optional server-side integrations with their own token.
class Source < ApplicationRecord
  KINDS = %w[excel word powerpoint outlook integration].freeze
  # The add-in's events are filed under one built-in source per Office app.
  OFFICE_HOSTS = { "Excel" => "excel", "Word" => "word", "PowerPoint" => "powerpoint" }.freeze

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

  # Built-in source for the Office add-in in a given host. Not token-authenticated:
  # add-in clients authenticate per person with an AddinToken.
  def self.for_office_host(host)
    kind = OFFICE_HOSTS.fetch(host.to_s) { raise ArgumentError, "unsupported Office host: #{host.inspect}" }
    find_or_create_by!(kind: kind, name: "Skill Capture for #{host}") do |s|
      s.token_digest = digest(SecureRandom.hex(32)) # unusable placeholder
      s.token_prefix = "builtin"
    end
  end

  def builtin? = token_prefix == "builtin"

  def self.authenticate(token)
    return nil if token.blank?
    active.where.not(token_prefix: "builtin").find_by(token_digest: digest(token))
  end
end
