require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @repo = Repository.create!(name: "example")
    @manifest = @repo.manifests.create!(
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    @tag = @repo.tags.create!(name: "v1.0.0", manifest: @manifest)
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
    repo = Repository.create!(name: "web-actor-test-repo")
    manifest = repo.manifests.create!(
      digest: "sha256:web-actor-#{SecureRandom.hex(4)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    tag = repo.tags.create!(name: "web-v1", manifest: manifest)

    post "/testing/sign_in", params: { user_id: users(:tonny).id }

    assert_difference -> { TagEvent.where(actor: "tonny@timberay.com", action: "delete").count }, +1 do
      delete "/repositories/#{repo.name}/tags/#{tag.name}"
    end
  end

  test "unsigned destroy falls back to actor: 'anonymous'" do
    repo = Repository.create!(name: "web-actor-anon-repo")
    manifest = repo.manifests.create!(
      digest: "sha256:web-actor-anon-#{SecureRandom.hex(4)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    tag = repo.tags.create!(name: "web-anon-v1", manifest: manifest)

    assert_difference -> { TagEvent.where(actor: "anonymous", action: "delete").count }, +1 do
      delete "/repositories/#{repo.name}/tags/#{tag.name}"
    end
  end
end
