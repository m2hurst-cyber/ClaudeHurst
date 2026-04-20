class CreateFinishedGoodLots < ActiveRecord::Migration[7.1]
  def change
    create_table :finished_good_lots do |t|
      t.references :product, null: false, foreign_key: true
      t.references :production_run, null: false, foreign_key: true
      t.string :lot_code, null: false
      t.date :produced_on, null: false
      t.date :best_by_on
      t.integer :quantity_produced, null: false
      t.integer :quantity_on_hand, null: false
      t.timestamps
    end
    add_index :finished_good_lots, :lot_code, unique: true
  end
end
