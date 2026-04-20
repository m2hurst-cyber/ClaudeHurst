class CreateActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :activities do |t|
      t.references :subject, polymorphic: true, null: false
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.datetime :occurred_at, null: false
      t.text :body
      t.integer :duration_minutes
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :activities, :occurred_at
    add_index :activities, :kind
  end
end
