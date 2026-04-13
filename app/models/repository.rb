class Repository < ApplicationRecord
  has_many :tags, dependent: :destroy
  has_many :manifests, dependent: :destroy
  has_many :tag_events, dependent: :destroy
  has_many :blob_uploads, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
