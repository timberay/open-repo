require "test_helper"

class EnforceRetentionPolicyJobTest < ActiveJob::TestCase
  def setup
    @repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    @manifest = Manifest.create!(
      repository: @repo,
      digest: "sha256:stale",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100,
      pull_count: 0,
      last_pulled_at: 100.days.ago
    )
  end

  # --- retention disabled (default) ---

  test "perform does nothing when retention is disabled" do
    Tag.create!(repository: @repo, manifest: @manifest, name: "old-tag")

    EnforceRetentionPolicyJob.perform_now

    assert Tag.find_by(name: "old-tag").present?
  end

  # --- retention enabled ---

  test "perform with retention enabled deletes stale tags" do
    with_retention_enabled do
      Tag.create!(repository: @repo, manifest: @manifest, name: "old-tag")

      EnforceRetentionPolicyJob.perform_now

      assert_nil Tag.find_by(name: "old-tag")
    end
  end

  test "perform with retention enabled protects latest tag by default" do
    with_retention_enabled do
      Tag.create!(repository: @repo, manifest: @manifest, name: "latest")

      EnforceRetentionPolicyJob.perform_now

      assert Tag.find_by(name: "latest").present?
    end
  end

  # --- retention enabled + tag_protection_policy=semver ---

  test "perform with retention enabled and semver policy does NOT delete the protected v1.0.0 tag" do
    with_retention_enabled do
      @repo.update!(tag_protection_policy: "semver")
      tag = Tag.create!(repository: @repo, manifest: @manifest, name: "v1.0.0")

      EnforceRetentionPolicyJob.perform_now

      assert Tag.find_by(id: tag.id).present?
    end
  end

  test "perform with retention enabled and semver policy does NOT record a tag_event for the skipped protected tag" do
    with_retention_enabled do
      @repo.update!(tag_protection_policy: "semver")
      Tag.create!(repository: @repo, manifest: @manifest, name: "v1.0.0")

      assert_no_difference -> { TagEvent.where(tag_name: "v1.0.0").count } do
        EnforceRetentionPolicyJob.perform_now
      end
    end
  end

  test "perform with retention enabled and semver policy still preserves latest" do
    with_retention_enabled do
      @repo.update!(tag_protection_policy: "semver")
      Tag.create!(repository: @repo, manifest: @manifest, name: "latest")

      EnforceRetentionPolicyJob.perform_now

      assert Tag.find_by(name: "latest").present?
    end
  end

  # --- retention enabled + tag_protection_policy=all_except_latest ---

  test "perform with retention enabled and all_except_latest policy preserves v1.0.0" do
    with_retention_enabled do
      @repo.update!(tag_protection_policy: "all_except_latest")
      tag = Tag.create!(repository: @repo, manifest: @manifest, name: "v1.0.0")

      EnforceRetentionPolicyJob.perform_now

      assert Tag.find_by(id: tag.id).present?
    end
  end

  private

  def with_retention_enabled
    keys = %w[RETENTION_ENABLED RETENTION_DAYS_WITHOUT_PULL RETENTION_MIN_PULL_COUNT]
    original = keys.index_with { |k| ENV[k] }
    ENV["RETENTION_ENABLED"] = "true"
    ENV["RETENTION_DAYS_WITHOUT_PULL"] = "90"
    ENV["RETENTION_MIN_PULL_COUNT"] = "5"
    yield
  ensure
    keys.each { |k| original[k] ? ENV[k] = original[k] : ENV.delete(k) }
  end
end
