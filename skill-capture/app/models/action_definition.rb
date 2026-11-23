# What an action key means, in words a colleague (or the LLM) can follow.
# Collectors may register labels with their events; admins can edit them.
class ActionDefinition < ApplicationRecord
  belongs_to :source, optional: true

  validates :key, presence: true, uniqueness: true
  validates :label, presence: true

  def self.label_for(key)
    find_by(key: key)&.label || humanize_key(key)
  end

  def self.labels_for(keys)
    known = where(key: keys).pluck(:key, :label).to_h
    keys.index_with { |k| known[k] || humanize_key(k) }
  end

  def self.domain_for(key) = find_by(key: key)&.domain

  def self.humanize_key(key)
    key.to_s.split(/[.:#\/]/).reject(&:blank?).map { |p| p.tr("_-", "  ") }.join(" — ").capitalize
  end
end
