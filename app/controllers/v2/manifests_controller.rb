class V2::ManifestsController < V2::BaseController
  # Single-platform v2 schema 2 manifests, in either Docker or OCI flavor.
  # Both formats are byte-compatible JSON for our supported subset; we store
  # whichever the client uploaded and return it verbatim on GET, gated by the
  # client's Accept header (Docker Registry V2 spec §manifest-content-type).
  SUPPORTED_MEDIA_TYPES = [
    "application/vnd.docker.distribution.manifest.v2+json",
    "application/vnd.oci.image.manifest.v1+json"
  ].freeze

  before_action :set_repository_for_authz, only: [ :update, :destroy ]

  def show
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

    unless accept_includes?(manifest.media_type)
      head :not_acceptable
      return
    end

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
        "This registry supports single-platform V2 Schema 2 (Docker or OCI) manifests only. " \
        "Use: docker build --platform linux/amd64 -t <image> ."
    end

    payload = request.raw_post
    manifest = ManifestProcessor.new.call(
      repo_name,
      params[:reference],
      request.content_type,
      payload,
      actor: current_user.email
    )

    response.headers["Docker-Content-Digest"] = manifest.digest
    response.headers["Location"] = "/v2/#{repo_name}/manifests/#{manifest.digest}"
    head :created
  end

  def destroy
    manifest = find_manifest!(@repository, params[:reference])

    manifest.tags.each { |tag| @repository.enforce_tag_protection!(tag.name) }

    manifest.tags.each do |tag|
      TagEvent.create!(
        repository: @repository,
        tag_name: tag.name,
        action: "delete",
        previous_digest: manifest.digest,
        actor: current_user.email,
        actor_identity_id: current_user.primary_identity_id,
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

  def set_repository_for_authz
    @repository = find_repository!
    case action_name
    when "update"  then authorize_for!(:write)
    when "destroy" then authorize_for!(:delete)
    end
  end

  # True when the client's Accept header is empty/wildcard or explicitly lists
  # the stored manifest media type. Quality (q=) parameters and parameters on
  # the wildcard (e.g. "*/*; q=0.5") are tolerated. We do NOT transcode between
  # Docker and OCI manifest formats, so a client that asks ONLY for the format
  # we did not store gets a 406.
  def accept_includes?(media_type)
    accept = request.headers["Accept"].to_s
    return true if accept.blank?

    accept.split(",").any? do |entry|
      token = entry.split(";").first.to_s.strip
      token == media_type || token == "*/*" || token == "application/*"
    end
  end

  def find_manifest!(repository, reference)
    if reference.include?(":")
      validate_digest!(reference)
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
