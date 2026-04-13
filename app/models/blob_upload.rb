class BlobUpload < ApplicationRecord
  belongs_to :repository

  validates :uuid, presence: true, uniqueness: true
end
