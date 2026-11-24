class AiWrittenShareableMacros < ActiveRecord::Migration[7.2]
  def change
    add_column :macro_reviews, :written_by, :string, null: false, default: "rules" # rules | ai | person
    add_column :macro_reviews, :source_run_id, :bigint
    add_column :macro_reviews, :visibility, :string, null: false, default: "firm"  # private | firm | market
    add_column :macro_reviews, :copied_from_id, :bigint
    add_column :macro_reviews, :app, :string
    add_index :macro_reviews, %i[status visibility]
    add_index :macro_reviews, :copied_from_id
  end
end
