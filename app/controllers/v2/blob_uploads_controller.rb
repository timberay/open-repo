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

  def update
    upload = find_upload!
    blob_store.append_upload(upload.uuid, request.body)
    upload.update!(byte_offset: blob_store.upload_size(upload.uuid))

    response.headers['Location'] = upload_url(upload)
    response.headers['Docker-Upload-UUID'] = upload.uuid
    response.headers['Range'] = "0-#{upload.byte_offset - 1}"
    head :accepted
  end

  def complete
    upload = find_upload!
    digest = params[:digest]

    if request.body.size > 0
      blob_store.append_upload(upload.uuid, request.body)
    end

    blob_store.finalize_upload(upload.uuid, digest)

    Blob.create_or_find_by!(digest: digest) do |b|
      b.size = blob_store.size(digest)
      b.content_type = 'application/octet-stream'
    end

    upload.destroy!

    response.headers['Docker-Content-Digest'] = digest
    response.headers['Location'] = "/v2/#{repo_name}/blobs/#{digest}"
    head :created
  end

  def destroy
    upload = find_upload!
    blob_store.cancel_upload(upload.uuid)
    upload.destroy!
    head :no_content
  end

  private

  def ensure_repository!
    @repository = Repository.find_or_create_by!(name: repo_name)
  end

  def find_upload!
    BlobUpload.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUploadUnknown, "upload '#{params[:uuid]}' not found"
  end

  def handle_start_upload
    uuid = SecureRandom.uuid
    blob_store.create_upload(uuid)
    upload = @repository.blob_uploads.create!(uuid: uuid)

    response.headers['Location'] = upload_url(upload)
    response.headers['Docker-Upload-UUID'] = uuid
    response.headers['Range'] = '0-0'
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
      b.content_type = 'application/octet-stream'
    end

    response.headers['Docker-Content-Digest'] = digest
    response.headers['Location'] = "/v2/#{repo_name}/blobs/#{digest}"
    head :created
  end

  def handle_blob_mount
    blob = Blob.find_by(digest: params[:mount])

    if blob && blob_store.exists?(params[:mount])
      ensure_repository!
      blob.increment!(:references_count)

      response.headers['Docker-Content-Digest'] = params[:mount]
      response.headers['Location'] = "/v2/#{repo_name}/blobs/#{params[:mount]}"
      head :created
    else
      handle_start_upload
    end
  end

  def upload_url(upload)
    "/v2/#{repo_name}/blobs/uploads/#{upload.uuid}"
  end

  def blob_store
    @blob_store ||= BlobStore.new
  end
end
