class Repository < ApplicationRecord
  belongs_to :owner_identity, class_name: "Identity"
  has_many :repository_members, dependent: :destroy
  has_many :member_identities, through: :repository_members, source: :identity
  has_many :tags, dependent: :destroy
  has_many :manifests, dependent: :destroy
  has_many :tag_events, dependent: :destroy
  has_many :blob_uploads, dependent: :destroy

  SEMVER_PATTERN = /\Av?\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/

  enum :tag_protection_policy,
       { none: "none", semver: "semver", all_except_latest: "all_except_latest", custom_regex: "custom_regex" },
       default: :none, prefix: :protection

  validates :name, presence: true, uniqueness: true
  validates :tag_protection_pattern, presence: true, if: :protection_custom_regex?
  validate :tag_protection_pattern_is_valid_regex, if: :protection_custom_regex?

  before_save :clear_tag_protection_pattern_unless_custom_regex

  # ---------------------------------------------------------------------------
  # Authorization methods (Stage 2)
  # ---------------------------------------------------------------------------

  # @param identity [Identity, nil]
  # @return [Boolean]
  def writable_by?(identity)
    return false if identity.nil?
    return true if owner_identity_id == identity.id
    repository_members.exists?(identity_id: identity.id, role: %w[writer admin])
  end

  # @param identity [Identity, nil]
  # @return [Boolean]
  def deletable_by?(identity)
    return false if identity.nil?
    return true if owner_identity_id == identity.id
    repository_members.exists?(identity_id: identity.id, role: "admin")
  end

  # Atomically transfers ownership and records an audit TagEvent.
  #
  # @param new_owner_identity [Identity]
  # @param by [User] the user performing the transfer (used for actor attribution)
  def transfer_ownership_to!(new_owner_identity, by:)
    transaction do
      previous_owner_id = owner_identity_id
      update!(owner_identity_id: new_owner_identity.id)
      repository_members
        .find_or_create_by!(identity_id: previous_owner_id) { |m| m.role = "admin" }
      TagEvent.create!(
        repository: self,
        tag_name: "-",
        action: "ownership_transfer",
        actor: by.primary_identity.email,
        actor_identity_id: by.primary_identity_id,
        occurred_at: Time.current
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Tag protection
  # ---------------------------------------------------------------------------

  def tag_protected?(tag_name)
    case tag_protection_policy
    when "none"              then false
    when "semver"            then tag_name.match?(SEMVER_PATTERN)
    when "all_except_latest" then tag_name != "latest"
    when "custom_regex"      then !!(protection_regex && tag_name.match?(protection_regex))
    end
  end

  # Raises Registry::TagProtected when the tag is protected and the operation
  # would mutate it. Used by ManifestProcessor (PUT), TagsController#destroy
  # (Web UI DELETE), V2::ManifestsController#destroy (Registry DELETE), and
  # EnforceRetentionPolicyJob (retention skip).
  #
  # @param tag_name [String]
  # @param new_digest [String, nil] for PUT, the digest being pushed; same
  #   digest as existing tag is idempotent (CI retry safety) and does not raise.
  # @param existing_tag [Tag, nil] pass an already-loaded Tag to avoid a
  #   duplicate `tags.find_by(name:)` query when the caller already has it.
  def enforce_tag_protection!(tag_name, new_digest: nil, existing_tag: :unset)
    return unless tag_protected?(tag_name)

    if new_digest
      current = existing_tag.equal?(:unset) ? tags.find_by(name: tag_name) : existing_tag
      return if current && current.manifest.digest == new_digest
    end

    raise Registry::TagProtected.new(tag: tag_name, policy: tag_protection_policy)
  end

  private

  def protection_regex
    return nil if tag_protection_pattern.blank?
    @protection_regex ||= Regexp.new(tag_protection_pattern)
  rescue RegexpError
    nil
  end

  def tag_protection_pattern_is_valid_regex
    return if tag_protection_pattern.blank?
    Regexp.new(tag_protection_pattern)
  rescue RegexpError => e
    errors.add(:tag_protection_pattern, "is not a valid regex: #{e.message}")
  end

  def clear_tag_protection_pattern_unless_custom_regex
    self.tag_protection_pattern = nil unless protection_custom_regex?
    @protection_regex = nil if tag_protection_policy_changed? || tag_protection_pattern_changed?
  end
end
