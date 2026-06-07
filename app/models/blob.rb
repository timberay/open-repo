class Blob < ApplicationRecord
  has_many :layers, dependent: :destroy
  has_many :manifests, through: :layers

  validates :digest, presence: true, uniqueness: true
  validates :size, presence: true

  # A blob is live if ANY manifest references it — either as a layer (via a
  # Layer row) or as the image config (manifests.config_digest, which has no
  # Layer row and never bumps references_count). references_count is a fast
  # index that can drift, so deletion/GC decisions must consult real references.
  def referenced?
    layers.exists? || Manifest.exists?(config_digest: digest)
  end
end
