# Roads between skills on the route map. Links are by skill *name* so they survive
# new versions. "observed" links are recomputed from activity; "manual" ones are
# set by reviewers.
class CreateSkillLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :skill_links do |t|
      t.string :from_node, null: false          # skill name, or "candidate:<id>" for an unpublished workflow
      t.string :to_node, null: false
      t.string :origin, null: false            # observed | manual
      t.integer :traffic, null: false, default: 0 # observed transitions in the lookback window
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :skill_links, %i[from_node to_node origin], unique: true
    add_index :skill_links, :to_node
  end
end
