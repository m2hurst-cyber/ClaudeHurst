# Each Office install that a person connects gets its own revocable token.
class CreateAddinTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :addin_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :host                       # Excel | Word | PowerPoint (as reported at connect)
      t.string :platform                   # PC | Mac | OfficeOnline | iOS ...
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :addin_tokens, :token_digest, unique: true
  end
end
