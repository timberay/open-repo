class PersonalAccessToken < ApplicationRecord
  RAW_PREFIX = "oprk_".freeze
  DISPLAY_PREFIX_LENGTH = 12

  belongs_to :identity

  validates :name, presence: true, uniqueness: { scope: :identity_id }
  validates :token_digest, presence: true, uniqueness: true
  validates :prefix, presence: true
  validates :kind, inclusion: { in: %w[cli ci] }

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  def self.generate_raw
    RAW_PREFIX + SecureRandom.urlsafe_base64(32)
  end

  # Returns the leading slice of the raw token to store as a displayable
  # disambiguator (e.g., "oprk_xY9aBz2"). Safe to expose because the
  # remaining secret entropy is far longer than this slice.
  def self.prefix_for(raw_token)
    raw_token.to_s[0, DISPLAY_PREFIX_LENGTH]
  end

  # @param raw_token [String]
  # @return [PersonalAccessToken, nil]
  def self.authenticate_raw(raw_token)
    return nil if raw_token.blank?
    active.find_by(token_digest: Digest::SHA256.hexdigest(raw_token))
  end

  # One-shot policy-change cleanup: revoke every active PAT whose owner's email
  # domain is not in `allowed_domains`. A blank allowlist means "no restriction"
  # and revokes nothing. Returns the PATs that were revoked.
  def self.revoke_disallowed!(allowed_domains)
    return [] if allowed_domains.blank?

    revoked = []
    active.includes(identity: :user).each do |pat|
      domain = Auth::AllowedEmailDomains.domain_for(pat.identity.user.email)
      next if domain && allowed_domains.include?(domain)

      pat.revoke!
      revoked << pat
    end
    revoked
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
