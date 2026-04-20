class CreateDeals < ActiveRecord::Migration[7.1]
  def change
    create_table :deals do |t|
      t.references :company, null: false, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.bigint :amount_cents, null: false, default: 0
      t.string :currency, null: false, default: "USD"
      t.string :stage, null: false, default: "lead"
      t.date :expected_close_on
      t.integer :probability, default: 10
      t.datetime :closed_at
      t.string :lost_reason
      t.text :notes
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :deals, :stage
    add_index :deals, :discarded_at
  end
end
