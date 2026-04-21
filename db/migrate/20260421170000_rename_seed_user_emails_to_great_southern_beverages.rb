class RenameSeedUserEmailsToGreatSouthernBeverages < ActiveRecord::Migration[7.1]
  EMAIL_MAP = {
    "admin@greatsoutherncopacker.test" => "admin@greatsouthernbeverages.test",
    "sally.sales@greatsoutherncopacker.test" => "sally.sales@greatsouthernbeverages.test",
    "omar.ops@greatsoutherncopacker.test" => "omar.ops@greatsouthernbeverages.test",
    "fred.finance@greatsoutherncopacker.test" => "fred.finance@greatsouthernbeverages.test",
    "sam.sales@greatsoutherncopacker.test" => "sam.sales@greatsouthernbeverages.test",
    "olive.ops@greatsoutherncopacker.test" => "olive.ops@greatsouthernbeverages.test"
  }.freeze

  def up
    EMAIL_MAP.each do |old_email, new_email|
      execute <<~SQL.squish
        UPDATE users
        SET email = #{connection.quote(new_email)}
        WHERE email = #{connection.quote(old_email)}
          AND NOT EXISTS (
            SELECT 1 FROM users existing_users WHERE existing_users.email = #{connection.quote(new_email)}
          )
      SQL
    end
  end

  def down
    EMAIL_MAP.each do |old_email, new_email|
      execute <<~SQL.squish
        UPDATE users
        SET email = #{connection.quote(old_email)}
        WHERE email = #{connection.quote(new_email)}
          AND NOT EXISTS (
            SELECT 1 FROM users existing_users WHERE existing_users.email = #{connection.quote(old_email)}
          )
      SQL
    end
  end
end