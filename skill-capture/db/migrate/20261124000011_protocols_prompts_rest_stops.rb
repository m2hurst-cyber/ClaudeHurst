class ProtocolsPromptsRestStops < ActiveRecord::Migration[7.2]
  def change
    # Protocols: admin-tunable rules for when to prompt people to save, extend or branch, and for rest stops.
    create_table :protocols do |t|
      t.string :key, null: false, index: { unique: true }
      t.boolean :enabled, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end

    # A prompt for one person: "you keep doing this; save it / extend the skill / branch it".
    create_table :skill_prompts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false              # save | extend | branch
      t.string :skill_name                     # the skill it builds on (extend, branch)
      t.jsonb :steps, null: false, default: [] # the workflow being proposed
      t.jsonb :evidence, null: false, default: {}
      t.integer :occurrences, null: false, default: 0
      t.string :fingerprint, null: false
      t.string :status, null: false, default: "open" # open | snoozed | accepted | dismissed
      t.datetime :snoozed_until
      t.datetime :last_seen_at
      t.datetime :responded_at
      t.string :response
      t.references :candidate, foreign_key: { to_table: :skill_candidates }
      t.timestamps
      t.index %i[user_id fingerprint], unique: true
      t.index %i[user_id status]
    end

    # What a candidate proposes to do to an existing skill (from a prompt or a person).
    add_column :skill_candidates, :proposal_kind, :string
    add_reference :skill_candidates, :base_skill, foreign_key: { to_table: :skills }

    # Rest stops: full restorable snapshots of a skill (content, workflow, directions, resources, fields).
    create_table :rest_stops do |t|
      t.string :skill_name, null: false
      t.integer :skill_version, null: false
      t.references :skill, foreign_key: true
      t.string :kind, null: false, default: "auto" # auto | manual
      t.string :reason, null: false
      t.string :label
      t.jsonb :snapshot, null: false
      t.string :checksum, null: false
      t.boolean :pinned, null: false, default: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
      t.index %i[skill_name created_at]
    end
  end
end
