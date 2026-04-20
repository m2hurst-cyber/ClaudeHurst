class CreateContracts < ActiveRecord::Migration[7.1]
  def change
    create_table :contracts do |t|
      t.string :number, null: false
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.date :start_on
      t.date :end_on
      t.string :payment_terms, null: false, default: "net_30"
      t.integer :minimum_run_units
      t.datetime :signed_at
      t.datetime :countersigned_at
      t.text :terms
      t.timestamps
    end
    add_index :contracts, :number, unique: true
    add_index :contracts, :status
  end
end
