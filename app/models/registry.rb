class Registry < ApplicationRecord
  has_secure_password validations: false

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP/HTTPS URL" }
  before_save :ensure_single_default, if: :is_default_changed?

  scope :active, -> { where(is_active: true) }

  def self.default
    find_by(is_default: true)
  end

  def display_name
    "[ENV] #{name}" if from_env?
    name
  end

  def from_env?
    false
  end

  def connection_status
    return :unknown if last_connected_at.nil?
    return :connected if last_connected_at > 5.minutes.ago
    :stale
  end

  def connection_status_icon
    case connection_status
    when :connected then "●"
    when :stale then "◐"
    else "○"
    end
  end

  def masked_password
    return nil if password_digest.nil?
    "••••••••"
  end

  private

  def ensure_single_default
    if is_default?
      Registry.where.not(id: id).update_all(is_default: false)
    end
  end
end
