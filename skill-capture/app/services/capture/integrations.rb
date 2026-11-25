module Capture
  # The catalogue of business systems we know how to take work from: what each one is,
  # the vocabulary of steps it produces, and what we refuse to store from it.
  #
  # Files rather than rows, for the same reason the playbooks and the help are: a new
  # system is a text file somebody can read and review, not a migration. The valuable
  # part is the vocabulary — until a step has a name a person recognises, a mined
  # sequence from an ERP is a row of opaque keys and nobody will approve it.
  module Integrations
    DIR = Rails.root.join("integrations")
    CATEGORIES = { "erp" => "ERP", "crm" => "CRM", "accounting" => "Accounting and payments" }.freeze
    AUTH_LABELS = { "oauth2" => "OAuth", "api_key" => "API key", "token" => "Token", "basic" => "Username and password" }.freeze

    Provider = Struct.new(:key, :name, :vendor, :category, :auth, :docs, :blurb, :actions, :records, :never,
                          :per_tenant, :registration, :portal, :credentials, :api, keyword_init: true) do
      def category_label = CATEGORIES.fetch(category, category.to_s.humanize)
      def auth_label = AUTH_LABELS.fetch(auth, auth.to_s.humanize)
      def action_keys = actions.map { |a| a["key"] }
      def connected? = Integration.exists?(provider: key)
      def per_tenant? = per_tenant == true
      def env_names = Array(credentials).map { |c| c["env"] }
      def missing_credentials = Array(credentials).reject { |c| ENV[c["env"]].present? }
      def ready? = missing_credentials.empty?
      # An entry that carries API details can say whether anyone has checked them.
      def endpoints_verified? = api.nil? || api["verified"] == true
    end

    module_function

    def all
      @all = nil if !Rails.env.production? && stale?
      @all ||= begin
        @loaded_at = Time.current
        Dir.glob(DIR.join("*.yml")).sort.filter_map { |f| parse(Pathname(f)) }
           .sort_by { |p| [CATEGORIES.keys.index(p.category) || 9, p.name] }
      end
    end

    def stale?
      @loaded_at.nil? || Dir.glob(DIR.join("*.yml")).any? { |f| File.mtime(f) > @loaded_at }
    end

    def parse(file)
      raw = YAML.safe_load(file.read)
      Provider.new(key: raw["key"], name: raw["name"], vendor: raw["vendor"], category: raw["category"],
                   auth: raw["auth"], docs: raw["docs"], blurb: raw["blurb"].to_s.strip,
                   actions: Array(raw["actions"]), records: Array(raw["records"]), never: Array(raw["never"]),
                   per_tenant: raw["per_tenant"] == true, registration: raw["registration"].to_s.strip,
                   portal: raw["portal"], credentials: Array(raw["credentials"]),
                   api: raw.slice("verified", "authorize_url", "token_url", "revoke_url", "scope", "api_base",
                                  "minor_version", "cdc").presence)
    rescue Psych::SyntaxError => e
      Rails.logger.warn("Integration #{file.basename} has broken YAML: #{e.message}")
      nil
    end

    def find(key) = all.find { |p| p.key == key.to_s }
    def by_category = all.group_by(&:category)

    # Teaching the system this provider's vocabulary is what connecting actually does:
    # from here on a mined sequence reads as "Code a bill → Route for approval → Approve
    # a bill" rather than three keys nobody can judge.
    def register_vocabulary!(provider)
      Array(provider.actions).each do |a|
        definition = ActionDefinition.find_or_initialize_by(key: a["key"])
        definition.label = a["label"] if definition.label.blank?
        definition.domain = a["domain"] if definition.domain.blank?
        definition.save! if definition.changed?
      end
    end
  end
end
