class RepositoryMember < ApplicationRecord
  belongs_to :repository
  belongs_to :identity

  validates :role, inclusion: { in: %w[writer admin] }
  validates :identity_id, uniqueness: { scope: :repository_id }
end
