class CreateRawMaterials < ActiveRecord::Migration[7.1]
  def change
    create_table :raw_materials do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.string :uom, null: false, default: "each"
      t.decimal :reorder_point, precision: 12, scale: 2, default: 0
      t.string :owned_by, null: false, default: "copacker"
      t.references :owned_by_company, foreign_key: { to_table: :companies }
      t.text :description
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :raw_materials, :code, unique: true
    add_index :raw_materials, :category
    add_index :raw_materials, :discarded_at
  end
end
