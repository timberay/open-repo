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

  # One-shot policy-change cleanup: revoke every active PAT whose owning
  # identity's current email domain is not in `allowed_domains`. The identity
  # email (not the user's, which is set once at creation and never refreshed) is
  # the authority, matching what the sign-in gate verifies. A blank allowlist
  # means "no restriction" and revokes nothing. Returns the revoked PATs.
  def self.revoke_disallowed!(allowed_domains)
    return [] if allowed_domains.blank?

    disallowed_ids = []
    active.includes(:identity).find_each do |pat|
      domain = Auth::AllowedEmailDomains.domain_for(pat.identity.email)
      disallowed_ids << pat.id unless domain && allowed_domains.include?(domain)
    end
    return [] if disallowed_ids.empty?

    # update_all: one statement, skips per-row validations so a single dirty row
    # can't abort the sweep mid-loop.
    where(id: disallowed_ids).update_all(revoked_at: Time.current, updated_at: Time.current)
    where(id: disallowed_ids).to_a
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
