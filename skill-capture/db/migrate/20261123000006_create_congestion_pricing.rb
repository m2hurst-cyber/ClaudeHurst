# Congestion pricing: a demand schedule prices each skill by how congested it is;
# the congestion premium funds a bounty for whoever removes the bottleneck.
class CreateCongestionPricing < ActiveRecord::Migration[7.2]
  def change
    # One row: the demand schedule and how bounties work (admin-editable).
    create_table :pricing_schedules do |t|
      t.string :currency, null: false, default: "credits"
      t.decimal :base_price, precision: 12, scale: 2, null: false, default: 10
      t.jsonb :tiers, null: false, default: []           # [{key, label, min_index, multiplier}]
      t.integer :window_days, null: false, default: 7     # recent traffic used for the price
      t.integer :min_trips, null: false, default: 5       # below this a skill isn't priced
      t.decimal :pool_share, precision: 5, scale: 2, null: false, default: 1  # share of the premium that funds bounties
      t.string :bounty_tier, null: false, default: "heavy" # bounties open at this tier or worse
      t.integer :measure_min_trips, null: false, default: 5
      t.integer :measure_max_days, null: false, default: 21
      t.timestamps
    end

    # Latest traffic reading per skill (by name), recomputed by the sweep.
    create_table :skill_metrics do |t|
      t.string :name, null: false
      t.integer :trips, null: false, default: 0           # in the pricing window
      t.integer :people, null: false, default: 0
      t.float :median_minutes                             # travel time = wait before + doing it
      t.float :median_wait_minutes
      t.float :freeflow_minutes                           # 20th percentile over the long baseline
      t.float :congestion_index
      t.float :delay_hours, null: false, default: 0       # excess over free-flow, summed over the window
      t.string :tier                                      # nil when not enough trips
      t.decimal :price, precision: 12, scale: 2
      t.jsonb :history, null: false, default: []          # [{date, index, trips}] last 30 sweeps (one per day)
      t.datetime :computed_at
      t.timestamps
    end
    add_index :skill_metrics, :name, unique: true

    create_table :bounties do |t|
      t.string :skill_name, null: false
      t.string :status, null: false, default: "open"      # open | measuring | awaiting_approval | paid | closed
      t.decimal :pool, precision: 12, scale: 2, null: false, default: 0
      t.datetime :accrued_until                           # trips ending before this are already in the pool
      t.float :opened_index
      t.float :baseline_index                             # index when the fix shipped
      t.datetime :fix_at
      t.string :fix_skill_name                            # the new version's or branch's name
      t.integer :fix_version
      t.references :solver, foreign_key: { to_table: :users }
      t.float :result_index
      t.float :improvement                                # 0..1 share of the congestion removed
      t.decimal :payout, precision: 12, scale: 2
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.text :notes
      t.timestamps
    end
    add_index :bounties, %i[skill_name status]

    create_table :credit_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :bounty, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :reason, null: false
      t.datetime :created_at, null: false
    end
  end
end
