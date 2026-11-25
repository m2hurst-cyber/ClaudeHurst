module Capture
  module Quickbooks
    # Turns "what changed in the books" into the same kind of steps the add-in reports,
    # so an ERP sequence is mined, reviewed and promoted exactly like one from Excel.
    #
    # One thing the API cannot tell us: who did it. QuickBooks' change feed carries the
    # record and when it changed, not the person who changed it. So these steps are
    # attributed to the company, not to a colleague. That is the honest attribution, and
    # it has a consequence worth knowing: the firm-wide detector will find repeated
    # procedures in the books, but nobody is personally prompted to save them, because
    # nobody can be shown to have done them.
    module Sync
      module_function

      # Change feed entity and operation → the vocabulary the catalogue declared.
      MAP = {
        %w[Invoice Create] => "quickbooks.create:invoice",
        %w[Invoice Update] => "quickbooks.create:invoice",
        %w[Payment Create] => "quickbooks.receive:payment",
        %w[Bill Create] => "quickbooks.enter:bill",
        %w[Bill Update] => "quickbooks.enter:bill",
        %w[BillPayment Create] => "quickbooks.receive:payment",
        %w[JournalEntry Create] => "quickbooks.post:journal",
        %w[Purchase Create] => "quickbooks.categorise:transaction",
        %w[Purchase Update] => "quickbooks.categorise:transaction",
        %w[Deposit Create] => "quickbooks.reconcile:account"
      }.freeze

      def call(integration, client: nil)
        client ||= Client.new(integration)
        payload = client.changes_since(integration.last_synced_at)
        events = events_from(payload, integration)
        result = events.any? ? Ingestor.call(integration.source, events) : nil

        integration.update!(last_synced_at: Time.current, last_sync_error: nil)
        integration.refresh_counts!
        AuditLog.record("integration.synced", subject: integration, provider: integration.provider, steps: events.size)
        result
      rescue Client::Error, Oauth::Error => e
        integration.update(last_sync_error: e.message)
        raise
      end

      # One session per company per day: a day's bookkeeping is one stretch of work, which
      # is the unit a procedure repeats in.
      def events_from(payload, integration)
        actor = "qbo:#{integration.external_id}"
        rows(payload).filter_map do |entity, record|
          operation = record["status"].presence || record.dig("Invoice", "status") || "Create"
          key = MAP[[entity, operation]] || MAP[[entity, "Create"]]
          next if key.nil?
          at = record.dig("MetaData", "LastUpdatedTime").presence || record.dig("MetaData", "CreateTime")
          next if at.blank?
          { "action" => key, "actor" => { "id" => actor, "name" => integration.name },
            "session" => "qbo-#{integration.external_id}-#{Time.parse(at).utc.to_date.iso8601}",
            "occurred_at" => Time.parse(at).utc.iso8601, "domain" => "finance",
            "context" => { "app" => "QuickBooks Online" } }
        end.sort_by { |e| e["occurred_at"] }
      rescue ArgumentError, TypeError => e
        Rails.logger.warn("QuickBooks sync: unreadable change feed (#{e.class})")
        []
      end

      # The change feed nests entities by type inside query responses; flatten to pairs.
      def rows(payload)
        Array(payload&.dig("CDCResponse")).flat_map do |response|
          Array(response["QueryResponse"]).flat_map do |query|
            query.except("startPosition", "maxResults", "totalCount").flat_map do |entity, records|
              Array(records).map { |record| [entity, record] }
            end
          end
        end
      end
    end
  end
end
