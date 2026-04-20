class CreateQuotes < ActiveRecord::Migration[7.1]
  def change
    create_table :quotes do |t|
      t.string :number, null: false
      t.references :company, null: false, foreign_key: true
      t.references :deal, foreign_key: true
      t.references :contact, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.date :issued_on
      t.date :expires_on
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "USD"
      t.text :notes
      t.text :terms
      t.timestamps
    end
    add_index :quotes, :number, unique: true
    add_index :quotes, :status
  end
end
