class Blob < ApplicationRecord
  has_many :layers, dependent: :destroy
  has_many :manifests, through: :layers

  validates :digest, presence: true, uniqueness: true
  validates :size, presence: true
end
