class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.references :subject, polymorphic: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.date :due_on
      t.datetime :completed_at
      t.string :priority, null: false, default: "normal"
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :tasks, :due_on
    add_index :tasks, :completed_at
    add_index :tasks, :discarded_at
  end
end
