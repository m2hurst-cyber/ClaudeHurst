class CreateMicrosoftConnections < ActiveRecord::Migration[7.2]
  def change
    create_table :microsoft_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :tenant_id, null: false
      t.string :microsoft_user_id, null: false
      t.string :email, null: false
      t.string :display_name
      t.text :integration_payload
      t.datetime :integration_expires_at
      t.text :granted_scopes, default: ""
      t.datetime :last_synced_at
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :microsoft_connections, :microsoft_user_id
    add_index :microsoft_connections, :tenant_id
    add_index :microsoft_connections, :discarded_at
  end
end
