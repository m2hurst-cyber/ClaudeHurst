class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :subject, polymorphic: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.string :url
      t.datetime :read_at
      t.datetime :emailed_at
      t.timestamps
    end
    add_index :notifications, :read_at
  end
end
