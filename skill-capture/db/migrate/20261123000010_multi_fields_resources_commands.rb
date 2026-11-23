# Many fields per skill (user-extensible taxonomy), a resource library of callable
# folders, and commands that send skills from the map to a running add-in or agent.
class MultiFieldsResourcesCommands < ActiveRecord::Migration[7.2]
  def up
    add_reference :fields, :created_by, foreign_key: { to_table: :users }

    create_table :skill_field_assignments do |t|
      t.references :skill_classification, null: false, foreign_key: true
      t.references :field, null: false, foreign_key: true
      t.integer :position, null: false, default: 0   # 0 = primary
      t.string :source, null: false, default: "rules" # ai | rules | user
      t.timestamps
    end
    add_index :skill_field_assignments, %i[skill_classification_id field_id], unique: true, name: "index_skill_field_assignments_unique"
    execute <<~SQL
      INSERT INTO skill_field_assignments (skill_classification_id, field_id, position, source, created_at, updated_at)
      SELECT id, field_id, 0, source, NOW(), NOW() FROM skill_classifications WHERE field_id IS NOT NULL
    SQL

    create_table :resource_folders do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :path, null: false
      t.references :parent, foreign_key: { to_table: :resource_folders }
      t.string :audience, null: false, default: "firm" # firm (people + agents) | restricted (listed areas + admins)
      t.string :areas, array: true, null: false, default: []
      t.text :description
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :resource_folders, :path, unique: true

    create_table :resources do |t|
      t.references :folder, null: false, foreign_key: { to_table: :resource_folders }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :kind, null: false, default: "file"   # file | link
      t.string :url                                  # for links (e.g. SharePoint)
      t.string :filename
      t.string :content_type
      t.integer :byte_size
      t.string :checksum
      t.binary :content
      t.integer :version, null: false, default: 1
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :resources, %i[folder_id slug], unique: true

    create_table :skill_resources do |t|
      t.string :skill_name, null: false
      t.references :resource, null: false, foreign_key: true
      t.string :note
      t.references :added_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :skill_resources, %i[skill_name resource_id], unique: true

    create_table :addin_commands do |t|
      t.references :sender, foreign_key: { to_table: :users }
      t.references :target_user, foreign_key: { to_table: :users }   # their running add-in(s)
      t.references :target_source, foreign_key: { to_table: :sources } # an agent integration
      t.string :kind, null: false                     # load_skill | load_route
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending" # pending | delivered | expired
      t.datetime :delivered_at
      t.string :delivered_to                           # e.g. "Excel on OfficeOnline"
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :addin_commands, %i[target_user_id status]
    add_index :addin_commands, %i[target_source_id status]
  end

  def down
    drop_table :addin_commands
    drop_table :skill_resources
    drop_table :resources
    drop_table :resource_folders
    drop_table :skill_field_assignments
    remove_reference :fields, :created_by
  end
end
