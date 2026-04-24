require "test_helper"

# UC-V2-016 — verify atomicity of `PUT /v2/:name/manifests/:tag` against
# concurrent races on a protected tag.
#
# The defense lives in `ManifestProcessor#call`, which wraps tag-protection
# enforcement and `manifest.save!` inside `repository.with_lock`. This test
# races two threads at the controller boundary to assert:
#   - same-digest race: both PUTs match the existing baseline digest, so both
#     pass the idempotency carve-out in `Repository#enforce_tag_protection!`.
#     Both succeed (201) and exactly one Manifest row exists for that digest.
#   - different-digest race on protected tag: one PUT matches baseline
#     (idempotent → 201), the other is a fresh digest (protected violation →
#     409 DENIED). The lock + protection check ensures the loser's Manifest
#     is never persisted (no orphan), and the tag remains pinned to baseline.
#
# Threaded tests must not themselves be raced by parallel test workers
# (shared `Rails.configuration.storage_path` mutation), so we pin to one
# worker for this file. Each thread takes its own connection from the pool
# to avoid leaking `ActiveRecord` connections back to the main thread.
#
# Note on protection semantics: `Repository#enforce_tag_protection!` denies
# ALL mutations of a protected tag, including creation, EXCEPT when the new
# digest equals the existing tag's digest (CI retry safety). So to exercise
# the race meaningfully, we seed a baseline tag while the policy is "none"
# and then flip it to a protective policy before racing. This mirrors the
# pattern used in `test/integration/v2_tag_protection_mount_bypass_test.rb`.
class V2TagProtectionAtomicityTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
    @blob_store = BlobStore.new(@storage_dir)

    @repo_name = "atomicity-test-#{SecureRandom.hex(3)}"
    @repository = Repository.create!(
      name: @repo_name,
      owner_identity: identities(:tonny_google),
      tag_protection_policy: "none"
    )
    @protected_tag = "v1.0.0"

    # Seed a baseline manifest while policy is permissive, then flip on the
    # protective policy. After this, only PUTs whose digest equals @baseline_digest
    # are allowed (idempotent overwrite); any other digest must be denied.
    baseline_payload = build_and_seed_payload("baseline-layer-#{SecureRandom.hex(6)}".b)
    @baseline_digest = push_via_processor(baseline_payload)

    @repository.update!(tag_protection_policy: "all_except_latest")

    # Sanity-check the model semantics this test relies on.
    raise "v1.0.0 must be protected under all_except_latest" \
      unless @repository.tag_protected?(@protected_tag)
    raise "idempotent same-digest PUT must be allowed" \
      if begin
           @repository.enforce_tag_protection!(@protected_tag, new_digest: @baseline_digest)
           false
         rescue Registry::TagProtected
           true
         end
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  # ---------------------------------------------------------------------------
  # e1 — two PUTs with the SAME (baseline) digest are idempotent: both 201,
  # ONE Manifest row total for that digest.
  # ---------------------------------------------------------------------------
  test "concurrent same-digest PUTs on a protected tag are idempotent (both 201, one manifest row)" do
    # Re-seed the same baseline payload so its blobs are present (already are).
    same_payload = rebuild_baseline_payload
    same_digest  = DigestCalculator.compute(same_payload)
    assert_equal @baseline_digest, same_digest,
      "test setup invariant: the rebuilt payload must hash to the baseline digest"

    statuses = race_two_puts(payload_a: same_payload, payload_b: same_payload)

    assert_equal [ 201, 201 ], statuses.sort,
      "same-digest race on protected tag must be idempotent (both 201); got #{statuses.inspect}"

    manifest_rows = @repository.manifests.where(digest: same_digest).count
    assert_equal 1, manifest_rows,
      "same-digest race must produce exactly ONE Manifest row; got #{manifest_rows}"

    tag = @repository.tags.find_by!(name: @protected_tag)
    assert_equal same_digest, tag.manifest.digest,
      "tag must point to the (single) baseline manifest"
  end

  # ---------------------------------------------------------------------------
  # e2 — race a baseline-digest PUT (idempotent → 201) against a fresh-digest
  # PUT (protection violation → 409 DENIED). Exactly one of each, no orphans,
  # tag stays pinned to baseline.
  # ---------------------------------------------------------------------------
  test "concurrent different-digest PUTs on a protected tag: one 201, one 409 DENIED, no orphan manifests" do
    idempotent_payload = rebuild_baseline_payload
    fresh_payload      = build_and_seed_payload("fresh-layer-#{SecureRandom.hex(6)}".b)
    idempotent_digest  = DigestCalculator.compute(idempotent_payload)
    fresh_digest       = DigestCalculator.compute(fresh_payload)

    assert_equal @baseline_digest, idempotent_digest, "idempotent payload must hash to baseline"
    refute_equal idempotent_digest, fresh_digest, "test fixture broken: digests must differ"

    manifests_before = @repository.manifests.count

    statuses, bodies = race_two_puts(
      payload_a: idempotent_payload,
      payload_b: fresh_payload,
      capture_bodies: true
    )

    # Exactly one 201 and one 409, regardless of which thread won the lock first.
    assert_equal [ 201, 409 ], statuses.sort,
      "different-digest race on protected tag must yield exactly one 201 and one 409; got #{statuses.inspect}"

    # The fresh-digest side MUST be the loser (it is the only one that can lose
    # under tag protection — the idempotent side is always allowed).
    fresh_index = 1
    assert_equal 409, statuses[fresh_index],
      "the fresh-digest PUT must be the one denied; statuses=#{statuses.inspect}"

    # 409 body must surface DENIED with the protection-policy detail.
    loser_body = JSON.parse(bodies[fresh_index])
    assert_equal "DENIED", loser_body.dig("errors", 0, "code"),
      "loser must surface DENIED; got #{loser_body.inspect}"
    assert_equal "all_except_latest", loser_body.dig("errors", 0, "detail", "policy"),
      "loser DENIED detail must include the protection policy"

    # No orphan manifests: the fresh digest must not have been persisted.
    # Count delta is at most 0 here (idempotent PUT hits an existing row).
    manifests_after = @repository.manifests.count
    delta = manifests_after - manifests_before
    assert delta <= 1,
      "race must not create orphan Manifest rows; delta=#{delta}"

    refute @repository.manifests.exists?(digest: fresh_digest),
      "fresh-digest Manifest row must not exist (would be an orphan write past the protection check)"

    tag = @repository.tags.find_by!(name: @protected_tag)
    assert_equal @baseline_digest, tag.manifest.digest,
      "protected tag must still point to the baseline digest after the race"
    refute_equal fresh_digest, tag.manifest.digest,
      "fresh digest must never have become the tag target"
  end

  private

  # Race two PUTs at the same protected tag using a Mutex+ConditionVariable
  # barrier so both threads enter the controller at (effectively) the same
  # moment. Each thread checks out its own connection from the pool to avoid
  # leaking the integration-session connection across threads.
  #
  # Returns [status_a, status_b] (and optionally [bodies_a, bodies_b]).
  def race_two_puts(payload_a:, payload_b:, capture_bodies: false)
    barrier_mutex = Mutex.new
    barrier_cv    = ConditionVariable.new
    ready_count   = 0
    go            = false

    statuses = Array.new(2)
    bodies   = Array.new(2)

    threads = [ payload_a, payload_b ].each_with_index.map do |payload, idx|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Each thread gets its own Rack session so they don't share cookies
          # or response state with the test's outer integration session.
          session = open_session

          barrier_mutex.synchronize do
            ready_count += 1
            barrier_cv.broadcast if ready_count == 2
            barrier_cv.wait(barrier_mutex) until go
          end

          session.put "/v2/#{@repo_name}/manifests/#{@protected_tag}",
            params: payload,
            headers: {
              "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
            }.merge(basic_auth_for)

          statuses[idx] = session.response.status
          bodies[idx]   = session.response.body if capture_bodies
        end
      end
    end

    # Wait for both threads to reach the barrier, then release them together.
    barrier_mutex.synchronize do
      barrier_cv.wait(barrier_mutex) until ready_count == 2
      go = true
      barrier_cv.broadcast
    end

    threads.each(&:join)

    capture_bodies ? [ statuses, bodies ] : statuses
  end

  # Build a manifest payload and pre-seed its config + layer blobs so the
  # PUT only races on the manifest row / tag, not on blob existence checks.
  def build_and_seed_payload(layer_content)
    config_content = File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
    config_digest  = DigestCalculator.compute(config_content)
    layer_digest   = DigestCalculator.compute(layer_content)

    @blob_store.put(config_digest, StringIO.new(config_content)) unless @blob_store.exists?(config_digest)
    @blob_store.put(layer_digest,  StringIO.new(layer_content))  unless @blob_store.exists?(layer_digest)

    {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: config_digest
      },
      layers: [
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: layer_content.bytesize,
          digest: layer_digest
        }
      ]
    }.to_json
  end

  # Reconstruct the exact baseline payload (so it hashes to @baseline_digest).
  # We cache the layer content from the seed step and re-serialize identically.
  def rebuild_baseline_payload
    @baseline_payload
  end

  # Push a manifest via the service (bypassing the controller) so we can seed
  # state without going through tag-protection (policy is "none" at seed time).
  # Returns the manifest digest.
  def push_via_processor(payload)
    @baseline_payload = payload
    manifest = ManifestProcessor.new(@blob_store).call(
      @repo_name, @protected_tag,
      "application/vnd.docker.distribution.manifest.v2+json",
      payload, actor: "tonny@timberay.com"
    )
    manifest.digest
  end
end
