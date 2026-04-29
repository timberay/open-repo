require "test_helper"

# UC-V2-005 — manifest push edge cases (.e11–.e16) called out in
# docs/qa-audit/TEST_PLAN.md and docs/qa-audit/QA_REPORT.md.
#
# Kept in a SEPARATE file from manifests_controller_test.rb so future audit
# waves can locate these edges by filename. Mirrors the canonical setup of
# manifests_controller_test.rb (blob_store + repo + config + layer seeding).
class V2::ManifestPushEdgesTest < ActionDispatch::IntegrationTest
  # The .e11 race must not itself be raced by parallel workers.
  parallelize(workers: 1)

  MEDIA_TYPE = "application/vnd.docker.distribution.manifest.v2+json".freeze

  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)
    @repo_name  = "edges-repo-#{SecureRandom.hex(3)}"
    @repo       = Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))

    @config_digest = DigestCalculator.compute(config_content)
    @blob_store.put(@config_digest, StringIO.new(config_content))
    Blob.find_or_create_by!(digest: @config_digest) { |b| b.size = config_content.bytesize }

    @layer_content = SecureRandom.random_bytes(1024)
    @layer_digest  = DigestCalculator.compute(@layer_content)
    @blob_store.put(@layer_digest, StringIO.new(@layer_content))
    Blob.find_or_create_by!(digest: @layer_digest) { |b| b.size = @layer_content.bytesize }
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  # Build a minimal valid v2 manifest JSON referencing @config_digest and
  # the supplied layer digest/size.
  def build_manifest_payload(layer_digest:, layer_size:)
    {
      schemaVersion: 2,
      mediaType: MEDIA_TYPE,
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: @config_digest
      },
      layers: [
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: layer_size,
          digest: layer_digest
        }
      ]
    }.to_json
  end

  def write_blob(content)
    digest = DigestCalculator.compute(content)
    @blob_store.put(digest, StringIO.new(content))
    Blob.find_or_create_by!(digest: digest) { |b| b.size = content.bytesize }
    digest
  end

  # ---------------------------------------------------------------------------
  # e11 — concurrent push to same protected tag with different digests.
  #
  # Setup intentionally pre-seeds v1.0.0 → seed_digest, then enables
  # all_except_latest protection. One thread re-pushes the SAME digest
  # (idempotent path → 201 per Repository#enforce_tag_protection!), the
  # other pushes a DIFFERENT digest (→ 409 DENIED TagProtected). The two
  # threads use different layer digests (the criterion the plan asks us to
  # observe). Repository#with_lock in ManifestProcessor#call serializes
  # the two threads, so the surviving tag must still point at seed_digest
  # and only ONE new manifest row may have been created (the
  # idempotent-winner row already existed; the loser cannot create one).
  # ---------------------------------------------------------------------------
  test "e11 concurrent push to protected tag with different digests yields one 201 and one 409 DENIED" do
    # 1. Pre-seed v1.0.0 with the SAME content the "winner" thread will push.
    seed_payload = build_manifest_payload(layer_digest: @layer_digest, layer_size: @layer_content.bytesize)
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: seed_payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)
    assert_response :created
    seed_manifest_digest = response.headers["Docker-Content-Digest"]
    assert_match(/\Asha256:/, seed_manifest_digest)

    # 2. Turn on protection so v1.0.0 is now protected.
    @repo.update!(tag_protection_policy: "all_except_latest")

    # 3. Build a DIFFERENT layer + manifest for the loser thread.
    other_layer_content = SecureRandom.random_bytes(1024)
    other_layer_digest  = write_blob(other_layer_content)
    other_payload       = build_manifest_payload(
      layer_digest: other_layer_digest, layer_size: other_layer_content.bytesize
    )

    # Sanity: payloads (and therefore manifest digests) MUST differ.
    refute_equal seed_payload, other_payload
    refute_equal @layer_digest, other_layer_digest

    pre_count = Manifest.count

    # 4. Align both threads on a starting line with Mutex + ConditionVariable
    #    so they hit the controller as close to simultaneously as possible.
    mutex   = Mutex.new
    cond    = ConditionVariable.new
    started = 0
    results = {}

    runner = lambda do |label, payload|
      ActiveRecord::Base.connection_pool.with_connection do
        # Each thread needs its own integration session so headers don't collide.
        session = open_session
        mutex.synchronize do
          started += 1
          if started < 2
            cond.wait(mutex)
          else
            cond.broadcast
          end
        end
        session.put "/v2/#{@repo_name}/manifests/v1.0.0",
                    params: payload,
                    headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)
        results[label] = {
          status: session.response.status,
          body:   session.response.body,
          digest: session.response.headers["Docker-Content-Digest"]
        }
      end
    end

    t_winner = Thread.new { runner.call(:winner, seed_payload) }
    t_loser  = Thread.new { runner.call(:loser, other_payload) }
    [ t_winner, t_loser ].each(&:join)

    statuses = results.values.map { |r| r[:status] }.sort
    assert_equal [ 201, 409 ], statuses,
      "expected exactly one 201 and one 409, got #{statuses.inspect} — bodies: #{results.inspect}"

    loser_result = results.values.find { |r| r[:status] == 409 }
    body = JSON.parse(loser_result[:body])
    assert_equal "DENIED", body.dig("errors", 0, "code")

    # Post-conditions:
    # - exactly ONE manifest row was created across both pushes (the loser's
    #   never persisted because enforce_tag_protection! short-circuits before
    #   manifest.save!), and the idempotent winner re-uses the seed row.
    assert_equal 0, Manifest.count - pre_count,
      "no NEW manifest row should be created; idempotent winner reuses seed and loser is rejected"

    # - surviving tag still points at the winning (seed) digest.
    surviving_tag = @repo.reload.tags.find_by!(name: "v1.0.0")
    assert_equal seed_manifest_digest, surviving_tag.manifest.digest
  end

  # ---------------------------------------------------------------------------
  # e12 — empty layers array. Per spec this is valid (rare, but allowed).
  # ---------------------------------------------------------------------------
  test "e12 empty layers array creates manifest with zero Layer rows" do
    payload = {
      schemaVersion: 2,
      mediaType: MEDIA_TYPE,
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: @config_digest
      },
      layers: []
    }.to_json

    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)

    assert_response :created
    digest = response.headers["Docker-Content-Digest"]
    manifest = Manifest.find_by!(digest: digest)
    assert_equal 0, manifest.layers.count
  end

  # ---------------------------------------------------------------------------
  # e13 — manifest body missing the "config" key entirely.
  # ---------------------------------------------------------------------------
  test "e13 missing config field returns 400 MANIFEST_INVALID" do
    payload = {
      schemaVersion: 2,
      mediaType: MEDIA_TYPE,
      layers: []
    }.to_json

    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "MANIFEST_INVALID", body.dig("errors", 0, "code")
  end

  # ---------------------------------------------------------------------------
  # e14 — config blob body is non-JSON. ManifestProcessor#extract_config
  # rescues JSON::ParserError and returns architecture/os = nil, so the push
  # still succeeds with 201.
  # ---------------------------------------------------------------------------
  test "e14 malformed config JSON in blob falls back to nil arch/os and still returns 201" do
    bad_config_content = "not-json"
    bad_config_digest  = write_blob(bad_config_content)

    layer_content = SecureRandom.random_bytes(256)
    layer_digest  = write_blob(layer_content)

    payload = {
      schemaVersion: 2,
      mediaType: MEDIA_TYPE,
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: bad_config_content.bytesize,
        digest: bad_config_digest
      },
      layers: [
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: layer_content.bytesize,
          digest: layer_digest
        }
      ]
    }.to_json

    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)

    assert_response :created
    digest = response.headers["Docker-Content-Digest"]
    manifest = Manifest.find_by!(digest: digest)
    assert_nil manifest.architecture
    assert_nil manifest.os
  end

  # ---------------------------------------------------------------------------
  # e15 — namespaced repo "org/team/app". Per docs/qa-audit/TEST_PLAN.md the
  # name is org/team/app, but the V2 routes (config/routes.rb) only define
  # one and two-segment forms (:name, :ns/:name). Three-segment names are
  # rejected by the route constraint, so we use the supported two-segment
  # form (org/app) which is the most-namespacing the registry actually
  # supports today. This still exercises the namespaced-repo code path
  # (Repository.find_by(name: "org/app"), repo_name composition with :ns).
  # ---------------------------------------------------------------------------
  test "e15 namespaced repo manifest push succeeds" do
    namespaced_name = "org/app-#{SecureRandom.hex(3)}"
    Repository.create!(name: namespaced_name, owner_identity: identities(:tonny_google))

    payload = build_manifest_payload(layer_digest: @layer_digest, layer_size: @layer_content.bytesize)

    put "/v2/#{namespaced_name}/manifests/v1.0.0",
        params: payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)

    assert_response :created
    repo = Repository.find_by(name: namespaced_name)
    assert_not_nil repo, "namespaced repository should exist after push"
    assert repo.tags.exists?(name: "v1.0.0"), "v1.0.0 tag should be present on namespaced repo"
  end

  # ---------------------------------------------------------------------------
  # e15 invariant — two-segment namespace (`org/repo`) is the supported maximum
  # by deliberate design (operator-confirmed: this is an internal single-tenant
  # registry, not GCR/Harbor with project hierarchies). config/routes.rb only
  # defines `:name` and `:ns/:name` scopes. Three-segment paths like
  # `org/team/app` MUST be rejected at the router (404), not silently routed
  # to a V2 controller. If this test ever fails, someone added a multi-segment
  # route — verify intent before letting it land.
  # ---------------------------------------------------------------------------
  test "e15 invariant — three-segment paths return 404 at the router (no V2 routing)" do
    %w[manifests/v1 blobs/sha256:abc tags/list blobs/uploads].each do |suffix|
      get "/v2/org/team/app/#{suffix}", headers: basic_auth_for
      assert_response :not_found,
        "GET /v2/org/team/app/#{suffix} should be rejected by the router (got #{response.status})"
    end

    put "/v2/org/team/app/manifests/v1.0.0",
        params: build_manifest_payload(layer_digest: @layer_digest, layer_size: @layer_content.bytesize),
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)
    assert_response :not_found,
      "PUT /v2/org/team/app/manifests/v1.0.0 should be rejected by the router (got #{response.status})"
  end

  # ---------------------------------------------------------------------------
  # E-26 — custom_regex tag protection enforced at the PUT manifest endpoint.
  # Model-level coverage exists (test/models/repository_test.rb), but the
  # controller path (rescue_from Registry::TagProtected → 409 DENIED) needs
  # an integration assertion. We seed a baseline `release-2025` tag while the
  # policy is permissive, flip on `custom_regex` with pattern `^release-.*`,
  # then exercise both paths:
  #   * matching tag (different digest)  → 409 DENIED with TAG_PROTECTED detail
  #   * non-matching tag (`dev-feature`) → 201 Created
  # Also asserts the protected tag's digest mapping is unchanged after the
  # rejected push (no orphan write past the protection check).
  # ---------------------------------------------------------------------------
  test "E-26 custom_regex tag protection denies matching push and allows non-matching push" do
    protected_tag     = "release-2025"
    non_matching_tag  = "dev-feature"

    # 1. Seed `release-2025` while protection is off so we have a baseline
    #    digest that subsequent (different-digest) pushes can fail against.
    seed_payload = build_manifest_payload(layer_digest: @layer_digest, layer_size: @layer_content.bytesize)
    put "/v2/#{@repo_name}/manifests/#{protected_tag}",
        params: seed_payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)
    assert_response :created
    baseline_digest = response.headers["Docker-Content-Digest"]
    assert_match(/\Asha256:/, baseline_digest)

    # 2. Turn on custom_regex protection — anything matching `^release-.*`
    #    is now frozen (idempotent same-digest still allowed by the model).
    @repo.update!(tag_protection_policy: "custom_regex", tag_protection_pattern: "^release-.*")
    assert @repo.reload.tag_protected?(protected_tag)
    refute @repo.tag_protected?(non_matching_tag)

    # 3. Build a DIFFERENT digest payload and try to overwrite `release-2025`.
    other_layer = SecureRandom.random_bytes(2048)
    other_digest = write_blob(other_layer)
    new_payload = build_manifest_payload(layer_digest: other_digest, layer_size: other_layer.bytesize)
    refute_equal seed_payload, new_payload

    pre_count = Manifest.count

    put "/v2/#{@repo_name}/manifests/#{protected_tag}",
        params: new_payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "DENIED", body.dig("errors", 0, "code")
    assert_equal protected_tag, body.dig("errors", 0, "detail", "tag")
    assert_equal "custom_regex", body.dig("errors", 0, "detail", "policy")

    # No orphan manifest row was created past the protection check.
    assert_equal 0, Manifest.count - pre_count

    # Protected tag still maps to the baseline digest (atomicity).
    surviving_tag = @repo.tags.find_by!(name: protected_tag)
    assert_equal baseline_digest, surviving_tag.manifest.digest

    # 4. A push to a non-matching tag must succeed (policy is regex-scoped,
    #    not a blanket freeze).
    put "/v2/#{@repo_name}/manifests/#{non_matching_tag}",
        params: new_payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)
    assert_response :created
    new_tag_digest = response.headers["Docker-Content-Digest"]
    assert_match(/\Asha256:/, new_tag_digest)
    refute_equal baseline_digest, new_tag_digest

    assert @repo.tags.exists?(name: non_matching_tag)
  end

  # ---------------------------------------------------------------------------
  # e16 — schemaVersion: 1 in body, valid v2 Content-Type. The schema check
  # in ManifestProcessor runs BEFORE the controller's Content-Type gate would
  # reject anything (and Content-Type is the supported v2 type anyway), so
  # the response is 400 MANIFEST_INVALID with "unsupported schema version",
  # NOT 415 UNSUPPORTED.
  # ---------------------------------------------------------------------------
  test "e16 schemaVersion 1 in body with v2 Content-Type returns 400 MANIFEST_INVALID before content-type rejection" do
    payload = {
      schemaVersion: 1,
      mediaType: MEDIA_TYPE,
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: @config_digest
      },
      layers: []
    }.to_json

    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: payload,
        headers: { "CONTENT_TYPE" => MEDIA_TYPE }.merge(basic_auth_for)

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "MANIFEST_INVALID", body.dig("errors", 0, "code")
    assert_match(/unsupported schema version/i, body.dig("errors", 0, "message"))
  end
end
