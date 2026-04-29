require "test_helper"

# UC-V2-002 (catalog), UC-V2-003 (tags list), UC-V2-015 (error response format)
# read-path edge cases that remain 🟡 after Wave 4. Pin current production
# contract — see app/controllers/v2/catalog_controller.rb and
# app/controllers/v2/tags_controller.rb. Companion to the existing
# v2/catalog_controller_test.rb and v2/tags_controller_test.rb (we deliberately
# do NOT duplicate the basic happy-path or the n=2&last=bravo pagination case
# already pinned there).
#
# Contract surprises codified here:
#   - n=0 is NOT a 400. It is clamped to 1 by `.clamp(1, 1000)` on the
#     controller's first line, so the response is a 200 with one item.
#     (UC-V2-002.e2 / UC-V2-003.e4 in TEST_PLAN.md.)
#   - last=<unknown> is NOT a 400. The SQL filter is `name > params[:last]`,
#     so an unknown last reads "everything lexicographically after that string"
#     — typically empty (or a partial tail) without any error code.
#     (UC-V2-002.e4 in TEST_PLAN.md.)
#   - When n exceeds total, the controller returns all rows and NO Link header
#     (the +1 probe row is absent). Pinned below.
class V2::CatalogTagsErrorEdgesTest < ActionDispatch::IntegrationTest
  ERROR_CODES = %w[
    NAME_UNKNOWN
    UNAUTHORIZED
    DENIED
    MANIFEST_INVALID
    DIGEST_INVALID
    UNSUPPORTED
    TOO_MANY_REQUESTS
    BLOB_UNKNOWN
    MANIFEST_UNKNOWN
    BLOB_UPLOAD_UNKNOWN
  ].freeze

  # Asserts the Docker distribution error envelope shape: a JSON body of
  # `{"errors":[{"code": <known>, "message": <string>, "detail": <any>}]}`.
  # `detail` is optional in the rack-attack throttled responder, so we only
  # require it to be present-and-typed when the body actually carries it.
  def assert_error_envelope!(code)
    body = JSON.parse(response.body)
    assert_kind_of Array, body["errors"], "errors must be an array (#{response.body.inspect})"
    refute_empty body["errors"], "errors must be non-empty"
    err = body["errors"].first
    assert_kind_of String, err["code"], "code must be a string"
    assert_includes ERROR_CODES, err["code"], "unknown error code: #{err["code"].inspect}"
    assert_equal code, err["code"]
    assert_kind_of String, err["message"], "message must be a string"
    assert err["message"].present?, "message must be non-empty"
    if err.key?("detail")
      # detail may be a Hash (DENIED w/ tag/policy or insufficient_scope), nil
      # (UNAUTHORIZED), or {} (default branch). Only assert it parses; do not
      # constrain shape further.
      assert(err["detail"].nil? || err["detail"].is_a?(Hash),
        "detail must be nil or Hash, got #{err["detail"].class}")
    end
  end

  # ---------------------------------------------------------------------------
  # UC-V2-002 — catalog pagination edges
  # ---------------------------------------------------------------------------

  setup do
    # Three repos; happy-path n=2&last=bravo is already covered in
    # v2/catalog_controller_test.rb so we DO NOT re-test that here.
    %w[alpha bravo charlie].each do |n|
      Repository.find_or_create_by!(name: n) { |r| r.owner_identity = identities(:tonny_google) }
    end
  end

  test "UC-V2-002.e2 GET /v2/_catalog?n=0 clamps to 1 (not 400) and returns first repo" do
    get "/v2/_catalog?n=0"
    assert_response :ok
    body = JSON.parse(response.body)
    # `.clamp(1, 1000)` floor → exactly one repo, `Link` header for the rest.
    assert_equal 1, body["repositories"].size
    assert_equal "alpha", body["repositories"].first
    assert_includes response.headers["Link"].to_s, "rel=\"next\""
  end

  test "UC-V2-002 GET /v2/_catalog?n exceeds total returns all repos and no Link header" do
    get "/v2/_catalog?n=500"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal %w[alpha bravo charlie], body["repositories"]
    assert_nil response.headers["Link"], "no Link header when result fits in one page"
  end

  test "UC-V2-002.e4 GET /v2/_catalog?last=<beyond-all-repos> returns empty array (not 400)" do
    # 'zzz' > 'charlie' lexicographically, so the SQL `name > 'zzz'` filter
    # returns no rows. Per spec this is a graceful empty page.
    get "/v2/_catalog?last=zzz"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal [], body["repositories"]
    assert_nil response.headers["Link"]
  end

  test "UC-V2-002 GET /v2/_catalog?last=<unknown-mid-string> filters by SQL ordering, not by row existence" do
    # 'bravo' is in the set; 'baz' is not, but it sits lexicographically
    # between 'bravo' and 'charlie'. The current contract treats `last` as a
    # cursor STRING (not a row id), so 'baz' returns 'bravo' onward.
    get "/v2/_catalog?last=baz"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal %w[bravo charlie], body["repositories"]
  end

  test "UC-V2-002.e5 anonymous GET /v2/_catalog with anon pull DISABLED returns 401 + envelope" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/_catalog"
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
    assert_error_envelope!("UNAUTHORIZED")
  ensure
    Rails.configuration.x.registry.anonymous_pull_enabled = true
  end

  test "UC-V2-002 anonymous GET /v2/_catalog with anon pull ENABLED returns 200" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/_catalog"
    assert_response :ok
    assert_equal %w[alpha bravo charlie], JSON.parse(response.body)["repositories"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-003 — tags list pagination + lookup edges
  # ---------------------------------------------------------------------------

  def seed_repo_with_tags!(name, tag_names)
    repo = Repository.find_or_create_by!(name: name) { |r| r.owner_identity = identities(:tonny_google) }
    manifest = repo.manifests.create!(
      digest: "sha256:tags-edges-#{SecureRandom.hex(6)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    tag_names.each { |t| repo.tags.create!(name: t, manifest: manifest) }
    repo
  end

  test "UC-V2-003.e4 GET tags/list?n=0 clamps to 1 (not 400)" do
    repo = seed_repo_with_tags!("tags-edge-n0-#{SecureRandom.hex(3)}", %w[a b c])
    get "/v2/#{repo.name}/tags/list?n=0"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal repo.name, body["name"]
    assert_equal 1, body["tags"].size
    assert_equal "a", body["tags"].first
    assert_includes response.headers["Link"].to_s, "rel=\"next\""
  end

  test "UC-V2-003.e4 GET tags/list?n exceeds tag count returns all tags, no Link header" do
    repo = seed_repo_with_tags!("tags-edge-big-#{SecureRandom.hex(3)}", %w[a b c])
    get "/v2/#{repo.name}/tags/list?n=500"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal %w[a b c], body["tags"]
    assert_nil response.headers["Link"]
  end

  test "UC-V2-003 GET tags/list?last=<beyond-all-tags> returns empty tags array, not 400" do
    repo = seed_repo_with_tags!("tags-edge-last-#{SecureRandom.hex(3)}", %w[a b c])
    get "/v2/#{repo.name}/tags/list?last=zzz"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal repo.name, body["name"]
    assert_equal [], body["tags"]
    assert_nil response.headers["Link"]
  end

  test "UC-V2-003.e1 GET tags/list for unknown repo returns 404 NAME_UNKNOWN envelope" do
    # tags_controller_test.rb pins the 404 status; here we lock the envelope
    # shape + error code (the differentiator from the existing test).
    get "/v2/this-repo-definitely-does-not-exist-#{SecureRandom.hex(4)}/tags/list"
    assert_response :not_found
    assert_error_envelope!("NAME_UNKNOWN")
  end

  test "UC-V2-003.e2 GET tags/list for repo with zero tags returns 200 with empty array" do
    repo = Repository.create!(
      name: "tags-edge-empty-#{SecureRandom.hex(3)}",
      owner_identity: identities(:tonny_google)
    )
    get "/v2/#{repo.name}/tags/list"
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal repo.name, body["name"]
    assert_equal [], body["tags"]
    assert_nil response.headers["Link"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-015 — Error response format (envelope lock-in)
  #
  # For each reachable error code, trigger one integration-level request that
  # surfaces it and assert the {errors: [{code, message, detail}]} envelope.
  # Codes already exercised elsewhere are intentionally re-asserted here so
  # that the schema invariant has a single auditable home.
  # ---------------------------------------------------------------------------

  test "UC-V2-015 NAME_UNKNOWN envelope on tags/list for unknown repo" do
    get "/v2/no-such-repo-#{SecureRandom.hex(4)}/tags/list"
    assert_response :not_found
    assert_error_envelope!("NAME_UNKNOWN")
  end

  test "UC-V2-015 UNAUTHORIZED envelope on POST /v2/<name>/blobs/uploads without creds" do
    post "/v2/some-repo/blobs/uploads"
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
    assert_error_envelope!("UNAUTHORIZED")
  end

  test "UC-V2-015 DENIED envelope on POST blobs/uploads to a repo owned by someone else" do
    repo = Repository.create!(
      name: "v2-015-denied-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    post "/v2/#{repo.name}/blobs/uploads",
         headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response :forbidden
    assert_error_envelope!("DENIED")
    body = JSON.parse(response.body)
    assert_equal repo.name, body.dig("errors", 0, "detail", "repository")
  end

  test "UC-V2-015 MANIFEST_INVALID envelope on PUT manifest with non-v2 schemaVersion" do
    repo_name = "v2-015-manifest-invalid-#{SecureRandom.hex(4)}"
    Repository.create!(name: repo_name, owner_identity: identities(:tonny_google))
    payload = { schemaVersion: 1, mediaType: "application/vnd.docker.distribution.manifest.v2+json",
                config: { digest: "sha256:none", size: 0,
                          mediaType: "application/vnd.docker.container.image.v1+json" },
                layers: [] }.to_json

    put "/v2/#{repo_name}/manifests/v1",
        params: payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    assert_response :bad_request
    assert_error_envelope!("MANIFEST_INVALID")
  end

  test "UC-V2-015 DIGEST_INVALID envelope on PUT blob upload finalize with wrong digest" do
    storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = storage_dir
    repo_name = "v2-015-digest-invalid-#{SecureRandom.hex(4)}"

    post "/v2/#{repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]
    patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
          params: "some bytes",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)
    put "/v2/#{repo_name}/blobs/uploads/#{uuid}?digest=sha256:deadbeef",
        headers: basic_auth_for

    assert_response :bad_request
    assert_error_envelope!("DIGEST_INVALID")
  ensure
    FileUtils.rm_rf(storage_dir) if storage_dir
  end

  test "UC-V2-015 UNSUPPORTED envelope on PUT manifest with non-v2 Content-Type" do
    repo_name = "v2-015-unsupported-#{SecureRandom.hex(4)}"
    Repository.create!(name: repo_name, owner_identity: identities(:tonny_google))
    put "/v2/#{repo_name}/manifests/v1",
        params: "{}",
        headers: { "CONTENT_TYPE" => "application/vnd.oci.image.index.v1+json" }
              .merge(basic_auth_for)
    assert_response :unsupported_media_type
    assert_error_envelope!("UNSUPPORTED")
  end

  test "UC-V2-015 BLOB_UNKNOWN envelope on GET blob with unknown digest in existing repo" do
    storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = storage_dir
    repo = Repository.create!(
      name: "v2-015-blob-unknown-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    get "/v2/#{repo.name}/blobs/sha256:#{"f" * 64}"
    assert_response :not_found
    assert_error_envelope!("BLOB_UNKNOWN")
  ensure
    FileUtils.rm_rf(storage_dir) if storage_dir
  end

  test "UC-V2-015 TOO_MANY_REQUESTS envelope skip — covered in rack_attack_v2_throttle_test.rb" do
    # The throttled-responder is set in config/initializers/rack_attack.rb and
    # already exercised under controlled cache + time conditions in
    # test/integration/rack_attack_v2_throttle_test.rb (POST blobs/uploads
    # 31st request → 429 + {code: "TOO_MANY_REQUESTS"}). Re-triggering it here
    # would require duplicating that file's whole setup (cache reset, time
    # freeze, parallelize(workers: 1)) just to assert the same envelope, which
    # would be a pure duplicate. Skip with a pointer.
    skip "TOO_MANY_REQUESTS envelope pinned in test/integration/rack_attack_v2_throttle_test.rb"
  end

  test "UC-V2-015 every error envelope carries Docker-Distribution-API-Version header (regression)" do
    # set_registry_headers runs as a before_action and is not unwound by
    # rescue_from, but lock it explicitly on a 4xx path so a future refactor
    # cannot strip it silently.
    get "/v2/no-such-repo-header-check-#{SecureRandom.hex(4)}/tags/list"
    assert_response :not_found
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end
end
