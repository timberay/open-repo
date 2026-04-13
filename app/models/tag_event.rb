class TagEvent < ApplicationRecord
  belongs_to :repository

  validates :tag_name, presence: true
  validates :action, presence: true, inclusion: { in: %w[create update delete] }
  validates :occurred_at, presence: true
end
