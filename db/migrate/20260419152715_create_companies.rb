class CreateCompanies < ActiveRecord::Migration[7.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :website
      t.string :industry
      t.string :status, null: false, default: "prospect"
      t.jsonb :billing_address, default: {}
      t.jsonb :shipping_address, default: {}
      t.references :owner, foreign_key: { to_table: :users }
      t.text :notes
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :companies, :slug, unique: true
    add_index :companies, :name
    add_index :companies, :status
    add_index :companies, :discarded_at
  end
end
