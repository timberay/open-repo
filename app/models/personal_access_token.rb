class PersonalAccessToken < ApplicationRecord
  RAW_PREFIX = "oprk_".freeze

  belongs_to :identity

  validates :name, presence: true, uniqueness: { scope: :identity_id }
  validates :token_digest, presence: true, uniqueness: true
  validates :kind, inclusion: { in: %w[cli ci] }

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  def self.generate_raw
    RAW_PREFIX + SecureRandom.urlsafe_base64(32)
  end

  # @param raw_token [String]
  # @return [PersonalAccessToken, nil]
  def self.authenticate_raw(raw_token)
    return nil if raw_token.blank?
    active.find_by(token_digest: Digest::SHA256.hexdigest(raw_token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
