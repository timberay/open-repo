class Layer < ApplicationRecord
  belongs_to :manifest
  belongs_to :blob

  validates :position, presence: true, uniqueness: { scope: :manifest_id }
end
