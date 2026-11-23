class Playbooks < ActiveRecord::Migration[7.2]
  def change
    # A question asked at intake; "yes" adds its branch skill to the route after the step it hangs off.
    create_table :situations do |t|
      t.string :playbook_key, null: false
      t.string :key, null: false
      t.text :question, null: false
      t.string :after_skill, null: false       # the mainline step it leaves after
      t.string :branch_skill                   # the branch skill (once published)
      t.string :forms, array: true, null: false, default: []
      t.string :keywords, array: true, null: false, default: []
      t.string :status, null: false, default: "active" # active | proposed | retired
      t.integer :position, null: false, default: 0
      t.references :candidate, foreign_key: { to_table: :skill_candidates }
      t.references :proposed_by, foreign_key: { to_table: :users }
      t.timestamps
      t.index %i[playbook_key key], unique: true
    end

    # One person working one return through a playbook. Holds answers and progress only:
    # no names, identifiers or amounts.
    create_table :playbook_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :playbook_key, null: false
      t.string :reference, null: false
      t.jsonb :answers, null: false, default: {}
      t.string :done, array: true, null: false, default: []
      t.string :status, null: false, default: "open"
      t.datetime :completed_at
      t.timestamps
      t.index %i[user_id status]
    end
  end
end
