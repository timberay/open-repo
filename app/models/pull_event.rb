class PullEvent < ApplicationRecord
  belongs_to :manifest
  belongs_to :repository

  validates :occurred_at, presence: true
end
