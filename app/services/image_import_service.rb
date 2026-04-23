require "rubygems/package"

class ImageImportService
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(tar_path, actor:, repository_name: nil, tag_name: nil)
    entries = {}

    File.open(tar_path, "rb") do |tar_io|
      Gem::Package::TarReader.new(tar_io) do |tar|
        tar.each do |entry|
          entries[entry.full_name] = entry.read if entry.file?
        end
      end
    end

    manifest_list = JSON.parse(entries["manifest.json"])
    image_manifest = manifest_list.first

    repo_name = repository_name || extract_repo_name(image_manifest)
    tag = tag_name || extract_tag_name(image_manifest)

    # Store config blob
    config_filename = image_manifest["Config"]
    config_content = entries[config_filename]
    config_digest = DigestCalculator.compute(config_content)
    @blob_store.put(config_digest, StringIO.new(config_content))
    Blob.find_or_create_by!(digest: config_digest) { |b| b.size = config_content.bytesize }

    # Store layer blobs
    layer_digests = []
    image_manifest["Layers"].each do |layer_path|
      layer_content = entries[layer_path]
      layer_digest = DigestCalculator.compute(layer_content)
      @blob_store.put(layer_digest, StringIO.new(layer_content))
      Blob.find_or_create_by!(digest: layer_digest) { |b| b.size = layer_content.bytesize }
      layer_digests << { digest: layer_digest, size: layer_content.bytesize }
    end

    # Build and process V2 manifest
    v2_manifest = build_v2_manifest(config_digest, config_content.bytesize, layer_digests)
    processor = ManifestProcessor.new(@blob_store)
    processor.call(repo_name, tag, "application/vnd.docker.distribution.manifest.v2+json", v2_manifest.to_json, actor: actor)
  end

  private

  def extract_repo_name(image_manifest)
    repo_tag = image_manifest["RepoTags"]&.first
    return "imported" unless repo_tag
    repo_tag.split(":").first
  end

  def extract_tag_name(image_manifest)
    repo_tag = image_manifest["RepoTags"]&.first
    return "latest" unless repo_tag
    repo_tag.split(":").last
  end

  def build_v2_manifest(config_digest, config_size, layer_digests)
    {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_size,
        digest: config_digest
      },
      layers: layer_digests.map do |ld|
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: ld[:size],
          digest: ld[:digest]
        }
      end
    }
  end
end
