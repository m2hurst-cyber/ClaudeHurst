class NumberSequence < ApplicationRecord
  validates :scope, :year, presence: true

  def self.next_for(scope, at: Time.current)
    year = at.year
    transaction do
      seq = lock.find_or_create_by!(scope: scope, year: year)
      seq.update!(last_value: seq.last_value + 1)
      seq.last_value
    end
  end
end
