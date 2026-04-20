class CreateNumberSequences < ActiveRecord::Migration[7.1]
  def change
    create_table :number_sequences do |t|
      t.string :scope, null: false
      t.integer :year, null: false
      t.integer :last_value, null: false, default: 0
      t.timestamps
    end
    add_index :number_sequences, [:scope, :year], unique: true
  end
end
