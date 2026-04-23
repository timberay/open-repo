class Identity < ApplicationRecord
  belongs_to :user

  has_many :personal_access_tokens, dependent: :destroy

  validates :provider, presence: true
  validates :uid,      presence: true
  validates :email,    presence: true
  validates :uid, uniqueness: { scope: :provider }
end
