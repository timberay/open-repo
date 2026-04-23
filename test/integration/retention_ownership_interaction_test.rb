require "test_helper"

class RetentionOwnershipInteractionTest < ActionDispatch::IntegrationTest
  setup do
    ENV["RETENTION_ENABLED"]            = "true"
    ENV["RETENTION_DAYS_WITHOUT_PULL"]  = "90"
    ENV["RETENTION_MIN_PULL_COUNT"]     = "5"
    ENV["RETENTION_PROTECT_LATEST"]     = "true"
  end

  teardown do
    %w[RETENTION_ENABLED RETENTION_DAYS_WITHOUT_PULL
       RETENTION_MIN_PULL_COUNT RETENTION_PROTECT_LATEST].each { |k| ENV.delete(k) }
  end

  # Scenario 1: retention deletes stale tag on another-user-owned repo without raising
  test "retention deletes owned-by-other stale tag without raising" do
    other_identity = identities(:admin_google)
    repo = Repository.create!(
      name: "retention-other-#{SecureRandom.hex(4)}",
      owner_identity: other_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:stale#{SecureRandom.hex(28)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "old-release")

    assert_difference -> { TagEvent.where(actor: "retention-policy").count }, +1 do
      assert_difference -> { repo.tags.count }, -1 do
        EnforceRetentionPolicyJob.perform_now
      end
    end

    event = TagEvent.order(:occurred_at).last
    assert_equal "retention-policy", event.actor
    assert_nil event.actor_identity_id
  end

  # Scenario 2: retention skips tag protected by semver policy
  test "retention skips tag protected by policy even if owner-identity is set" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "retention-protected-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "semver"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:vstale#{SecureRandom.hex(27)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "v1.0.0")

    assert_no_difference -> { repo.tags.count } do
      EnforceRetentionPolicyJob.perform_now
    end
    refute TagEvent.exists?(repository: repo, tag_name: "v1.0.0", action: "delete")
  end

  # Scenario 3: retention job does NOT call authorize_for!
  # Indirect assertion: job runs without current_user (current_user = nil in job context).
  # If authorize_for! were called, it would raise Auth::Unauthenticated.
  # We assert the job completes and produces the expected TagEvent — no exception.
  test "retention job runs without current_user and produces TagEvent without raising" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "retention-noauth-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:noauth#{SecureRandom.hex(27)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "stale-tag")

    # assert_nothing_raised: if authorize_for! leaked, Auth::Unauthenticated would raise here
    assert_nothing_raised do
      assert_difference -> { TagEvent.where(actor: "retention-policy").count }, +1 do
        EnforceRetentionPolicyJob.perform_now
      end
    end

    event = TagEvent.order(:occurred_at).last
    assert_equal "retention-policy", event.actor
    assert_nil event.actor_identity_id,
               "retention events must not carry actor_identity_id (no user context)"
  end
end
