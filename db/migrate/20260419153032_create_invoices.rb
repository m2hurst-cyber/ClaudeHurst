class CreateInvoices < ActiveRecord::Migration[7.1]
  def change
    create_table :invoices do |t|
      t.string :number, null: false
      t.references :company, null: false, foreign_key: true
      t.references :contract, foreign_key: true
      t.references :production_run, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.date :issued_on
      t.date :due_on
      t.date :paid_on
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :balance_cents, null: false, default: 0
      t.string :currency, null: false, default: "USD"
      t.text :notes
      t.timestamps
    end
    add_index :invoices, :number, unique: true
    add_index :invoices, :status
    add_index :invoices, :due_on
  end
end
