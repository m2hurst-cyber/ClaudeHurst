class AddCapabilities < ActiveRecord::Migration[7.2]
  def change
    # What a skill says it touches, and what the screen found in its text.
    add_column :skills, :capabilities, :jsonb, null: false, default: {}
    add_column :skill_candidates, :capabilities, :jsonb, null: false, default: {}
  end
end
