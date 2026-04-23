class User < ApplicationRecord
  include Auth::LoginTracker

  has_many :identities, dependent: :destroy
  belongs_to :primary_identity, class_name: "Identity", optional: true

  validates :email, presence: true, uniqueness: true
end
