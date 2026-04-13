class Manifest < ApplicationRecord
  belongs_to :repository
  has_many :tags, dependent: :nullify
  has_many :layers, dependent: :destroy
  has_many :blobs, through: :layers
  has_many :pull_events, dependent: :destroy

  validates :digest, presence: true, uniqueness: true
  validates :media_type, presence: true
  validates :payload, presence: true
  validates :size, presence: true
end
