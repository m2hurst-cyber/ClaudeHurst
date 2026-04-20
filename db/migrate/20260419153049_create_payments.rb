class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.date :received_on, null: false
      t.string :method, null: false, default: "ach"
      t.string :reference
      t.text :notes
      t.timestamps
    end
    add_index :payments, :received_on
  end
end
