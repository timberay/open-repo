require 'rubygems/package'

class ImageExportService
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(repository_name, tag_name, output_path:)
    repo = Repository.find_by!(name: repository_name)
    tag = repo.tags.find_by!(name: tag_name)
    manifest = tag.manifest

    config_digest_hex = manifest.config_digest.sub('sha256:', '')
    layers = manifest.layers.includes(:blob).order(:position)

    File.open(output_path, 'wb') do |tar_io|
      Gem::Package::TarWriter.new(tar_io) do |tar|
        # manifest.json
        docker_manifest = [{
          'Config' => "#{config_digest_hex}.json",
          'RepoTags' => ["#{repository_name}:#{tag_name}"],
          'Layers' => layers.map { |l| "#{l.blob.digest.sub('sha256:', '')}/layer.tar" }
        }]
        manifest_json = docker_manifest.to_json
        tar.add_file_simple('manifest.json', 0644, manifest_json.bytesize) { |f| f.write(manifest_json) }

        # Config blob
        config_io = @blob_store.get(manifest.config_digest)
        config_data = config_io.read
        config_io.close
        tar.add_file_simple("#{config_digest_hex}.json", 0644, config_data.bytesize) { |f| f.write(config_data) }

        # Layer blobs
        layers.each do |layer|
          layer_io = @blob_store.get(layer.blob.digest)
          layer_data = layer_io.read
          layer_io.close
          digest_hex = layer.blob.digest.sub('sha256:', '')
          tar.mkdir(digest_hex, 0755)
          tar.add_file_simple("#{digest_hex}/layer.tar", 0644, layer_data.bytesize) { |f| f.write(layer_data) }
        end
      end
    end
  end
end
