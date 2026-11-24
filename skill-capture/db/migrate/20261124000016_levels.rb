class Levels < ActiveRecord::Migration[7.2]
  def change
    # The department a person works in (for the "Department" level: skills by colleagues).
    add_column :users, :department, :string
    add_index :users, :department
    # Who a market skill is shared with: the firm's industry, or everyone.
    add_column :skills, :market_audience, :string, null: false, default: "global"
  end
end
