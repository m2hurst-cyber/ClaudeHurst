class CreateCommunicationPushEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :communication_push_events do |t|
      t.references :user, foreign_key: true
      t.references :subject, polymorphic: true
      t.string :event_type, null: false
      t.string :channel, null: false
      t.string :status, null: false, default: "pending"
      t.string :recipient
      t.string :external_id
      t.string :deduplication_key, null: false
      t.jsonb :payload, null: false, default: {}
      t.text :error_message
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :communication_push_events, :event_type
    add_index :communication_push_events, :channel
    add_index :communication_push_events, :status
    add_index :communication_push_events, :deduplication_key, unique: true
  end
end
