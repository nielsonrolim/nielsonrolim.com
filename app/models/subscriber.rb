class Subscriber < ApplicationRecord
  attr_accessor :nickname

  validates :email, presence: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP },
                     uniqueness: { case_sensitive: false }
end
