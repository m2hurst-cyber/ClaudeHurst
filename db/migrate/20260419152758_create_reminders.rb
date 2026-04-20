class CreateReminders < ActiveRecord::Migration[7.1]
  def change
    create_table :reminders do |t|
      t.references :subject, polymorphic: true
      t.references :user, null: false, foreign_key: true
      t.datetime :remind_at, null: false
      t.string :channel, null: false, default: "in_app"
      t.string :recurrence, null: false, default: "none"
      t.text :message, null: false
      t.datetime :fired_at
      t.timestamps
    end
    add_index :reminders, :remind_at
    add_index :reminders, :fired_at
  end
end
