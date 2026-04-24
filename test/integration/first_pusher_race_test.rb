require "test_helper"

class FirstPusherRaceTest < ActionDispatch::IntegrationTest
  include TokenFixtures

  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
    @repos_to_clean = []
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
    # Ensure test repositories are cleaned up even if not using transactional tests
    Repository.where(id: @repos_to_clean).destroy_all
  end

  # Scenario 1: First-pusher-owner pattern in absence of concurrent race
  # When a user pushes to a new repository (no race), they become owner.
  # When another non-member user tries to push, they get 403.
  # With the fix, if a race DOES occur (RecordNotUnique), the losing racer
  # gets 202 (not 403), because the rescue path no longer calls authorize_for!.
  test "concurrent first-push: first pusher becomes owner" do
    repo_name = "push-owner-#{SecureRandom.hex(4)}"
    tonny_auth = ActionController::HttpAuthentication::Basic.encode_credentials(
      "tonny@timberay.com", TONNY_CLI_RAW
    )

    env = Rack::MockRequest.env_for(
      "/v2/#{repo_name}/blobs/uploads",
      method: "POST",
      "HTTP_AUTHORIZATION" => tonny_auth
    )
    status, _headers, body = Rails.application.call(env)
    body.close if body.respond_to?(:close)

    assert_equal 202, status, "first pusher should get 202"
    assert_equal 1, Repository.where(name: repo_name).count
    repo = Repository.find_by!(name: repo_name)
    @repos_to_clean << repo.id
    assert_equal identities(:tonny_google).id, repo.owner_identity_id
  end

  # Scenario 2: push to existing repo by non-member returns 403
  test "push to existing repo does NOT reassign owner_identity_id" do
    owner_identity = identities(:tonny_google)
    repo_name = "pre-existing-#{SecureRandom.hex(4)}"
    repo = Repository.create!(
      name: repo_name,
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )

    admin_hdrs = basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    post "/v2/#{repo.name}/blobs/uploads", headers: admin_hdrs

    assert_equal 403, response.status
    repo.reload
    assert_equal owner_identity.id, repo.owner_identity_id,
                 "owner_identity_id must not change"
  ensure
    Repository.where(name: repo_name).destroy_all if defined?(repo_name) && repo_name
  end

  # Scenario 3: writer member can push to existing repo
  test "writer member push to existing repo returns 202" do
    owner_identity = identities(:tonny_google)
    repo_name = "member-push-#{SecureRandom.hex(4)}"
    repo = Repository.create!(
      name: repo_name,
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    RepositoryMember.create!(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )

    admin_hdrs = basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    post "/v2/#{repo.name}/blobs/uploads", headers: admin_hdrs

    assert_equal 202, response.status
  ensure
    if defined?(repo) && repo&.persisted?
      RepositoryMember.where(repository: repo).destroy_all
    end
    Repository.where(name: repo_name).destroy_all if defined?(repo_name) && repo_name
  end
end
