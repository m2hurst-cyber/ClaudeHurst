class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.references :company, null: false, foreign_key: true
      t.string :sku, null: false
      t.string :name, null: false
      t.string :format
      t.integer :case_pack, default: 24
      t.string :gtin
      t.boolean :active, null: false, default: true
      t.text :description
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :products, [:company_id, :sku], unique: true
    add_index :products, :discarded_at
  end
end
