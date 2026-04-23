class TagEvent < ApplicationRecord
  belongs_to :repository

  validates :tag_name, presence: true
  validates :action, presence: true, inclusion: { in: %w[create update delete] }
  validates :occurred_at, presence: true

  def display_actor
    return actor if actor.to_s.include?("@")
    "<system: #{actor.to_s.delete_prefix('system:')}>"
  end
end
