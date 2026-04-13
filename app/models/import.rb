class Import < ApplicationRecord
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }
end
