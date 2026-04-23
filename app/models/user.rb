class User < ApplicationRecord
  has_many :identities, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
