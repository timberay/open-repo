require "test_helper"

# UC-V2-007 / UC-V2-008 / UC-V2-010 ~ UC-V2-014 — blob + upload edge cases that
# remained yellow after Wave 4. Source-of-truth specs live in
# docs/qa-audit/TEST_PLAN.md. This file is intentionally separate from the
# existing happy-path controller tests so future audit waves can locate these
# edges by filename.
class V2::BlobUploadEdgesTest < ActionDispatch::IntegrationTest
  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)
    @repo_name  = "edge-repo-#{SecureRandom.hex(3)}"
    Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  # ---------------------------------------------------------------------------
  # UC-V2-007.e3 — blob row in DB, file deleted from disk → 404 BLOB_UNKNOWN.
  # The controller's `BlobStore#exists?` short-circuit returns false, so a
  # missing-FS edge is treated as not-existing rather than a 500.
  # ---------------------------------------------------------------------------
  test "GET blob when DB row exists but file is missing returns 404 BLOB_UNKNOWN" do
    content = "vanishing blob"
    digest = DigestCalculator.compute(content)
    Blob.create!(digest: digest, size: content.bytesize)
    @blob_store.put(digest, StringIO.new(content))
    # Delete the on-disk file but keep the DB row.
    File.delete(@blob_store.path_for(digest))

    get "/v2/#{@repo_name}/blobs/#{digest}"

    assert_response 404
    assert_equal "BLOB_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-008.e1 — blob still referenced by a Manifest's Layer.
  # CONTRACT: V2::BlobsController#destroy does NOT check references_count.
  # The delete succeeds with 202 and orphan-detection is left to a separate
  # job. Pinning current behavior — if this changes, the test should be
  # updated deliberately, not silently.
  # ---------------------------------------------------------------------------
  test "DELETE blob with references_count > 0 still returns 202" do
    repo = Repository.find_by!(name: @repo_name)
    content = "referenced blob"
    digest = DigestCalculator.compute(content)
    blob = Blob.create!(digest: digest, size: content.bytesize, references_count: 1)
    @blob_store.put(digest, StringIO.new(content))

    manifest = repo.manifests.create!(
      digest: "sha256:refcountedge#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    Layer.create!(manifest: manifest, blob: blob, position: 0)

    delete "/v2/#{@repo_name}/blobs/#{digest}", headers: basic_auth_for

    assert_response 202
    assert_nil Blob.find_by(digest: digest)
  end

  # ---------------------------------------------------------------------------
  # UC-V2-008.e5 — blob row exists, references_count = 0, but the on-disk file
  # is already gone. DELETE should still succeed (FileUtils.rm_f is silent on
  # missing files) and the DB row should be destroyed.
  # ---------------------------------------------------------------------------
  test "DELETE blob when file is already missing destroys DB row without raising" do
    content = "ghost blob"
    digest = DigestCalculator.compute(content)
    Blob.create!(digest: digest, size: content.bytesize, references_count: 0)
    # Note: no @blob_store.put — file is missing from the start.

    delete "/v2/#{@repo_name}/blobs/#{digest}", headers: basic_auth_for

    assert_response 202
    assert_nil Blob.find_by(digest: digest)
  end

  # ---------------------------------------------------------------------------
  # UC-V2-010.e1 — monolithic upload where computed digest of body differs
  # from the `?digest=` query param → 400 DIGEST_INVALID.
  # ---------------------------------------------------------------------------
  test "POST monolithic upload with mismatched digest returns 400 DIGEST_INVALID" do
    body = "actual body content"
    wrong_digest = DigestCalculator.compute("a totally different payload")

    post "/v2/#{@repo_name}/blobs/uploads?digest=#{wrong_digest}",
         params: body,
         headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    assert_response 400
    assert_equal "DIGEST_INVALID", JSON.parse(response.body)["errors"][0]["code"]
    # Blob row should NOT be created.
    assert_nil Blob.find_by(digest: wrong_digest)
  end

  # ---------------------------------------------------------------------------
  # UC-V2-011.e1 — mount source blob does not exist in source repo (source repo
  # itself exists, but the digest is unknown). Should fall through to a regular
  # chunked upload session: 202 + Docker-Upload-UUID, NOT 201.
  # NOTE: existing happy-path test covers nonexistent source repo + digest —
  # this case specifically pins behavior when the source repo IS seeded.
  # ---------------------------------------------------------------------------
  test "POST mount with unknown source blob in existing source repo falls back to upload session" do
    Repository.find_or_create_by!(name: "src-#{SecureRandom.hex(3)}") do |r|
      r.owner_identity = identities(:tonny_google)
    end
    source_name = Repository.where("name LIKE 'src-%'").last.name

    post "/v2/#{@repo_name}/blobs/uploads?mount=sha256:abcdef0123456789&from=#{source_name}",
         headers: basic_auth_for

    assert_response 202
    assert response.headers["Docker-Upload-UUID"].present?
    assert_match %r{/v2/#{@repo_name}/blobs/uploads/.+}, response.headers["Location"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-011 cross-repo authz — admin (no membership on tonny's target repo)
  # tries to mount a blob from a repo they CAN read. Authorization on the
  # target repo runs in `ensure_repository!` BEFORE the mount branch, so the
  # request is rejected with 403 DENIED and no mount happens.
  # ---------------------------------------------------------------------------
  test "POST mount across repos by user without write on target returns 403 DENIED" do
    source_repo = Repository.create!(
      name: "mount-src-#{SecureRandom.hex(3)}",
      owner_identity: identities(:admin_google)
    )
    content = "shareable layer"
    digest = DigestCalculator.compute(content)
    Blob.create!(digest: digest, size: content.bytesize, references_count: 1)
    @blob_store.put(digest, StringIO.new(content))

    # Target repo is owned by tonny; admin has no membership → no write.
    post "/v2/#{@repo_name}/blobs/uploads?mount=#{digest}&from=#{source_repo.name}",
         headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")

    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
    # references_count must not be incremented.
    assert_equal 1, Blob.find_by!(digest: digest).references_count
  end

  # ---------------------------------------------------------------------------
  # UC-V2-012 canary — controller does NOT parse / validate the Content-Range
  # header. PATCH currently appends bytes regardless of header syntax.
  # PINNING current behavior: a malformed Content-Range header is silently
  # accepted and the chunk is appended → 202. If a future change adds proper
  # Content-Range validation, this test should be updated deliberately.
  # ---------------------------------------------------------------------------
  test "PATCH chunked upload with malformed Content-Range header is silently accepted" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: "five!",
          headers: {
            "CONTENT_TYPE" => "application/octet-stream",
            "Content-Range" => "0-0" # malformed: claims zero bytes for a 5-byte body
          }.merge(basic_auth_for)

    assert_response 202
    assert_equal "0-4", response.headers["Range"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-012.e1 — PATCH against an unknown UUID → 404 BLOB_UPLOAD_UNKNOWN.
  # ---------------------------------------------------------------------------
  test "PATCH chunked upload against unknown UUID returns 404 BLOB_UPLOAD_UNKNOWN" do
    patch "/v2/#{@repo_name}/blobs/uploads/does-not-exist-#{SecureRandom.hex(4)}",
          params: "data",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    assert_response 404
    assert_equal "BLOB_UPLOAD_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-013.e3 — finalize twice on the same UUID: first 201, second 404
  # (the BlobUpload row was destroyed at end of the successful PUT).
  # ---------------------------------------------------------------------------
  test "PUT finalize called twice on same UUID returns 404 on the second call" do
    content = "finalize-twice payload"
    digest = DigestCalculator.compute(content)

    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: content,
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    put "/v2/#{@repo_name}/blobs/uploads/#{uuid}?digest=#{digest}", headers: basic_auth_for
    assert_response 201

    put "/v2/#{@repo_name}/blobs/uploads/#{uuid}?digest=#{digest}", headers: basic_auth_for
    assert_response 404
    assert_equal "BLOB_UPLOAD_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-013.e4 — finalize without `?digest=` query param.
  # The controller passes nil to `BlobStore#finalize_upload`, which calls
  # `DigestCalculator.verify!(io, nil)` → mismatch → Registry::DigestMismatch
  # → 400 DIGEST_INVALID.
  # ---------------------------------------------------------------------------
  test "PUT finalize without digest query param returns 400 DIGEST_INVALID" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: "some bytes",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    put "/v2/#{@repo_name}/blobs/uploads/#{uuid}", headers: basic_auth_for

    assert_response 400
    assert_equal "DIGEST_INVALID", JSON.parse(response.body)["errors"][0]["code"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-014 idempotency edge — two consecutive DELETEs.
  # CURRENT contract: first 204, second 404 (find_upload! raises after the
  # BlobUpload row was destroyed). NOTE: docs/qa-audit/TEST_PLAN.md UC-V2-014.e1
  # describes the second call as "still 204 (idempotent per discovery)".
  # That is a contract DRIFT vs the implementation. This test pins what the
  # code actually does today — TEST_PLAN should be reconciled.
  # ---------------------------------------------------------------------------
  test "DELETE upload twice returns 204 then 404" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    delete "/v2/#{@repo_name}/blobs/uploads/#{uuid}", headers: basic_auth_for
    assert_response 204

    delete "/v2/#{@repo_name}/blobs/uploads/#{uuid}", headers: basic_auth_for
    assert_response 404
    assert_equal "BLOB_UPLOAD_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]
  end

  # ---------------------------------------------------------------------------
  # UC-V2-014.e3 — DELETE without basic auth → 401 with WWW-Authenticate.
  # Anonymous pull is GET/HEAD only on a fixed allowlist; DELETE on uploads is
  # always authenticated.
  # ---------------------------------------------------------------------------
  test "DELETE upload without basic auth returns 401 with V2 challenge" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    delete "/v2/#{@repo_name}/blobs/uploads/#{uuid}"

    assert_response 401
    assert_match(/Basic realm=/, response.headers["WWW-Authenticate"].to_s)
    # Upload row must still exist — auth gate fired before the destroy ran.
    assert BlobUpload.find_by(uuid: uuid).present?
  end
end
