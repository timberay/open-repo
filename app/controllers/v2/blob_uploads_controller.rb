class V2::BlobUploadsController < V2::BaseController
  def create
    ensure_repository!

    if params[:mount].present? && params[:from].present?
      handle_blob_mount
    elsif params[:digest].present?
      handle_monolithic_upload
    else
      handle_start_upload
    end
  end

  def show
    @repository = find_repository!
    upload = find_upload!
    bytes_received = upload.byte_offset.to_i

    # Per V2 spec: Range header is inclusive of the last byte received.
    # When zero bytes have been written, the canonical "no progress" value is "0-0".
    range_end = bytes_received.positive? ? bytes_received - 1 : 0

    response.headers["Location"] = upload_url(upload)
    response.headers["Docker-Upload-UUID"] = upload.uuid
    response.headers["Range"] = "0-#{range_end}"
    head :no_content
  end

  def update
    authorize_write!
    upload = find_upload!
    validate_content_range!(upload)
    blob_store.append_upload(upload.uuid, request.body)
    upload.update!(byte_offset: blob_store.upload_size(upload.uuid))

    response.headers["Location"] = upload_url(upload)
    response.headers["Docker-Upload-UUID"] = upload.uuid
    response.headers["Range"] = "0-#{upload.byte_offset - 1}"
    head :accepted
  end

  def complete
    authorize_write!
    upload = find_upload!
    digest = params[:digest]

    if request.body.size > 0
      blob_store.append_upload(upload.uuid, request.body)
    end

    blob_store.finalize_upload(upload.uuid, digest)

    Blob.create_or_find_by!(digest: digest) do |b|
      b.size = blob_store.size(digest)
      b.content_type = "application/octet-stream"
    end

    upload.destroy!

    response.headers["Docker-Content-Digest"] = digest
    response.headers["Location"] = "/v2/#{repo_name}/blobs/#{digest}"
    head :created
  end

  def destroy
    authorize_write!
    upload = find_upload!
    blob_store.cancel_upload(upload.uuid)
    upload.destroy!
    head :no_content
  end

  private

  # First-pusher-owner pattern (tech design D2).
  # If the repository does not exist, the authenticated user becomes owner.
  # If it exists, write permission is checked.
  # Handles the SQLite unique-constraint race: the losing racer hits
  # RecordNotUnique, reloads the now-existing repo, and must run the SAME write
  # authz as the happy path — otherwise the loser could start an upload on a
  # repository they have no write access to.
  def ensure_repository!
    identity_id = current_user.primary_identity_id
    @repository = Repository.find_or_create_by!(name: repo_name) do |r|
      r.owner_identity_id = identity_id
    end
    # Existing repo: verify write access
    authorize_for!(:write) unless @repository.owner_identity_id == identity_id
  rescue ActiveRecord::RecordNotUnique
    # Race-loss path: reload and re-check write authz (no bypass).
    @repository = Repository.find_by!(name: repo_name)
    authorize_for!(:write) unless @repository.owner_identity_id == identity_id
  end

  # Resolves the existing repository from the request path and enforces write
  # access, mirroring the authz that `create` performs via ensure_repository!.
  def authorize_write!
    @repository = find_repository!
    authorize_for!(:write)
  end

  # Scopes the upload lookup to @repository so a UUID minted under one repo
  # cannot be driven under another repo's path.
  def find_upload!
    @repository.blob_uploads.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUploadUnknown, "upload '#{params[:uuid]}' not found"
  end

  def handle_start_upload
    uuid = SecureRandom.uuid
    blob_store.create_upload(uuid)
    upload = @repository.blob_uploads.create!(uuid: uuid)

    response.headers["Location"] = upload_url(upload)
    response.headers["Docker-Upload-UUID"] = uuid
    response.headers["Range"] = "0-0"
    head :accepted
  end

  def handle_monolithic_upload
    digest = params[:digest]
    uuid = SecureRandom.uuid
    blob_store.create_upload(uuid)
    blob_store.append_upload(uuid, request.body)
    blob_store.finalize_upload(uuid, digest)

    Blob.create_or_find_by!(digest: digest) do |b|
      b.size = blob_store.size(digest)
      b.content_type = "application/octet-stream"
    end

    response.headers["Docker-Content-Digest"] = digest
    response.headers["Location"] = "/v2/#{repo_name}/blobs/#{digest}"
    head :created
  end

  def handle_blob_mount
    source = Repository.find_by(name: params[:from])
    blob = Blob.find_by(digest: params[:mount])

    # Per V2 spec, only honor the mount when the named source repository
    # actually references the blob (manifest -> layer -> blob) and the content
    # is on disk. Otherwise gracefully fall back to a normal upload session.
    # (Stage 3 will additionally enforce :read authz on the source repo here.)
    if source && blob && blob_store.exists?(params[:mount]) && source_references_blob?(source, blob)
      blob.increment!(:references_count)

      response.headers["Docker-Content-Digest"] = params[:mount]
      response.headers["Location"] = "/v2/#{repo_name}/blobs/#{params[:mount]}"
      head :created
    else
      handle_start_upload
    end
  end

  def source_references_blob?(source, blob)
    source.manifests.joins(:layers).exists?(layers: { blob_id: blob.id })
  end

  # When a chunked PATCH carries a Content-Range header, validate it against the
  # current upload offset and the declared body length (Content-Length). A
  # mismatch means an out-of-order or inconsistent chunk that would silently
  # corrupt the blob, so reject with 416 before appending anything. A PATCH with
  # no Content-Range (single streamed chunk) keeps the existing append behavior.
  def validate_content_range!(upload)
    range = request.headers["Content-Range"]
    return if range.blank?

    match = range.match(/\A(\d+)-(\d+)\z/)
    raise Registry::RangeNotSatisfiable, "malformed Content-Range '#{range}'" unless match

    start_offset = match[1].to_i
    end_offset   = match[2].to_i
    chunk_length = end_offset - start_offset + 1
    declared_length = request.content_length

    if start_offset != upload.byte_offset.to_i
      raise Registry::RangeNotSatisfiable,
            "Content-Range start #{start_offset} does not match upload offset #{upload.byte_offset}"
    end

    if declared_length && chunk_length != declared_length
      raise Registry::RangeNotSatisfiable,
            "Content-Range '#{range}' length #{chunk_length} does not match body size #{declared_length}"
    end
  end

  def upload_url(upload)
    "/v2/#{repo_name}/blobs/uploads/#{upload.uuid}"
  end

  def blob_store
    @blob_store ||= BlobStore.new
  end
end
