class CreateProductionRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :production_runs do |t|
      t.string :number, null: false
      t.references :product, null: false, foreign_key: true
      t.references :bom, foreign_key: true
      t.references :production_line, null: false, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.datetime :scheduled_start, null: false
      t.datetime :scheduled_end
      t.datetime :actual_start
      t.datetime :actual_end
      t.integer :planned_units, null: false
      t.integer :actual_units
      t.string :status, null: false, default: "planned"
      t.string :batch_code
      t.text :notes
      t.timestamps
    end
    add_index :production_runs, :number, unique: true
    add_index :production_runs, :status
    add_index :production_runs, :scheduled_start
  end
end
