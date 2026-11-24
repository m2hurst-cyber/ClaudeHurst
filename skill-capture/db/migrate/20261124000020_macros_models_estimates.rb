class MacrosModelsEstimates < ActiveRecord::Migration[7.2]
  def change
    # The models a task can run on, with what they cost. Seeded from Capture::Models::DEFAULTS.
    create_table :model_profiles do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :tier, null: false                  # macro | small | standard | deep
      t.decimal :input_cost, precision: 10, scale: 4, null: false, default: 0   # credits per 1M input tokens
      t.decimal :output_cost, precision: 10, scale: 4, null: false, default: 0
      t.integer :tokens_per_second, null: false, default: 60
      t.text :notes
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # The macro-suitability layer: a task is screened, and a person reviews it before a macro may run
    # in place of the AI.
    create_table :macro_reviews do |t|
      t.string :subject_kind, null: false          # skill | flow_step
      t.string :subject_key, null: false           # skill name, or "<flow id>:<step id>"
      t.string :title, null: false
      t.string :verdict, null: false               # macro | partial | ai
      t.integer :score, null: false, default: 0
      t.jsonb :signals, null: false, default: {}
      t.jsonb :suggestion, null: false, default: {} # {language, code, steps[], inputs[]}
      t.text :reason
      t.string :status, null: false, default: "proposed" # proposed | approved | rejected | needs_work
      t.references :proposed_by, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :review_notes
      t.integer :runs_saved, null: false, default: 0
      t.bigint :tokens_saved, null: false, default: 0
      t.timestamps
      t.index %i[subject_kind subject_key], unique: true
    end

    add_column :skill_runs, :engine, :string, null: false, default: "ai"   # ai | macro | person
    add_column :skill_runs, :nature, :string
    add_column :skill_runs, :cost, :decimal, precision: 12, scale: 4
    add_column :skill_runs, :estimated_tokens, :integer
    add_column :skill_runs, :part_id, :string
    add_column :skill_runs, :trial_of, :string      # groups runs of the same task tested on several models
    add_index :skill_runs, :trial_of
    add_column :flow_runs, :estimate, :jsonb, null: false, default: {}
  end
end
