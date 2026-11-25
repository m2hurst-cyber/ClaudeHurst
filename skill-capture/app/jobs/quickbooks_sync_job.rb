# Polls the change feed. Runs on the webhook's nudge, and on a timer regardless, because
# a missed notification should cost a delay rather than a gap in the record.
class QuickbooksSyncJob < ApplicationJob
  queue_as :default

  def perform(integration_id = nil)
    integrations = integration_id ? Integration.where(id: integration_id) : Integration.on.where(provider: "quickbooks")
    integrations.find_each do |integration|
      next unless integration.enabled? && integration.connected_to_api?
      Capture::Quickbooks::Sync.call(integration)
    rescue Capture::Quickbooks::Client::Error, Capture::Quickbooks::Oauth::Error => e
      Rails.logger.warn("QuickBooks sync for ##{integration.id}: #{e.message}")
    end
  end
end
