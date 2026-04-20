class CreateContacts < ActiveRecord::Migration[7.1]
  def change
    create_table :contacts do |t|
      t.references :company, null: false, foreign_key: true
      t.string :first_name, null: false
      t.string :last_name
      t.string :title
      t.string :email
      t.string :phone
      t.boolean :primary, null: false, default: false
      t.datetime :discarded_at
      t.timestamps
    end
    add_index :contacts, :email
    add_index :contacts, :discarded_at
  end
end
