class User < ApplicationRecord
  include Auth::LoginTracker

  has_many :identities, dependent: :destroy
  belongs_to :primary_identity, class_name: "Identity", optional: true

  validates :email, presence: true, uniqueness: true

  def self.admin_email?(email)
    configured = Rails.configuration.x.registry.admin_email
    return false if configured.blank?
    configured.to_s.casecmp(email.to_s).zero?
  end
end
