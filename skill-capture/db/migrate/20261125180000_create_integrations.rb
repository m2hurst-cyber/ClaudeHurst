class CreateIntegrations < ActiveRecord::Migration[7.2]
  def change
    create_table :integrations do |t|
      t.string  :provider, null: false, index: { unique: true }  # a key from the catalogue
      t.string  :label                                           # "NetSuite (production)"
      t.references :source, foreign_key: true                    # the token its events arrive on
      t.references :connected_by, foreign_key: { to_table: :users }
      t.boolean :enabled, null: false, default: true
      t.datetime :last_event_at
      t.integer :event_count, null: false, default: 0
      t.timestamps
    end
  end
end
