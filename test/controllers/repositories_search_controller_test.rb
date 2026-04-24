require "test_helper"

class RepositoriesSearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    repo = Repository.create!(name: "searchable-repo", description: "findable", owner_identity: identities(:tonny_google))
    manifest = Manifest.create!(repository: repo, digest: "sha256:xyz", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 100)
    Tag.create!(repository: repo, manifest: manifest, name: "v1.0.0")
  end

  test "GET /repositories as turbo_stream returns turbo_stream matching index.html.erb palette and structure" do
    get repositories_path, as: :turbo_stream
    assert_response :success
    assert_no_match(/gray-/, response.body)
    assert_no_match(/stroke-width="2"/, response.body)
    assert_includes response.body, "slate-"
  end

  test "GET /repositories as turbo_stream renders card grid when repositories exist" do
    get repositories_path, as: :turbo_stream
    assert_includes response.body, "searchable-repo"
    assert_includes response.body, "grid"
  end

  test "GET /repositories as turbo_stream renders empty state when no results match query" do
    get repositories_path(q: "zzzznonexistentzzzz"), as: :turbo_stream
    assert_includes response.body, "No results found"
    assert_no_match(/gray-/, response.body)
  end
end
