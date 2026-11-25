class AddProvenance < ActiveRecord::Migration[7.2]
  def change
    # The content hash is the skill's identity: the same bytes give the same hash in
    # any firm, so a skill can be referred to, transferred and checked without us.
    add_column :skills, :content_hash, :string
    add_index :skills, :content_hash

    # An append-only, hash-linked ledger. Each entry commits to the one before it, so
    # altering any historical row invalidates every hash after it.
    create_table :provenance_entries do |t|
      t.bigint   :sequence, null: false
      t.string   :prev_hash, null: false
      t.string   :entry_hash, null: false
      t.string   :event, null: false
      t.string   :skill_name
      t.integer  :skill_version
      t.string   :content_hash
      t.string   :actor_key
      t.jsonb    :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
      t.index :sequence, unique: true
      t.index :entry_hash, unique: true
      t.index :skill_name
      t.index :content_hash
    end

    # A periodic commitment to the ledger so far: publish the root anywhere (a mirror,
    # a counterparty, a notary, a chain) and the history under it can no longer change.
    create_table :provenance_anchors do |t|
      t.date     :on_date, null: false
      t.bigint   :from_sequence, null: false
      t.bigint   :to_sequence, null: false
      t.integer  :entry_count, null: false, default: 0
      t.string   :root_hash, null: false
      t.string   :tip_hash, null: false
      t.datetime :created_at, null: false
      t.index :on_date, unique: true
    end
  end
end
