class AddOauthToIntegrations < ActiveRecord::Migration[7.2]
  def change
    add_column :integrations, :external_id, :string          # the provider's id for the company (QBO realmId)
    add_column :integrations, :credentials, :text            # encrypted: access and refresh tokens
    add_column :integrations, :token_expires_at, :datetime
    add_column :integrations, :last_synced_at, :datetime     # how far the poller has read
    add_column :integrations, :last_sync_error, :text
    add_index  :integrations, :external_id
  end
end
