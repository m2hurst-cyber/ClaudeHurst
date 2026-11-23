# The rules behind save / extend / branch prompts and rest stops. One row per key, admin-editable.
#
#   save     a workflow you repeat that no skill covers           → "Save it as a skill"
#   extend   you finish a skill, then keep doing the same steps    → "Extend the skill (new version)"
#   branch   you start and end a skill but do the middle your way  → "Branch it (a variant)"
#   rest_stop  automatic snapshots of skills, so any version or branch can be reverted
#   evaluation how often the triggers run per person, and the AI's bar for raising a prompt
class Protocol < ApplicationRecord
  DEFAULTS = {
    "save" => { "min_repeats" => 3, "min_steps" => 3, "lookback_days" => 14, "snooze_days" => 3 },
    "extend" => { "min_repeats" => 2, "max_added_steps" => 4, "lookback_days" => 14, "snooze_days" => 3 },
    "branch" => { "min_repeats" => 2, "max_extra_steps" => 3, "lookback_days" => 14, "snooze_days" => 3 },
    "rest_stop" => { "daily" => true, "keep_auto" => 30 },
    # How often the triggers run per person, and how sure the AI must be before anyone is prompted.
    "evaluation" => { "interval_minutes" => 10, "min_confidence" => 60 }
  }.freeze
  LABELS = { "save" => "Save", "extend" => "Extend", "branch" => "Branch", "rest_stop" => "Rest stops", "evaluation" => "AI evaluation" }.freeze
  LIMITS = { "min_repeats" => 1..50, "min_steps" => 2..20, "lookback_days" => 1..90, "snooze_days" => 1..90,
             "max_added_steps" => 1..10, "max_extra_steps" => 1..10, "keep_auto" => 1..1000,
             "interval_minutes" => 1..1440, "min_confidence" => 0..100 }.freeze

  validates :key, inclusion: { in: DEFAULTS.keys }, uniqueness: true
  validate :settings_in_range

  def self.for(key)
    raise ArgumentError, "unknown protocol #{key}" unless DEFAULTS.key?(key.to_s)
    find_or_create_by!(key: key.to_s) { |p| p.settings = DEFAULTS[key.to_s] }
  end

  def self.all_keys = DEFAULTS.keys.map { |k| self.for(k) }

  def [](name) = settings.fetch(name.to_s) { DEFAULTS[key][name.to_s] }
  def label = LABELS[key]

  # Accepts form strings; keeps only known settings, typed like the defaults.
  def assign_settings(raw)
    self.settings = DEFAULTS[key].to_h do |name, default|
      v = raw.respond_to?(:key?) && raw.key?(name) ? raw[name] : self[name]
      [name, default == true || default == false ? ActiveModel::Type::Boolean.new.cast(v) || false : Integer(v.to_s, exception: false)]
    end
  end

  private

  def settings_in_range
    settings.each do |name, v|
      next unless (range = LIMITS[name])
      errors.add(:settings, "#{name.humanize.downcase} must be between #{range.min} and #{range.max}") unless v.is_a?(Integer) && range.cover?(v)
    end
  end
end
