class CreateGitBackups < ActiveRecord::Migration[7.2]
  def change
    create_table :git_backups do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string  :host, null: false, default: "github.com"
      t.string  :repo, null: false              # owner/name
      t.string  :branch, null: false, default: "main"
      t.string  :path_prefix, null: false, default: "skills"
      t.text    :token, null: false             # encrypted at rest
      t.string  :token_hint                     # last four, so a person can tell which token this is
      t.boolean :enabled, null: false, default: true
      t.datetime :last_pushed_at
      t.string  :last_commit_sha
      t.integer :last_skill_count
      t.text    :last_error
      t.timestamps
    end
  end
end
