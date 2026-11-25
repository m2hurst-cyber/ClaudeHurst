class AddOnboardingToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :tour_dismissed_at, :datetime
    add_column :users, :tour_seen_at, :datetime
  end
end
