class CreateSkillCaptureTables < ActiveRecord::Migration[7.2]
  def change
    # Raw activity stream from the in-app collector. Stores *structure only*
    # (which controller/action ran on which resource type) — never param values.
    create_table :usage_events do |t|
      t.references :user, foreign_key: true
      t.string :session_key, null: false
      t.string :workflow_key, null: false        # e.g. "production_runs#release"
      t.string :http_method, null: false
      t.string :resource_type
      t.bigint :resource_id
      t.integer :response_status
      t.jsonb :context, default: {}, null: false # allowlisted, non-sensitive metadata
      t.datetime :occurred_at, null: false
    end
    add_index :usage_events, %i[user_id occurred_at]
    add_index :usage_events, :occurred_at
    add_index :usage_events, :workflow_key

    create_table :skills do |t|
      t.string :name, null: false                # Agent Skills `name` (kebab-case)
      t.integer :version, null: false, default: 1
      t.string :title, null: false
      t.text :description, null: false           # Agent Skills `description`
      t.text :body, null: false                  # Markdown instructions (SKILL.md body)
      t.string :domain
      t.string :tags, array: true, default: [], null: false
      t.jsonb :inputs, default: [], null: false
      t.jsonb :outputs, default: [], null: false
      t.string :license, null: false, default: "Proprietary - internal use only"
      t.string :status, null: false, default: "published" # published | superseded | deprecated
      t.references :parent_skill, foreign_key: { to_table: :skills }
      t.references :published_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.jsonb :source, default: {}, null: false  # lineage: candidate, contributors, app context, first/last seen
      t.timestamps
    end
    add_index :skills, %i[name version], unique: true
    add_index :skills, :status

    create_table :skill_candidates do |t|
      t.string :signature, null: false           # "a#b>c#d" — the detected step sequence
      t.jsonb :steps, default: [], null: false
      t.string :domain
      t.string :status, null: false, default: "detected" # detected | drafted | approved | rejected | dismissed
      t.integer :occurrence_count, null: false, default: 0
      t.integer :distinct_user_count, null: false, default: 0
      t.jsonb :contributor_ids, default: [], null: false
      t.jsonb :example_traces, default: [], null: false
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.string :origin, null: false, default: "detected" # detected | manual
      t.string :draft_name
      t.string :draft_title
      t.text :draft_description
      t.text :draft_body
      t.string :draft_tags, array: true, default: [], null: false
      t.jsonb :draft_inputs, default: [], null: false
      t.jsonb :draft_outputs, default: [], null: false
      t.string :draft_generator                  # "claude" | "template" | "human"
      t.datetime :drafted_at
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :review_notes
      t.references :skill, foreign_key: true
      t.timestamps
    end
    add_index :skill_candidates, :signature, unique: true
    add_index :skill_candidates, :status
  end
end
