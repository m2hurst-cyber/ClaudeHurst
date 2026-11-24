class EscrowRunsFlows < ActiveRecord::Migration[7.2]
  def up
    add_column :skill_transfers, :contract_log, :jsonb, null: false, default: []
    add_column :skill_transfers, :terms_hash, :string
    add_column :skill_transfers, :funded_at, :datetime
    add_column :skill_transfers, :settled_at, :datetime
    add_column :credit_entries, :kind, :string, null: false, default: "bounty"
    execute "UPDATE skill_transfers SET status = 'settled', settled_at = responded_at WHERE status = 'accepted'"
    execute "UPDATE credit_entries SET kind = 'transfer' WHERE skill_transfer_id IS NOT NULL"

    create_table :skill_runs do |t|
      t.string :skill_name, null: false
      t.integer :skill_version
      t.string :agent, null: false
      t.string :model
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :duration_ms
      t.string :status, null: false, default: "succeeded"
      t.references :source, foreign_key: true
      t.references :user, foreign_key: true
      t.references :flow_run, index: true
      t.integer :step_index
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :skill_runs, %i[skill_name occurred_at]

    create_table :flows do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.jsonb :steps, null: false, default: []
      t.timestamps
    end
    create_table :flow_runs do |t|
      t.references :flow, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.jsonb :steps, null: false, default: []
      t.integer :current_index, null: false, default: 0
      t.datetime :finished_at
      t.timestamps
    end
    add_foreign_key :skill_runs, :flow_runs
  end

  def down
    drop_table :skill_runs
    drop_table :flow_runs
    drop_table :flows
    remove_column :credit_entries, :kind
    %i[contract_log terms_hash funded_at settled_at].each { |c| remove_column :skill_transfers, c }
  end
end
