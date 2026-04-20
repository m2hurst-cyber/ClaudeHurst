class CreateProductionRunConsumptions < ActiveRecord::Migration[7.1]
  def change
    create_table :production_run_consumptions do |t|
      t.references :production_run, null: false, foreign_key: true
      t.references :raw_material_lot, null: false, foreign_key: true
      t.decimal :quantity_planned, precision: 14, scale: 4, null: false, default: 0
      t.decimal :quantity_actual, precision: 14, scale: 4
      t.string :uom, null: false
      t.timestamps
    end
    add_index :production_run_consumptions, [:production_run_id, :raw_material_lot_id], unique: true, name: "idx_run_consumption"
  end
end
