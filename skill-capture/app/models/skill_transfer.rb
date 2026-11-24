# Person-to-person: send one skill or a selection to a coworker, free or for credits, without promoting
# it. The recipient accepts (paying the price from their credits, if any) or declines; on acceptance each
# skill is granted to them at its current stage.
class SkillTransfer < ApplicationRecord
  STATUSES = %w[offered accepted declined cancelled expired].freeze
  MAX_ITEMS = 25
  MAX_PRICE = 10_000
  TTL = 14.days

  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"
  has_many :grants, class_name: "SkillGrant", foreign_key: :transfer_id, dependent: :nullify
  has_many :credit_entries, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :price, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_PRICE }
  validates :message, length: { maximum: 1000 }
  validate :items_ok, on: :create

  before_validation { self.expires_at ||= TTL.from_now }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(status: "offered").where("expires_at > ?", Time.current) }

  def free? = price.to_d.zero?
  def names = items.map { |i| i["name"] }
  def pending? = status == "offered" && expires_at.future?
  def involves?(u) = u && [sender_id, recipient_id].include?(u.id)
  def label = items.size == 1 ? items.first["title"] : "#{items.size} skills"

  # What a person may send: skills they can see that are shared with the firm or beyond, local skills they
  # authored, review, or received with permission to forward. Selling needs authorship (or review rights).
  def self.sendable?(skill, user)
    return false unless skill&.visible_to?(user)
    skill.shared? || owns?(skill, user) || SkillGrant.exists?(user: user, skill_name: skill.name, can_forward: true)
  end

  def self.sellable?(skill, user) = owns?(skill, user)

  def self.owns?(skill, user)
    user.admin? || user.reviews?(skill.domain) || skill.published_by_id == user.id ||
      Array(skill.source["contributor_keys"]).include?(user.actor_key) ||
      SkillCandidate.where(requested_by: user, skill_id: Skill.where(name: skill.name).select(:id)).exists?
  end

  def self.offer!(sender:, recipient:, names:, price: 0, message: nil, allow_forward: false)
    names = Array(names).map(&:to_s).reject(&:blank?).uniq
    skills = names.map { |n| Skill.current(n) or raise ActiveRecord::RecordInvalid.new(new.tap { |t| t.errors.add(:base, "No skill named #{n}") }) }
    t = new(sender: sender, recipient: recipient, price: price.to_d.round(2), message: message.to_s.strip.presence, allow_forward: allow_forward,
            items: skills.map { |s| { "name" => s.name, "version" => s.version, "title" => s.title, "stage" => s.stage } })
    t.save!
    Notification.create!(user: recipient, subject: t, kind: "skill_transfer", title: "#{sender.name} sent you #{t.label}",
                         body: t.free? ? "Free. Accept to add it to your library." : "#{t.price.to_s('F')} credits. Accept to pay and add it to your library.",
                         url: Rails.application.routes.url_helpers.transfer_path(t))
    AuditLog.record("transfer.offered", user: sender, subject: t, to: recipient.id, skills: t.names, price: t.price.to_s("F"))
    t
  end

  def accept!(by:)
    raise Error, "Only #{recipient.name} can accept this." unless by.id == recipient_id
    transaction do
      lock!
      raise Error, "This offer is #{status == 'offered' ? 'expired' : status}." unless pending?
      unless free?
        User.where(id: [sender_id, recipient_id].sort).lock.to_a # serialize balances for both sides
        raise Error, "You have #{recipient.credits.to_s('F')} credits; this costs #{price.to_s('F')}." if recipient.credits < price
        CreditEntry.create!(user: recipient, amount: -price, reason: "Bought #{label} from #{sender.name}", skill_transfer: self)
        CreditEntry.create!(user: sender, amount: price, reason: "Sold #{label} to #{recipient.name}", skill_transfer: self)
      end
      items.each do |i|
        g = SkillGrant.find_or_initialize_by(user: recipient, skill_name: i["name"])
        g.update!(version: i["version"], transfer: self, granted_by: sender, can_forward: g.can_forward || allow_forward)
      end
      update!(status: "accepted", responded_at: Time.current)
    end
    Notification.create!(user: sender, subject: self, kind: "skill_transfer", title: "#{recipient.name} accepted #{label}",
                         body: free? ? nil : "#{price.to_s('F')} credits paid to you.", url: Rails.application.routes.url_helpers.transfer_path(self))
    AuditLog.record("transfer.accepted", user: by, subject: self, price: price.to_s("F"))
    self
  end

  def decline!(by:)
    raise Error, "Only #{recipient.name} can decline this." unless by.id == recipient_id
    respond!("declined", by)
  end

  def cancel!(by:)
    raise Error, "Only #{sender.name} can withdraw this." unless by.id == sender_id
    respond!("cancelled", by)
  end

  class Error < StandardError; end

  private

  def respond!(st, by)
    with_lock do
      raise Error, "This offer is #{status == 'offered' ? 'expired' : status}." unless pending?
      update!(status: st, responded_at: Time.current)
    end
    AuditLog.record("transfer.#{st}", user: by, subject: self)
    self
  end

  def items_ok
    errors.add(:base, "Choose at least one skill") if items.empty?
    errors.add(:base, "At most #{MAX_ITEMS} skills per transfer") if items.size > MAX_ITEMS
    errors.add(:recipient, "can't be you") if sender_id == recipient_id
    return if sender.nil?
    skills = items.map { |i| Skill.current(i["name"]) }
    skills.compact.each do |s|
      errors.add(:base, "You can't send “#{s.title}”: send skills you authored or review, or ones shared with the firm") unless self.class.sendable?(s, sender)
      errors.add(:base, "You can only charge for skills you authored or review (“#{s.title}”)") if !free? && !self.class.sellable?(s, sender)
    end
    already = recipient && !free? ? skills.compact.select { |s| s.visible_to?(recipient) } : []
    errors.add(:base, "#{recipient.name} can already use #{already.map(&:title).to_sentence}: send it free, or leave it out") if already.present?
  end
end
