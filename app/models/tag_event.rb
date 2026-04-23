class TagEvent < ApplicationRecord
  belongs_to :repository
  belongs_to :actor_identity, class_name: "Identity", optional: true

  validates :tag_name, presence: true
  validates :action, presence: true,
            inclusion: { in: %w[create update delete ownership_transfer] }
  validates :occurred_at, presence: true

  # Render actor for display. Prefers actor_identity.email when FK is present
  # (Stage 2 rows). Falls back to string-based heuristic for legacy rows.
  def display_actor
    return actor_identity.email if actor_identity.present?
    return actor if actor.to_s.include?("@")
    "<system: #{actor.to_s.delete_prefix('system:')}>"
  end
end
