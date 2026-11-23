# Classification: a hierarchical field taxonomy (Finance › Accounting › Reconciliation)
# and the apps a skill uses. Set by AI inference or by people; people win.
class CreateFieldsAndClassifications < ActiveRecord::Migration[7.2]
  def change
    create_table :fields do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :path, null: false                # "finance/accounting/reconciliation"
      t.references :parent, foreign_key: { to_table: :fields }
      t.integer :position, null: false, default: 0
      t.string :keywords, array: true, null: false, default: [] # help rule-based inference
      t.timestamps
    end
    add_index :fields, :path, unique: true

    create_table :skill_classifications do |t|
      t.string :skill_name, null: false          # by name: survives new versions
      t.references :field, foreign_key: true
      t.string :apps, array: true, null: false, default: []
      t.string :source, null: false, default: "rules" # ai | rules | user
      t.float :confidence
      t.text :rationale
      t.boolean :confirmed, null: false, default: false # a person set or confirmed it; inference won't overwrite
      t.references :updated_by, foreign_key: { to_table: :users }
      t.datetime :inferred_at
      t.timestamps
    end
    add_index :skill_classifications, :skill_name, unique: true
  end
end
