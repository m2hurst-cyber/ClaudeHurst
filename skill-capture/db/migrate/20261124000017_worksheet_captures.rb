class WorksheetCaptures < ActiveRecord::Migration[7.2]
  def change
    # Observe → Interpret → Document → Write: one captured worksheet and the files made from it.
    create_table :worksheet_captures do |t|
      t.references :user, null: false, foreign_key: true
      t.string :sheet_name, null: false
      t.string :address
      t.string :provider                     # bql | factset | excel
      t.jsonb :observed, null: false, default: {}      # labels and formulas by cell (never numbers)
      t.jsonb :interpretation, null: false, default: {}
      t.jsonb :inventory, null: false, default: []      # one entry per formula pattern
      t.jsonb :blueprint, null: false, default: {}
      t.text :structure_md
      t.text :formulas_md
      t.text :skill_md
      t.string :interpreted_by                 # ai | rules
      t.string :status, null: false, default: "written"
      t.references :candidate, foreign_key: { to_table: :skill_candidates }
      t.timestamps
    end
    add_column :skill_candidates, :worksheet, :jsonb
  end
end
