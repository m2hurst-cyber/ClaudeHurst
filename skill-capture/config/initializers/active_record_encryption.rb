# Encryption at rest for return documents (uploaded tax forms and the figures read from them).
# Production must set the three keys (generate with `bin/rails db:encryption:init`); development
# and test derive fixed keys so the app runs out of the box. Never reuse the dev keys in production.
Rails.application.configure do
  keys = {
    primary_key: ENV["SKILL_CAPTURE_ENCRYPTION_PRIMARY_KEY"],
    deterministic_key: ENV["SKILL_CAPTURE_ENCRYPTION_DETERMINISTIC_KEY"],
    key_derivation_salt: ENV["SKILL_CAPTURE_ENCRYPTION_KEY_DERIVATION_SALT"]
  }
  if keys.values.any?(&:blank?)
    if Rails.env.production?
      raise "Set SKILL_CAPTURE_ENCRYPTION_PRIMARY_KEY, _DETERMINISTIC_KEY and _KEY_DERIVATION_SALT (bin/rails db:encryption:init) before storing return documents"
    end
    keys = keys.to_h { |k, v| [k, v.presence || Digest::SHA256.hexdigest("skill-capture-#{Rails.env}-#{k}")] }
  end
  config.active_record.encryption.primary_key = keys[:primary_key]
  config.active_record.encryption.deterministic_key = keys[:deterministic_key]
  config.active_record.encryption.key_derivation_salt = keys[:key_derivation_salt]
end
