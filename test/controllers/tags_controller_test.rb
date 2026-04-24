require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @repo = Repository.create!(
      name: "example",
      owner_identity: identities(:tonny_google)
    )
    @manifest = @repo.manifests.create!(
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    @tag = @repo.tags.create!(name: "v1.0.0", manifest: @manifest)
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
  end

  test "GET /repositories/:name/tags/:name renders each layer digest with a click-to-copy affordance carrying the full digest" do
    blob = Blob.create!(digest: "sha256:1d1ddb624e47aabbccddeeff0011223344556677", size: 4096)
    Layer.create!(manifest: @manifest, blob: blob, position: 0)

    get "/repositories/#{@repo.name}/tags/#{@tag.name}"

    assert_response :success
    assert_equal 2, response.body.scan("data-clipboard-text-value=\"#{blob.digest}\"").size
    assert_equal 2, response.body.scan(%r{aria-label="Copy digest 1d1ddb624e47"}).size
  end

  test "DELETE /repositories/:name/tags/:name when tag is not protected deletes the tag and redirects" do
    delete "/repositories/#{@repo.name}/tags/#{@tag.name}"
    assert_redirected_to repository_path(@repo.name)
    assert_nil Tag.find_by(id: @tag.id)
  end

  test "DELETE /repositories/:name/tags/:name when tag is protected by semver policy does NOT delete the tag" do
    @repo.update!(tag_protection_policy: "semver")
    delete "/repositories/#{@repo.name}/tags/#{@tag.name}"
    assert @tag.reload.present?
  end

  test "DELETE /repositories/:name/tags/:name when tag is protected by semver policy redirects to the repository page with a flash error" do
    @repo.update!(tag_protection_policy: "semver")
    delete "/repositories/#{@repo.name}/tags/#{@tag.name}"
    assert_redirected_to repository_path(@repo.name)
    assert_includes flash[:alert], "protected"
    assert_includes flash[:alert], "semver"
  end

  test "DELETE /repositories/:name/tags/:name when tag is protected by semver policy does NOT record a tag_event" do
    @repo.update!(tag_protection_policy: "semver")
    assert_no_difference -> { TagEvent.count } do
      delete "/repositories/#{@repo.name}/tags/#{@tag.name}"
    end
  end

  # --- Task 2.6: Web UI actor 실명화 ---

  test "authenticated destroy records TagEvent.actor = current_user.email" do
    repo = Repository.create!(name: "web-actor-test-repo", owner_identity: identities(:tonny_google))
    manifest = repo.manifests.create!(
      digest: "sha256:web-actor-#{SecureRandom.hex(4)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    tag = repo.tags.create!(name: "web-v1", manifest: manifest)

    assert_difference -> { TagEvent.where(actor: "tonny@timberay.com", action: "delete").count }, +1 do
      delete "/repositories/#{repo.name}/tags/#{tag.name}"
    end
  end

  # ---------------------------------------------------------------------------
  # Stage 2: destroy authz + actor_identity_id
  # ---------------------------------------------------------------------------

  test "DELETE tag by non-owner/non-member redirects with alert" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "tags-authz-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    tag = manifest.tags.create!(repository: repo, name: "v1")

    # admin user (not owner) — overrides the setup sign-in
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    delete "/repositories/#{repo.name}/tags/#{tag.name}"

    assert_redirected_to repository_path(repo.name)
    assert_match(/permission/, flash[:alert])
    assert Tag.exists?(id: tag.id), "tag should still exist"
  end

  test "DELETE tag by owner records actor_identity_id on TagEvent" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "tags-actid-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    tag = manifest.tags.create!(repository: repo, name: "v1")

    # setup already signed in as tonny (owner)
    delete "/repositories/#{repo.name}/tags/#{tag.name}"

    assert_redirected_to repository_path(repo.name)
    event = TagEvent.order(:occurred_at).last
    assert_equal identities(:tonny_google).id, event.actor_identity_id
  end

  # ---------------------------------------------------------------------------
  # UC-UI-008: GET /repositories/:repository_name/tags/:name/history
  # ---------------------------------------------------------------------------

  test "GET tag history returns 200 and lists all events (happy path)" do
    TagEvent.create!(
      repository: @repo, tag_name: @tag.name, action: "create",
      actor: "alice@example.com", new_digest: "sha256:abc",
      occurred_at: 2.hours.ago
    )
    TagEvent.create!(
      repository: @repo, tag_name: @tag.name, action: "update",
      actor: "bob@example.com", previous_digest: "sha256:abc",
      new_digest: "sha256:def", occurred_at: 1.hour.ago
    )

    get "/repositories/#{@repo.name}/tags/#{@tag.name}/history"

    assert_response :success
    assert_includes response.body, "create"
    assert_includes response.body, "update"
  end

  test "GET tag history orders events by occurred_at DESC" do
    # Use distinct 12-hex-char prefixes per event because the view truncates
    # digests via short_digest (first 12 chars after stripping "sha256:").
    # Each event uses a unique marker as its `new_digest` so we can locate
    # exactly one render position per event in the response body.
    older_marker  = "aaaaaaaaaaaa"
    middle_marker = "bbbbbbbbbbbb"
    newest_marker = "cccccccccccc"

    TagEvent.create!(
      repository: @repo, tag_name: @tag.name, action: "create",
      actor: "first@example.com",
      new_digest: "sha256:#{older_marker}1111",
      occurred_at: 3.days.ago
    )
    TagEvent.create!(
      repository: @repo, tag_name: @tag.name, action: "update",
      actor: "third@example.com",
      new_digest: "sha256:#{newest_marker}3333",
      occurred_at: 1.hour.ago
    )
    TagEvent.create!(
      repository: @repo, tag_name: @tag.name, action: "update",
      actor: "second@example.com",
      new_digest: "sha256:#{middle_marker}2222",
      occurred_at: 1.day.ago
    )

    get "/repositories/#{@repo.name}/tags/#{@tag.name}/history"

    assert_response :success
    positions = [ newest_marker, middle_marker, older_marker ].map { |m| response.body.index(m) }
    assert positions.all?, "expected all digest markers to appear: #{positions.inspect}"
    assert_equal positions.sort, positions,
      "events should render in occurred_at DESC (newest first); got positions #{positions.inspect}"
  end

  test "GET tag history with no events renders empty state gracefully" do
    assert_equal 0, TagEvent.where(repository: @repo, tag_name: @tag.name).count

    get "/repositories/#{@repo.name}/tags/#{@tag.name}/history"

    assert_response :success
    assert_includes response.body, "No history events"
  end

  test "GET tag history for unknown repository returns 404" do
    get "/repositories/no-such-repo/tags/#{@tag.name}/history"
    assert_response :not_found
  end

  test "GET tag history for unknown tag returns 404" do
    get "/repositories/#{@repo.name}/tags/no-such-tag/history"
    assert_response :not_found
  end

  test "GET tag history is accessible when signed out (no auth filter on :history)" do
    TagEvent.create!(
      repository: @repo, tag_name: @tag.name, action: "create",
      actor: "alice@example.com", new_digest: "sha256:abc",
      occurred_at: 1.hour.ago
    )

    # Drop the cookies/session set up by the setup block's sign-in.
    reset!

    get "/repositories/#{@repo.name}/tags/#{@tag.name}/history"

    assert_response :success
    assert_includes response.body, "create"
  end
end
