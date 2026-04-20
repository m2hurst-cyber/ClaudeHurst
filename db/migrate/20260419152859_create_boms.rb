class CreateBoms < ActiveRecord::Migration[7.1]
  def change
    create_table :boms do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.integer :yield_units, null: false, default: 1
      t.text :notes
      t.timestamps
    end
    add_index :boms, [:product_id, :version], unique: true
  end
end
