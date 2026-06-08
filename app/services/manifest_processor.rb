class ManifestProcessor
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(repo_name, reference, content_type, payload, actor:, owner_identity: nil)
    parsed = parse_manifest!(payload)
    validate_schema!(parsed)

    config_digest = parsed["config"]["digest"]
    raise Registry::ManifestInvalid, "config blob not found" unless @blob_store.exists?(config_digest)

    layer_digests = parsed["layers"].map { |l| l["digest"] }
    layer_digests.each do |d|
      raise Registry::ManifestInvalid, "layer blob not found: #{d}" unless @blob_store.exists?(d)
    end

    # First-pusher-owner: a repository created here is owned by the caller's
    # identity (the authenticated pusher), never an admin. The controller
    # normally creates the repo before reaching this point, so this branch is a
    # fallback for direct service callers; owner_identity must be present then.
    repository = Repository.find_or_create_by!(name: repo_name) do |r|
      r.owner_identity = owner_identity
    end
    digest = DigestCalculator.compute(payload)

    tag_name = reference if reference.present? && !reference.start_with?("sha256:")

    # Decision 1-A + OV-1: enforce tag protection at the ENTRY of the service,
    # inside a row-lock on the repository, BEFORE any manifest.save! or blob
    # references_count increments. This prevents orphan manifest rows,
    # leaked blob refs, and concurrent-push races on the same tag.
    repository.with_lock do
      if tag_name
        existing_tag = repository.tags.find_by(name: tag_name)
        repository.enforce_tag_protection!(tag_name, new_digest: digest, existing_tag: existing_tag)
      end

      manifest = repository.manifests.find_or_initialize_by(digest: digest)
      config_data = extract_config(config_digest)

      manifest.assign_attributes(
        media_type: content_type,
        payload: payload,
        size: payload.bytesize,
        config_digest: config_digest,
        architecture: config_data[:architecture],
        os: config_data[:os],
        docker_config: config_data[:config_json]
      )
      manifest.save!

      create_layers!(manifest, parsed["layers"])

      assign_tag!(repository, tag_name, manifest, actor: actor) if tag_name

      update_repository_size!(repository)

      manifest
    end
  end

  private

  # Map a non-JSON manifest body to a spec-shaped MANIFEST_INVALID (400) instead
  # of letting JSON::ParserError bubble up as a 500. (extract_config has its own
  # rescue for the config blob's JSON, so this only guards the manifest body.)
  def parse_manifest!(payload)
    JSON.parse(payload)
  rescue JSON::ParserError
    raise Registry::ManifestInvalid, "manifest is not valid JSON"
  end

  def validate_schema!(parsed)
    unless parsed["schemaVersion"] == 2
      raise Registry::ManifestInvalid, "unsupported schema version"
    end

    unless parsed["config"].is_a?(Hash) && parsed["config"]["digest"].present?
      raise Registry::ManifestInvalid, "missing config"
    end

    unless parsed["layers"].is_a?(Array)
      raise Registry::ManifestInvalid, "missing layers"
    end
  end

  def extract_config(config_digest)
    config_io = @blob_store.get(config_digest)
    config_json = config_io.read
    config_io.close
    parsed = JSON.parse(config_json)

    {
      architecture: parsed["architecture"],
      os: parsed["os"],
      config_json: (parsed["config"] || {}).to_json
    }
  rescue JSON::ParserError
    { architecture: nil, os: nil, config_json: nil }
  end

  def create_layers!(manifest, layers_data)
    # Release the references held by the manifest's current layers before
    # rebuilding them, so re-pushing the same manifest does not leak +1 per
    # layer. Runs inside the caller's repository.with_lock, so it is atomic.
    manifest.layers.includes(:blob).each { |layer| layer.blob.decrement!(:references_count) }
    manifest.layers.destroy_all

    layers_data.each_with_index do |layer_data, index|
      blob = Blob.find_or_create_by!(digest: layer_data["digest"]) do |b|
        b.size = layer_data["size"]
        b.content_type = layer_data["mediaType"]
      end
      blob.increment!(:references_count)

      Layer.create!(manifest: manifest, blob: blob, position: index)
    end
  end

  def assign_tag!(repository, tag_name, manifest, actor:)
    existing_tag = repository.tags.find_by(name: tag_name)

    if existing_tag
      old_digest = existing_tag.manifest.digest
      if old_digest != manifest.digest
        existing_tag.update!(manifest: manifest)
        TagEvent.create!(
          repository: repository,
          tag_name: tag_name,
          action: "update",
          previous_digest: old_digest,
          new_digest: manifest.digest,
          actor: actor,
          occurred_at: Time.current
        )
      end
    else
      Tag.create!(repository: repository, name: tag_name, manifest: manifest)
      TagEvent.create!(
        repository: repository,
        tag_name: tag_name,
        action: "create",
        new_digest: manifest.digest,
        actor: actor,
        occurred_at: Time.current
      )
    end
  end

  def update_repository_size!(repository)
    total = repository.manifests.joins(layers: :blob).sum("blobs.size")
    repository.update_column(:total_size, total)
  end
end
