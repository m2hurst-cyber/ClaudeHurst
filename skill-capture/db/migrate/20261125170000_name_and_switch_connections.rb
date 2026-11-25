class NameAndSwitchConnections < ActiveRecord::Migration[7.2]
  def change
    # A connection someone can recognise, and a switch that is not a one-way door:
    # revoked_at ends a token for good, enabled just stops it answering for now.
    add_column :addin_tokens, :name, :string
    add_column :addin_tokens, :kind, :string, null: false, default: "office"
    add_column :addin_tokens, :enabled, :boolean, null: false, default: true
    add_index :addin_tokens, %i[user_id kind]
  end
end
