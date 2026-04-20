class CreateFinishedGoodMovements < ActiveRecord::Migration[7.1]
  def change
    create_table :finished_good_movements do |t|
      t.references :finished_good_lot, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :reference, polymorphic: true
      t.string :kind, null: false
      t.integer :quantity, null: false
      t.datetime :occurred_at, null: false
      t.text :notes
      t.timestamps
    end
    add_index :finished_good_movements, :kind
    add_index :finished_good_movements, :occurred_at
  end
end
