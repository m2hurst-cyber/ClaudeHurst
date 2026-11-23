class CreditEntry < ApplicationRecord
  belongs_to :user
  belongs_to :bounty, optional: true
  validates :amount, :reason, presence: true

  def self.balances = group(:user_id).sum(:amount)
end
