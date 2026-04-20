class CreateRawMaterialLots < ActiveRecord::Migration[7.1]
  def change
    create_table :raw_material_lots do |t|
      t.references :raw_material, null: false, foreign_key: true
      t.string :lot_code, null: false
      t.date :received_on, null: false
      t.date :expires_on
      t.decimal :quantity_received, precision: 14, scale: 4, null: false
      t.decimal :quantity_on_hand, precision: 14, scale: 4, null: false
      t.string :supplier
      t.text :notes
      t.timestamps
    end
    add_index :raw_material_lots, [:raw_material_id, :lot_code], unique: true
    add_index :raw_material_lots, :received_on
  end
end
