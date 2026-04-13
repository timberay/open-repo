class V2::BlobsController < V2::BaseController
  def show
    find_repository!
    blob = Blob.find_by!(digest: params[:digest])
    blob_store = BlobStore.new

    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found" unless blob_store.exists?(params[:digest])

    response.headers['Docker-Content-Digest'] = blob.digest
    response.headers['Content-Length'] = blob.size.to_s
    response.headers['Content-Type'] = blob.content_type || 'application/octet-stream'

    if request.head?
      head :ok
    else
      send_file blob_store.path_for(blob.digest), type: 'application/octet-stream', disposition: 'inline'
    end
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found"
  end

  def destroy
    find_repository!
    blob = Blob.find_by!(digest: params[:digest])
    BlobStore.new.delete(blob.digest)
    blob.destroy!
    head :accepted
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found"
  end
end
