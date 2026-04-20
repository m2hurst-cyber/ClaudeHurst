class CreateProductionLines < ActiveRecord::Migration[7.1]
  def change
    create_table :production_lines do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.integer :hourly_capacity
      t.boolean :active, null: false, default: true
      t.text :description
      t.timestamps
    end
    add_index :production_lines, :code, unique: true
  end
end
