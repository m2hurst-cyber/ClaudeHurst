class FormulaCommands < ActiveRecord::Migration[7.2]
  def change
    # A data provider's Excel formula (BQL, FactSet, ...): the small commands worksheet skills are built from.
    create_table :formula_commands do |t|
      t.string :provider, null: false                 # bql | factset | ...
      t.string :key, null: false                      # shared semantic key, e.g. revenue, pe_ratio
      t.string :name, null: false
      t.string :category, null: false, default: "Other"
      t.text :syntax, null: false                     # =BQL({security},"sales_rev_turn(fpt={fpt}, fpo={fpo})")
      t.jsonb :defaults, null: false, default: {}
      t.text :description
      t.string :status, null: false, default: "unverified" # unverified | verified | deprecated
      t.string :origin, null: false, default: "pack"  # pack | import | console
      t.text :verification_note
      t.references :verified_by, foreign_key: { to_table: :users }
      t.datetime :verified_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
      t.index %i[provider key], unique: true
      t.index %i[provider category]
    end
  end
end
