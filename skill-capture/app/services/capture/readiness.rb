module Capture
  # Everything this installation needs from the outside world, and whether it has it.
  #
  # These answers were scattered: a mail failure appeared as a colleague who never got a
  # reset, a missing model key as drafting quietly falling back to rules, an unregistered
  # app as an error at the end of a redirect. One page, checked from the environment as
  # it actually is.
  module Readiness
    Check = Struct.new(:key, :label, :state, :detail, :fix, :where, keyword_init: true) do
      def ok? = state == :ok
      def blocking? = state == :missing
    end

    module_function

    def all = [model, encryption, mail, addin] + integrations
    def blocking = all.select(&:blocking?)
    def ready? = blocking.empty?

    def model
      if Config.llm_enabled?
        Check.new(key: "model", label: "Model access", state: :ok,
                  detail: "Drafting and judging run on #{Config.llm_model}.")
      else
        Check.new(key: "model", label: "Model access", state: :degraded,
                  detail: "No key, so drafts and judgements fall back to rules. The system works; it is blunter.",
                  fix: "ANTHROPIC_API_KEY", where: "https://console.anthropic.com/settings/keys")
      end
    end

    def encryption
      present = %w[SKILL_CAPTURE_ENCRYPTION_PRIMARY_KEY SKILL_CAPTURE_ENCRYPTION_DETERMINISTIC_KEY
                   SKILL_CAPTURE_ENCRYPTION_KEY_DERIVATION_SALT].reject { |k| ENV[k].present? }
      if present.empty?
        Check.new(key: "encryption", label: "Encryption keys", state: :ok, detail: "Tokens and return documents are encrypted at rest.")
      else
        Check.new(key: "encryption", label: "Encryption keys",
                  state: Rails.env.production? ? :missing : :degraded,
                  detail: "Without these, nothing that must be encrypted can be stored: return documents, Git tokens, integration credentials.",
                  fix: present.join(", "), where: "bin/rails db:encryption:init")
      end
    end

    def mail
      if MailCheck.configured?
        Check.new(key: "mail", label: "Mail", state: :ok, detail: MailCheck.summary)
      else
        Check.new(key: "mail", label: "Mail", state: :missing,
                  detail: "A password reset cannot reach anyone. Nothing errors — the person simply waits.",
                  fix: MailCheck.missing.keys.join(", "))
      end
    end

    def addin
      url = ENV["SKILL_CAPTURE_PUBLIC_URL"].presence
      id = ENV["SKILL_CAPTURE_ADDIN_ID"].presence
      if url&.start_with?("https://") && id.present?
        Check.new(key: "addin", label: "Office add-in", state: :ok, detail: "Served from #{url} under a fixed id.")
      else
        Check.new(key: "addin", label: "Office add-in", state: :degraded,
                  detail: "Office only loads add-ins over HTTPS, and the id must be a fixed GUID or an update installs " \
                          "as a second add-in beside the first.",
                  fix: [("SKILL_CAPTURE_PUBLIC_URL" unless url), ("SKILL_CAPTURE_ADDIN_ID" unless id)].compact.join(", "))
      end
    end

    # One per catalogue entry that somebody has actually connected or tried to.
    def integrations
      Integrations.all.filter_map do |provider|
        next unless provider.connected? || provider.ready?
        missing = provider.missing_credentials
        unverified = !provider.endpoints_verified?
        state = if missing.any? then :missing
                elsif unverified then :degraded
                else :ok
                end
        detail = if missing.any?
                   "Connected but it cannot authorise: #{missing.map { |c| c['what'] }.to_sentence} #{missing.size == 1 ? 'is' : 'are'} not set."
                 elsif unverified
                   "Registered, but its API endpoints have not been checked against the vendor's documentation."
                 else
                   "Registered and ready."
                 end
        Check.new(key: "integration:#{provider.key}", label: provider.name, state: state, detail: detail,
                  fix: missing.map { |c| c["env"] }.join(", ").presence, where: provider.portal)
      end
    end
  end
end
