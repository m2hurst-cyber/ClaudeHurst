class CreateCoreTables < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      ## Devise
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.string :name, null: false
      t.string :role, null: false, default: "member"      # admin | reviewer | member
      t.string :domains, array: true, null: false, default: [] # areas a reviewer owns
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true

    # A registered activity collector (Office add-in, Slack bot, IDE plugin, browser agent, ...).
    create_table :sources do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "custom"
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :sources, :token_digest, unique: true

    # Plain-English meaning of each action key collectors report; shown to reviewers and the LLM.
    create_table :action_definitions do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :domain
      t.references :source, foreign_key: true
      t.timestamps
    end
    add_index :action_definitions, :key, unique: true

    create_table :usage_events do |t|
      t.references :source, null: false, foreign_key: true
      t.string :actor_key, null: false   # stable pseudonymous id from the collector
      t.string :actor_name               # optional display name, used only for attribution
      t.string :session_key, null: false
      t.string :action_key, null: false  # e.g. "excel.run_macro:quarterly_close"
      t.string :domain
      t.string :resource_type
      t.string :resource_ref
      t.jsonb :context, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :usage_events, %i[actor_key occurred_at]
    add_index :usage_events, :occurred_at

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :subject, polymorphic: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.string :url
      t.datetime :read_at
      t.timestamps
    end

    create_table :audit_logs do |t|
      t.references :user, foreign_key: true
      t.references :source, foreign_key: true
      t.references :subject, polymorphic: true
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
