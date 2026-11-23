class ReturnDocuments < ActiveRecord::Migration[7.2]
  def change
    # A tax document uploaded to a return. The file, its name, the payer and the figures read
    # from it are encrypted at rest (ActiveRecord encryption); only metadata is plain.
    create_table :return_documents do |t|
      t.references :playbook_run, null: false, foreign_key: true
      t.string :kind                       # catalog key (w2, 1099-int, form-1040, ...), nil until identified
      t.string :label                      # "W-2 #1"
      t.text :filename                     # encrypted
      t.text :payer                        # encrypted
      t.string :content_type, null: false
      t.integer :byte_size, null: false
      t.string :checksum, null: false
      t.text :content, null: false         # encrypted, base64
      t.text :fields_json                  # encrypted, {"box1": 1234.56, ...}
      t.integer :tax_year
      t.string :status, null: false, default: "uploaded" # uploaded | reading | read | confirmed | failed
      t.string :read_by                    # ai | manual | sample
      t.integer :confidence
      t.text :notes
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
      t.timestamps
      t.index %i[playbook_run_id checksum], unique: true
    end

    # Each leg's preparation and verification, filer inputs and attestations, and a reviewer.
    add_column :playbook_runs, :legs, :jsonb, null: false, default: {}
    add_column :playbook_runs, :inputs, :jsonb, null: false, default: {}
    add_reference :playbook_runs, :reviewer, foreign_key: { to_table: :users }
    add_column :playbook_runs, :reviewed_at, :datetime
  end
end
