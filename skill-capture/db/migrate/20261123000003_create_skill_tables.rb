class CreateSkillTables < ActiveRecord::Migration[7.2]
  def change
    create_table :skills do |t|
      t.string :name, null: false                # Agent Skills `name` (kebab-case)
      t.integer :version, null: false, default: 1
      t.string :title, null: false
      t.text :description, null: false           # Agent Skills `description`
      t.text :body, null: false                  # SKILL.md Markdown body
      t.string :domain
      t.string :tags, array: true, null: false, default: []
      t.jsonb :inputs, null: false, default: []
      t.jsonb :outputs, null: false, default: []
      t.string :license, null: false, default: "Proprietary - internal use only"
      t.string :status, null: false, default: "published" # published | superseded | deprecated
      t.references :parent_skill, foreign_key: { to_table: :skills }
      t.references :published_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.jsonb :source, null: false, default: {}  # provenance / lineage
      t.timestamps
    end
    add_index :skills, %i[name version], unique: true
    add_index :skills, :status

    create_table :skill_candidates do |t|
      t.string :signature, null: false
      t.jsonb :steps, null: false, default: []
      t.string :domain
      t.string :status, null: false, default: "detected" # detected | drafted | approved | rejected | dismissed
      t.string :origin, null: false, default: "detected" # detected | manual
      t.integer :occurrence_count, null: false, default: 0
      t.integer :distinct_actor_count, null: false, default: 0
      t.jsonb :contributors, null: false, default: []    # [{key, name}]
      t.jsonb :example_traces, null: false, default: []
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.string :draft_name
      t.string :draft_title
      t.text :draft_description
      t.text :draft_body
      t.string :draft_tags, array: true, null: false, default: []
      t.jsonb :draft_inputs, null: false, default: []
      t.jsonb :draft_outputs, null: false, default: []
      t.string :draft_generator
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
