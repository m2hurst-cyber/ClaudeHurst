class SkillTransfers < ActiveRecord::Migration[7.2]
  def change
    create_table :skill_transfers do |t|
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.jsonb :items, null: false, default: [] # [{name, version, title}]
      t.decimal :price, precision: 12, scale: 2, null: false, default: 0
      t.string :status, null: false, default: "offered"
      t.text :message
      t.boolean :allow_forward, null: false, default: false
      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.timestamps
    end
    add_index :skill_transfers, %i[recipient_id status]
    create_table :skill_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.string :skill_name, null: false
      t.integer :version, null: false
      t.references :transfer, foreign_key: { to_table: :skill_transfers }
      t.references :granted_by, foreign_key: { to_table: :users }
      t.boolean :can_forward, null: false, default: false
      t.timestamps
    end
    add_index :skill_grants, %i[user_id skill_name], unique: true
    add_reference :credit_entries, :skill_transfer, foreign_key: true
  end
end
