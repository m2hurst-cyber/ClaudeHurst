module Capture
  # What a skill says it touches. Declared by whoever writes it, shown to whoever approves
  # it, and checked against the text. An empty declaration is a claim too: it says the
  # skill stays inside the workbook in front of it.
  module Capabilities
    KEYS = %w[reads writes sends tools hosts needs_credentials].freeze
    LABELS = {
      "reads" => "Reads", "writes" => "Writes", "sends" => "Sends to",
      "tools" => "Uses", "hosts" => "Reaches", "needs_credentials" => "Needs a credential"
    }.freeze

    module_function

    def of(subject)
      raw = subject.is_a?(Hash) ? (subject[:capabilities] || subject["capabilities"]) : subject.try(:capabilities)
      normalize(raw || {})
    end

    def normalize(raw)
      raw = raw.to_h.stringify_keys
      KEYS.index_with do |k|
        next ActiveModel::Type::Boolean.new.cast(raw[k]) || false if k == "needs_credentials"
        Array(raw[k]).map { |v| v.to_s.strip.downcase }.reject(&:blank?).uniq.first(12)
      end
    end

    def empty?(caps) = KEYS.all? { |k| k == "needs_credentials" ? !caps[k] : Array(caps[k]).empty? }

    # One line a reviewer can read without unfolding anything.
    def summary(caps)
      return "Stays inside the file in front of it" if empty?(caps)
      parts = KEYS.filter_map do |k|
        next "needs a credential" if k == "needs_credentials" && caps[k]
        next if k == "needs_credentials" || Array(caps[k]).empty?
        "#{LABELS[k].downcase} #{Array(caps[k]).to_sentence}"
      end
      parts.to_sentence.upcase_first
    end
  end
end
