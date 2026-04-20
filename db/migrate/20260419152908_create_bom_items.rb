class CreateBomItems < ActiveRecord::Migration[7.1]
  def change
    create_table :bom_items do |t|
      t.references :bom, null: false, foreign_key: true
      t.references :raw_material, null: false, foreign_key: true
      t.decimal :quantity_per_unit, precision: 14, scale: 6, null: false
      t.string :uom, null: false
      t.integer :position, null: false, default: 0
      t.text :notes
      t.timestamps
    end
    add_index :bom_items, [:bom_id, :raw_material_id], unique: true
  end
end
