class PromptEvaluation < ActiveRecord::Migration[7.2]
  def change
    # When the save / extend / branch triggers last ran for this person (they run at most every N minutes).
    add_column :users, :prompts_checked_at, :datetime
  end
end
