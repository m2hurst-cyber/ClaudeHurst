# Agent directions for every place on the route map:
#   road:<skill>            driving a skill's road
#   junction:<skill>        the intersection at the end of a skill: which exit to take
#   handoff:<from>><to>     the connector road between two skills
class CreateWaypoints < ActiveRecord::Migration[7.2]
  def change
    create_table :waypoints do |t|
      t.string :key, null: false
      t.string :kind, null: false            # road | junction | handoff
      t.string :from_name, null: false       # the skill (road/junction) or handoff origin
      t.string :to_name                      # handoff destination
      t.string :title, null: false
      t.text :body, null: false              # Markdown directions for agents (and people)
      t.string :tags, array: true, null: false, default: []
      t.integer :version, null: false, default: 1
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :waypoints, :key, unique: true
    add_index :waypoints, :from_name
    add_index :waypoints, :to_name
    execute <<~SQL
      CREATE INDEX index_waypoints_on_search ON waypoints
      USING gin (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, '')));
    SQL

    create_table :waypoint_revisions do |t|
      t.references :waypoint, null: false, foreign_key: true
      t.integer :version, null: false
      t.text :body, null: false
      t.string :note
      t.references :editor, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end
  end
end
