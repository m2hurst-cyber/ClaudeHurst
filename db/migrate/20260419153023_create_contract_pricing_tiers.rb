class CreateContractPricingTiers < ActiveRecord::Migration[7.1]
  def change
    create_table :contract_pricing_tiers do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :min_quantity, null: false, default: 1
      t.bigint :unit_price_cents, null: false
      t.timestamps
    end
    add_index :contract_pricing_tiers, [:contract_id, :product_id, :min_quantity], unique: true, name: "idx_contract_pricing_uniq"
  end
end
