class AddLeadSourceToCompanies < ActiveRecord::Migration[7.2]
  def change
    add_column :companies, :lead_source, :string
    add_index :companies, :lead_source
  end
end
