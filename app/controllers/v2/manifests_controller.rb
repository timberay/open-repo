class V2::ManifestsController < V2::BaseController
  SUPPORTED_MEDIA_TYPES = [
    "application/vnd.docker.distribution.manifest.v2+json"
  ].freeze

  def show
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

    response.headers["Docker-Content-Digest"] = manifest.digest
    response.headers["Content-Type"] = manifest.media_type
    response.headers["Content-Length"] = manifest.size.to_s

    if request.head?
      head :ok
    else
      record_pull_event(manifest)
      render json: manifest.payload, content_type: manifest.media_type
    end
  end

  def update
    unless SUPPORTED_MEDIA_TYPES.include?(request.content_type)
      raise Registry::Unsupported,
        "Unsupported manifest media type: #{request.content_type}. " \
        "This registry supports single-platform V2 Schema 2 manifests only. " \
        "Use: docker build --platform linux/amd64 -t <image> ."
    end

    payload = request.raw_post
    manifest = ManifestProcessor.new.call(
      repo_name,
      params[:reference],
      request.content_type,
      payload,
      actor: "anonymous"
    )

    response.headers["Docker-Content-Digest"] = manifest.digest
    response.headers["Location"] = "/v2/#{repo_name}/manifests/#{manifest.digest}"
    head :created
  end

  def destroy
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

    # Decision 1-B: whether reference is a digest or a tag name, if ANY tag
    # connected to this manifest is protected, block the delete.
    manifest.tags.each { |tag| repository.enforce_tag_protection!(tag.name) }

    manifest.tags.each do |tag|
      TagEvent.create!(
        repository: repository,
        tag_name: tag.name,
        action: "delete",
        previous_digest: manifest.digest,
        actor: "anonymous",
        occurred_at: Time.current
      )
    end

    manifest.tags.destroy_all

    manifest.layers.each do |layer|
      layer.blob.decrement!(:references_count)
    end

    manifest.destroy!
    head :accepted
  end

  private

  def find_manifest!(repository, reference)
    if reference.start_with?("sha256:")
      repository.manifests.find_by!(digest: reference)
    else
      tag = repository.tags.find_by!(name: reference)
      tag.manifest
    end
  rescue ActiveRecord::RecordNotFound
    raise Registry::ManifestUnknown, "manifest '#{reference}' not found"
  end

  def record_pull_event(manifest)
    manifest.increment!(:pull_count)
    manifest.update_column(:last_pulled_at, Time.current)

    tag_name = params[:reference].start_with?("sha256:") ? nil : params[:reference]
    PullEvent.create!(
      manifest: manifest,
      repository: manifest.repository,
      tag_name: tag_name,
      user_agent: request.user_agent,
      remote_ip: request.remote_ip,
      occurred_at: Time.current
    )
  end
end
