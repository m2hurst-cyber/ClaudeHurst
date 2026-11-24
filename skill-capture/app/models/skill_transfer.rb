# Person-to-person transfer as an escrow contract. Nothing moves up a level.
#
#   offered   the sender's leg is deposited: each skill's exact SKILL.md is snapshotted and fingerprinted
#             (sha256), and the terms (parties, skills, fingerprints, price, expiry) are hashed
#   funded    the buyer's leg is deposited: the price moves from their balance into escrow (paid offers)
#   settled   both legs verified, then crossed in one transaction: credits released to the sender, the
#             skills granted to the buyer exactly as fingerprinted
#   refunded  a leg failed verification (the skill changed, was withdrawn, or the sender lost the right
#             to send it): the buyer's credits go back
#   declined · cancelled · expired   before funding; nothing was held but the snapshot
#
# Every step is appended to a hash-chained contract log (each entry hashes the one before), so the
# history can be checked but not quietly edited.
class SkillTransfer < ApplicationRecord
  STATUSES = %w[offered funded settled refunded declined cancelled expired].freeze
  OPEN = %w[offered funded].freeze
  MAX_ITEMS = 25
  MAX_PRICE = 10_000
  TTL = 14.days

  class Error < StandardError; end

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
  def settled? = status == "settled"
  def involves?(u) = u && [sender_id, recipient_id].include?(u.id)
  def label = items.size == 1 ? items.first["title"] : "#{items.size} skills"
  def released = credit_entries.where(kind: "escrow_release").sum(:amount)
  def escrow_balance = -credit_entries.where(kind: %w[escrow_hold escrow_refund]).sum(:amount) - released

  # ---------- rights ----------
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

  def self.fingerprint(text) = Digest::SHA256.hexdigest(text.to_s)
  # Key-sorted JSON, so a hash survives storage (jsonb reorders keys).
  def self.canonical(v)
    case v
    when Hash then "{#{v.map { |k, x| [k.to_s, x] }.sort_by(&:first).map { |k, x| "#{k.to_json}:#{canonical(x)}" }.join(',')}}"
    when Array then "[#{v.map { |x| canonical(x) }.join(',')}]"
    else v.to_json
    end
  end
  # What is being sold: the skill's content at that version (not its stage, which may change).
  def self.content_fingerprint(s) = fingerprint({ name: s.name, version: s.version, title: s.title, description: s.description, body: s.body }.to_json)

  # ---------- 1. offer: the sender's leg goes into escrow ----------
  def self.offer!(sender:, recipient:, names:, price: 0, message: nil, allow_forward: false)
    names = Array(names).map(&:to_s).reject(&:blank?).uniq
    skills = names.map { |n| Skill.current(n) or raise ActiveRecord::RecordInvalid.new(new.tap { |t| t.errors.add(:base, "No skill named #{n}") }) }
    t = new(sender: sender, recipient: recipient, price: price.to_d.round(2), message: message.to_s.strip.presence, allow_forward: allow_forward,
            items: skills.map { |s| md = s.to_skill_md; { "name" => s.name, "version" => s.version, "title" => s.title, "stage" => s.stage, "sha256" => content_fingerprint(s), "skill_md" => md } })
    t.terms_hash = fingerprint({ sender: sender.id, recipient: recipient&.id, items: t.items.map { |i| i.slice("name", "version", "sha256") },
                                 price: t.price.to_s("F"), expires_at: t.expires_at&.utc&.iso8601, forward: allow_forward }.to_json)
    transaction do
      t.save!
      t.log!("terms_agreed_by_sender", sender, terms: t.terms_hash)
      t.log!("skill_leg_deposited", sender, skills: t.items.map { |i| "#{i['name']}@v#{i['version']}:#{i['sha256'].first(12)}" })
    end
    Notification.create!(user: recipient, subject: t, kind: "skill_transfer", title: "#{sender.name} sent you #{t.label}",
                         body: t.free? ? "Free. Accept to add it to your library." : "#{t.price.to_s('F')} credits, held in escrow until the skills are delivered.",
                         url: Rails.application.routes.url_helpers.transfer_path(t))
    AuditLog.record("transfer.offered", user: sender, subject: t, to: recipient.id, skills: t.names, price: t.price.to_s("F"), terms: t.terms_hash)
    t
  end

  # Accept = fund the buyer's leg (if priced), then cross.
  def accept!(by:)
    fund!(by: by) unless free?
    with_lock { raise Error, "This offer is #{state_word}." unless pending? } if free?
    cross!(by: by)
  end

  # ---------- 2. the buyer's leg goes into escrow ----------
  def fund!(by:)
    raise Error, "Only #{recipient.name} can accept this." unless by.id == recipient_id
    transaction do
      lock!
      raise Error, "This offer is #{state_word}." unless pending?
      User.where(id: [sender_id, recipient_id].sort).lock.to_a
      bal = recipient.credits
      raise Error, "You have #{bal.to_s('F')} credits; this costs #{price.to_s('F')}." if bal < price
      CreditEntry.create!(user: recipient, amount: -price, kind: "escrow_hold", reason: "Escrow for #{label} from #{sender.name}", skill_transfer: self)
      update!(status: "funded", funded_at: Time.current)
      log!("terms_agreed_by_buyer", by, terms: terms_hash)
      log!("payment_leg_deposited", by, credits: price.to_s("F"))
    end
    self
  end

  # ---------- 3. verify both legs, then swap atomically (or refund) ----------
  def cross!(by: nil)
    problems = []
    transaction do
      lock!
      ready = free? ? status == "offered" : status == "funded"
      raise Error, "This offer is #{state_word}." unless ready
      problems = verify_skill_leg
      if problems.empty? && (free? || escrow_balance == price)
        unless free?
          CreditEntry.create!(user: sender, amount: price, kind: "escrow_release", reason: "Sold #{label} to #{recipient.name} (escrow released)", skill_transfer: self)
        end
        items.each do |i|
          g = SkillGrant.find_or_initialize_by(user: recipient, skill_name: i["name"])
          g.update!(version: i["version"], transfer: self, granted_by: sender, can_forward: g.can_forward || allow_forward)
        end
        update!(status: "settled", settled_at: Time.current, responded_at: Time.current)
        log!("crossed", by, delivered: names, paid: price.to_s("F"))
      else
        problems << "escrow holds #{escrow_balance.to_s('F')}, expected #{price.to_s('F')}" if problems.empty?
        refund_inside!(by, problems)
      end
    end
    notify_settlement(problems)
    raise Error, "Not delivered: #{problems.to_sentence}. #{free? ? '' : 'Your credits were refunded.'}".strip if problems.any?
    self
  end

  def decline!(by:)
    raise Error, "Only #{recipient.name} can decline this." unless by.id == recipient_id
    close!("declined", by)
  end

  def cancel!(by:)
    raise Error, "Only #{sender.name} can withdraw this." unless by.id == sender_id
    close!("cancelled", by)
  end

  # Offers past their expiry: unfunded ones expire, funded ones (a crossing that never completed) refund.
  def self.sweep!
    where(status: "offered").where("expires_at <= ?", Time.current).find_each { |t| t.with_lock { t.update!(status: "expired"); t.log!("expired", nil) if t.status == "expired" } }
    where(status: "funded").where("funded_at <= ?", 1.hour.ago).find_each { |t| t.with_lock { t.send(:refund_inside!, nil, ["the swap didn't complete"]) if t.status == "funded" } }
  end

  # ---------- the contract log ----------
  def log!(event, user, **detail)
    prev = contract_log.last&.dig("hash") || terms_hash.to_s
    entry = { "seq" => contract_log.size + 1, "event" => event, "at" => Time.current.utc.iso8601(3), "by" => user&.name, "detail" => detail.deep_stringify_keys, "prev" => prev }
    entry["hash"] = self.class.fingerprint(self.class.canonical(entry))
    update_columns(contract_log: contract_log + [entry])
    entry
  end

  def log_intact?
    prev = terms_hash.to_s
    contract_log.all? do |e|
      ok = e["prev"] == prev && e["hash"] == self.class.fingerprint(self.class.canonical(e.except("hash")))
      prev = e["hash"]
      ok
    end
  end

  def state_word = status == "offered" && !pending? ? "expired" : status
  def delivered_md(name) = settled? && items.find { |i| i["name"] == name }&.dig("skill_md")

  private

  def verify_skill_leg
    items.filter_map do |i|
      s = Skill.find_by(name: i["name"], version: i["version"])
      if i["sha256"].blank? then "#{i['title']} was offered before escrow existed (no fingerprint); ask #{sender.name} to send it again"
      elsif s.nil? then "#{i['title']} v#{i['version']} no longer exists"
      elsif s.status == "deprecated" then "#{i['title']} was withdrawn"
      elsif self.class.content_fingerprint(s) != i["sha256"] then "#{i['title']} changed since it was offered"
      elsif !self.class.sendable?(s, sender) then "#{sender.name} can no longer send #{i['title']}"
      end
    end
  end

  def refund_inside!(by, problems)
    held = escrow_balance
    CreditEntry.create!(user: recipient, amount: held, kind: "escrow_refund", reason: "Refund: #{label} not delivered", skill_transfer: self) if held.positive?
    update!(status: "refunded", responded_at: Time.current)
    log!("refunded", by, reasons: problems, credits: held.to_s("F"))
  end

  def close!(st, by)
    with_lock do
      raise Error, "This offer is #{state_word}." unless pending?
      update!(status: st, responded_at: Time.current)
      log!(st, by)
    end
    AuditLog.record("transfer.#{st}", user: by, subject: self)
    self
  end

  def notify_settlement(problems)
    url = Rails.application.routes.url_helpers.transfer_path(self)
    if problems.empty?
      Notification.create!(user: sender, subject: self, kind: "skill_transfer", title: "#{recipient.name} accepted #{label}", body: free? ? nil : "#{price.to_s('F')} credits released to you from escrow.", url: url)
      AuditLog.record("transfer.settled", user: recipient, subject: self, price: price.to_s("F"))
    else
      [sender, recipient].each { |u| Notification.create!(user: u, subject: self, kind: "skill_transfer", title: "#{label} not delivered", body: problems.to_sentence, url: url) }
      AuditLog.record("transfer.refunded", user: recipient, subject: self, reasons: problems)
    end
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
