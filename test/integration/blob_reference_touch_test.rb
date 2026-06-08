require "test_helper"

# G5 — every blob access (HEAD/GET, cross-repo mount, monolithic upload, chunked
# finalize) must bump the blob's updated_at. The orphaned-blob GC keys its grace
# window on updated_at, so touching a blob on access keeps a long-lived but
# briefly-unreferenced blob alive long enough for the in-flight push that is
# about to reference it (closes the upload-vs-GC race).
class BlobReferenceTouchTest < ActionDispatch::IntegrationTest
  def setup
    @storage_dir = Dir.mktmpdir
    @original_storage_path = Rails.configuration.storage_path
    Rails.configuration.storage_path = @storage_dir
    @blob_store = BlobStore.new(@storage_dir)

    @content = SecureRandom.random_bytes(256)
    @digest  = DigestCalculator.compute(@content)
    @blob_store.put(@digest, StringIO.new(@content))

    @auth = basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")
  end

  def teardown
    Rails.configuration.storage_path = @original_storage_path
    FileUtils.rm_rf(@storage_dir)
  end

  def stale_blob(references_count: 0)
    Blob.create!(digest: @digest, size: @content.bytesize,
                 references_count: references_count, updated_at: 2.hours.ago)
  end

  test "HEAD blob bumps the blob's updated_at" do
    repo = Repository.create!(name: "touch-head-#{SecureRandom.hex(4)}", owner_identity: identities(:tonny_google))
    blob = stale_blob

    head "/v2/#{repo.name}/blobs/#{@digest}", headers: @auth
    assert_response :ok

    assert_operator blob.reload.updated_at, :>, 1.minute.ago,
                    "HEAD blob must touch updated_at (GC re-reference grace)"
  end

  test "GET blob bumps the blob's updated_at" do
    repo = Repository.create!(name: "touch-get-#{SecureRandom.hex(4)}", owner_identity: identities(:tonny_google))
    blob = stale_blob

    get "/v2/#{repo.name}/blobs/#{@digest}", headers: @auth
    assert_response :ok

    assert_operator blob.reload.updated_at, :>, 1.minute.ago,
                    "GET blob must touch updated_at (GC re-reference grace)"
  end

  test "cross-repo blob mount bumps the blob's updated_at" do
    source = Repository.create!(name: "touch-src-#{SecureRandom.hex(4)}", owner_identity: identities(:tonny_google))
    blob = stale_blob(references_count: 1)
    manifest = source.manifests.create!(
      digest: "sha256:touch-mount-#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    Layer.create!(manifest: manifest, blob: blob, position: 0)

    dst = "touch-mount-dst-#{SecureRandom.hex(4)}"
    post "/v2/#{dst}/blobs/uploads?mount=#{@digest}&from=#{source.name}", headers: @auth
    assert_response 201

    assert_operator blob.reload.updated_at, :>, 1.minute.ago,
                    "honored mount must touch updated_at (GC re-reference grace)"
  end

  # NOTE: upload finalize (monolithic / chunked complete) is intentionally NOT
  # asserted here. A finalized blob is freshly created (updated_at == now), so
  # the grace window already protects it without an extra touch; and a client
  # never re-finalizes an already-known blob (docker skips upload after a 200
  # HEAD). The race-relevant accesses of a *long-lived* blob are HEAD/GET and
  # cross-repo mount, covered above.
end
