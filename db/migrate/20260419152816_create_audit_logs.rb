class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, foreign_key: true
      t.references :subject, polymorphic: true
      t.string :action, null: false
      t.jsonb :metadata, default: {}
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
