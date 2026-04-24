require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # validations
  # ---------------------------------------------------------------------------

  test "validations requires name" do
    repo = Repository.new(name: nil)
    refute repo.valid?
    assert_includes repo.errors[:name], "can't be blank"
  end

  test "validations requires unique name" do
    Repository.create!(name: "myapp", owner_identity: identities(:tonny_google))
    repo = Repository.new(name: "myapp")
    refute repo.valid?
    assert_includes repo.errors[:name], "has already been taken"
  end

  # ---------------------------------------------------------------------------
  # associations
  # ---------------------------------------------------------------------------

  test "associations has many tags" do
    assert_equal :has_many, Repository.reflect_on_association(:tags).macro
  end

  test "associations has many manifests" do
    assert_equal :has_many, Repository.reflect_on_association(:manifests).macro
  end

  test "associations has many tag_events" do
    assert_equal :has_many, Repository.reflect_on_association(:tag_events).macro
  end

  # ---------------------------------------------------------------------------
  # #tag_protected?
  # ---------------------------------------------------------------------------

  def repo_for_protection
    @repo_for_protection ||= Repository.create!(name: "example", owner_identity: identities(:tonny_google))
  end

  test "#tag_protected? when policy is none (default) returns false for any tag name" do
    repo = repo_for_protection
    refute repo.tag_protected?("v1.0.0")
    refute repo.tag_protected?("latest")
    refute repo.tag_protected?("anything")
  end

  test "#tag_protected? when policy is semver protects v-prefixed semver" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    assert repo.tag_protected?("v1.2.3")
  end

  test "#tag_protected? when policy is semver protects bare semver" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    assert repo.tag_protected?("1.2.3")
  end

  test "#tag_protected? when policy is semver protects semver with pre-release" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    assert repo.tag_protected?("1.2.3-rc1")
  end

  test "#tag_protected? when policy is semver protects semver with build metadata" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    assert repo.tag_protected?("1.2.3+build.5")
  end

  test "#tag_protected? when policy is semver does NOT protect latest" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    refute repo.tag_protected?("latest")
  end

  test "#tag_protected? when policy is semver does NOT protect partial versions" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    refute repo.tag_protected?("v1.2")
  end

  test "#tag_protected? when policy is semver does NOT protect branch names" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "semver")
    refute repo.tag_protected?("main")
  end

  test "#tag_protected? when policy is all_except_latest does NOT protect latest" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "all_except_latest")
    refute repo.tag_protected?("latest")
  end

  test "#tag_protected? when policy is all_except_latest protects everything else (including other floating names)" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "all_except_latest")
    assert repo.tag_protected?("v1.0.0")
    assert repo.tag_protected?("main")
    assert repo.tag_protected?("develop")
    assert repo.tag_protected?("anything")
  end

  test "#tag_protected? when policy is custom_regex protects names matching the pattern" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "custom_regex", tag_protection_pattern: '^release-\d+$')
    assert repo.tag_protected?("release-1")
    assert repo.tag_protected?("release-42")
  end

  test "#tag_protected? when policy is custom_regex does NOT protect non-matching names" do
    repo = repo_for_protection
    repo.update!(tag_protection_policy: "custom_regex", tag_protection_pattern: '^release-\d+$')
    refute repo.tag_protected?("release-1a")
    refute repo.tag_protected?("v1.0.0")
  end

  test "#tag_protected? when policy is custom_regex but in-memory pattern is invalid does not raise and returns false (view-render safety)" do
    repo = repo_for_protection
    repo.tag_protection_policy = "custom_regex"
    repo.tag_protection_pattern = "[unclosed"
    assert_nothing_raised { repo.tag_protected?("anything") }
    refute repo.tag_protected?("anything")
  end

  # ---------------------------------------------------------------------------
  # tag_protection_pattern validation
  # ---------------------------------------------------------------------------

  test "tag_protection_pattern validation requires pattern when policy is custom_regex" do
    repo = Repository.new(name: "x", tag_protection_policy: "custom_regex", tag_protection_pattern: nil)
    refute repo.valid?
    assert_includes repo.errors[:tag_protection_pattern], "can't be blank"
  end

  test "tag_protection_pattern validation rejects invalid regex" do
    repo = Repository.new(name: "x", tag_protection_policy: "custom_regex", tag_protection_pattern: "[unclosed")
    refute repo.valid?
    assert_match(/is not a valid regex/, repo.errors[:tag_protection_pattern].first)
  end

  test "tag_protection_pattern validation does NOT require pattern when policy is not custom_regex" do
    repo = Repository.new(name: "x", tag_protection_policy: "semver", tag_protection_pattern: nil, owner_identity: identities(:tonny_google))
    assert repo.valid?
  end

  # ---------------------------------------------------------------------------
  # before_save clears pattern when policy is not custom_regex
  # ---------------------------------------------------------------------------

  test "before_save clears pattern when policy is not custom_regex nullifies pattern when policy transitions to semver" do
    repo = Repository.create!(name: "x", tag_protection_policy: "custom_regex", tag_protection_pattern: "^v.+$", owner_identity: identities(:tonny_google))
    repo.update!(tag_protection_policy: "semver")
    assert_nil repo.reload.tag_protection_pattern
  end

  test "before_save clears pattern when policy is not custom_regex keeps pattern when policy stays custom_regex" do
    repo = Repository.create!(name: "y", tag_protection_policy: "custom_regex", tag_protection_pattern: "^v.+$", owner_identity: identities(:tonny_google))
    repo.update!(tag_protection_pattern: '^release-\d+$')
    assert_equal '^release-\d+$', repo.reload.tag_protection_pattern
  end

  # ---------------------------------------------------------------------------
  # #enforce_tag_protection!
  # ---------------------------------------------------------------------------

  def enforcement_repo
    @enforcement_repo ||= Repository.create!(name: "example", tag_protection_policy: "semver", owner_identity: identities(:tonny_google))
  end

  def enforcement_manifest
    @enforcement_manifest ||= begin
      m = enforcement_repo.manifests.create!(
        digest: "sha256:existing",
        media_type: "application/vnd.docker.distribution.manifest.v2+json",
        payload: "{}",
        size: 2
      )
      enforcement_repo.tags.create!(name: "v1.0.0", manifest: m)
      m
    end
  end

  def setup_enforcement
    enforcement_manifest # force creation of repo + manifest + tag
  end

  test "#enforce_tag_protection! when tag is not protected returns nil and does not raise" do
    setup_enforcement
    assert_nil enforcement_repo.enforce_tag_protection!("latest")
  end

  test "#enforce_tag_protection! when tag is protected and no existing tag raises Registry::TagProtected" do
    setup_enforcement
    err = assert_raises(Registry::TagProtected) do
      enforcement_repo.enforce_tag_protection!("v2.0.0")
    end
    assert_equal({ tag: "v2.0.0", policy: "semver" }, err.detail)
  end

  test "#enforce_tag_protection! when tag is protected and existing digest differs raises Registry::TagProtected" do
    setup_enforcement
    assert_raises(Registry::TagProtected) do
      enforcement_repo.enforce_tag_protection!("v1.0.0", new_digest: "sha256:different")
    end
  end

  test "#enforce_tag_protection! when tag is protected and existing digest matches (idempotent) does not raise" do
    setup_enforcement
    assert_nothing_raised do
      enforcement_repo.enforce_tag_protection!("v1.0.0", new_digest: "sha256:existing")
    end
  end

  test "#enforce_tag_protection! when called with an already-loaded tag (to avoid duplicate query) accepts existing_tag keyword and uses it" do
    setup_enforcement
    tag = enforcement_repo.tags.find_by(name: "v1.0.0")
    assert_nothing_raised do
      enforcement_repo.enforce_tag_protection!("v1.0.0", new_digest: "sha256:existing", existing_tag: tag)
    end
  end

  # ---------------------------------------------------------------------------
  # Stage 2: ownership associations + authorization methods
  # ---------------------------------------------------------------------------

  def owner_identity
    identities(:tonny_google)
  end

  def other_identity
    identities(:admin_google)
  end

  def owned_repo
    @owned_repo ||= Repository.create!(
      name: "owned-repo-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
  end

  test "belongs_to :owner_identity" do
    assert_equal :belongs_to, Repository.reflect_on_association(:owner_identity).macro
  end

  test "has_many :repository_members" do
    assert_equal :has_many, Repository.reflect_on_association(:repository_members).macro
  end

  test "writable_by? returns true for owner" do
    assert owned_repo.writable_by?(owner_identity)
  end

  test "writable_by? returns false for nil identity" do
    refute owned_repo.writable_by?(nil)
  end

  test "writable_by? returns false for stranger with no membership" do
    refute owned_repo.writable_by?(other_identity)
  end

  test "writable_by? returns true for writer member" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "writer")
    assert owned_repo.writable_by?(other_identity)
  end

  test "writable_by? returns true for admin member" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "admin")
    assert owned_repo.writable_by?(other_identity)
  end

  test "deletable_by? returns true for owner" do
    assert owned_repo.deletable_by?(owner_identity)
  end

  test "deletable_by? returns false for nil identity" do
    refute owned_repo.deletable_by?(nil)
  end

  test "deletable_by? returns false for writer member (not admin)" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "writer")
    refute owned_repo.deletable_by?(other_identity)
  end

  test "deletable_by? returns true for admin member" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "admin")
    assert owned_repo.deletable_by?(other_identity)
  end

  test "transfer_ownership_to! changes owner_identity_id" do
    repo = owned_repo
    repo.transfer_ownership_to!(other_identity, by: users(:tonny))
    repo.reload
    assert_equal other_identity.id, repo.owner_identity_id
  end

  test "transfer_ownership_to! adds previous owner as admin member" do
    repo = owned_repo
    repo.transfer_ownership_to!(other_identity, by: users(:tonny))
    assert RepositoryMember.exists?(repository: repo, identity: owner_identity, role: "admin")
  end

  test "transfer_ownership_to! creates ownership_transfer TagEvent" do
    repo = owned_repo
    assert_difference -> { TagEvent.where(action: "ownership_transfer").count }, +1 do
      repo.transfer_ownership_to!(other_identity, by: users(:tonny))
    end
    event = TagEvent.where(action: "ownership_transfer").last
    assert_equal users(:tonny).primary_identity.email, event.actor
    assert_equal users(:tonny).primary_identity_id, event.actor_identity_id
  end
end
