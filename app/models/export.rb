class Export < ApplicationRecord
  belongs_to :repository

  validates :tag_name, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }
end
