class Tag < ApplicationRecord
  belongs_to :repository, counter_cache: true
  belongs_to :manifest

  validates :name, presence: true, uniqueness: { scope: :repository_id }
end
