class CreateQuoteLineItems < ActiveRecord::Migration[7.1]
  def change
    create_table :quote_line_items do |t|
      t.references :quote, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.string :description, null: false
      t.decimal :quantity, precision: 12, scale: 3, null: false, default: 1
      t.bigint :unit_price_cents, null: false, default: 0
      t.decimal :tax_rate, precision: 6, scale: 4, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
