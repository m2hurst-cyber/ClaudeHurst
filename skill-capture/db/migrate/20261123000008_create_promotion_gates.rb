# Gatekeeping: skills move local (sandbox) → firm → market through gated promotions,
# informed by an internal vote on which process is better.
class CreatePromotionGates < ActiveRecord::Migration[7.2]
  def up
    add_column :skills, :stage, :string, null: false, default: "local"
    add_column :skills, :stage_changed_at, :datetime
    execute "UPDATE skills SET stage = 'firm', stage_changed_at = COALESCE(published_at, created_at)" # existing skills were already firm-wide
    add_index :skills, :stage

    create_table :promotion_policies do |t|
      t.string :initial_stage, null: false, default: "local"
      t.integer :firm_min_trips, null: false, default: 3
      t.integer :firm_min_people, null: false, default: 2
      t.integer :firm_min_score, null: false, default: 2
      t.integer :market_min_days, null: false, default: 14
      t.integer :market_min_score, null: false, default: 5
      t.string :market_max_tier, null: false, default: "slow"
      t.boolean :market_requires_directions, null: false, default: true
      t.timestamps
    end

    create_table :skill_votes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :skill_name, null: false
      t.integer :value, null: false                 # +1 / -1
      t.text :comment
      t.timestamps
    end
    add_index :skill_votes, %i[user_id skill_name], unique: true
    add_index :skill_votes, :skill_name

    create_table :promotions do |t|
      t.string :skill_name, null: false
      t.integer :skill_version, null: false
      t.string :from_stage, null: false
      t.string :to_stage, null: false
      t.string :status, null: false, default: "open"  # open | approved | rejected | withdrawn
      t.string :replaces_name                        # optional incumbent to retire on approval
      t.text :pitch                                  # why this should be promoted
      t.jsonb :checks, null: false, default: []      # gate results at decision time
      t.boolean :waived, null: false, default: false
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.text :decision_notes
      t.timestamps
    end
    add_index :promotions, %i[skill_name status]
  end

  def down
    drop_table :promotions
    drop_table :skill_votes
    drop_table :promotion_policies
    remove_column :skills, :stage_changed_at
    remove_column :skills, :stage
  end
end
