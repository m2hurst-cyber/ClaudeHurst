class Contact < ApplicationRecord
  include Discard::Model
  has_paper_trail

  belongs_to :company
  has_many :activities, as: :subject, dependent: :destroy

  validates :first_name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  scope :by_name, -> { order(:first_name, :last_name) }

  def display_name
    [first_name, last_name].compact.join(" ")
  end
end
