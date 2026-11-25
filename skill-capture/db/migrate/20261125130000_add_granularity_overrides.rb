class AddGranularityOverrides < ActiveRecord::Migration[7.2]
  def change
    create_table :granularity_overrides do |t|
      t.string  :scope, null: false        # "domain" or "user"
      t.string  :scope_key, null: false    # the area's name, or the user id
      t.integer :level, null: false
      t.timestamps
      t.index %i[scope scope_key], unique: true
    end
  end
end
