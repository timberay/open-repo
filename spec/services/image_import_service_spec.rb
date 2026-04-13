require 'rails_helper'
require 'rubygems/package'

RSpec.describe ImageImportService do
  let(:store_dir) { Dir.mktmpdir }
  let(:blob_store) { BlobStore.new(store_dir) }
  let(:service) { ImageImportService.new(blob_store) }

  after { FileUtils.rm_rf(store_dir) }

  describe '#call' do
    it 'imports a docker save tar file' do
      tar_path = create_test_docker_tar(store_dir)

      result = service.call(tar_path, repository_name: 'imported-image', tag_name: 'v1')

      expect(result).to be_a(Manifest)
      expect(Repository.find_by(name: 'imported-image')).to be_present
      expect(Tag.find_by(name: 'v1')).to be_present
    end
  end

  private

  def create_test_docker_tar(dir)
    tar_path = File.join(dir, 'test.tar')

    config_content = '{"architecture":"amd64","os":"linux","config":{"Cmd":["/bin/sh"]}}'
    config_digest = Digest::SHA256.hexdigest(config_content)

    layer_content = SecureRandom.random_bytes(256)
    layer_digest = Digest::SHA256.hexdigest(layer_content)

    manifest_list = [{
      'Config' => "#{config_digest}.json",
      'RepoTags' => ['imported-image:v1'],
      'Layers' => ["#{layer_digest}/layer.tar"]
    }]

    File.open(tar_path, 'wb') do |tar_io|
      Gem::Package::TarWriter.new(tar_io) do |tar|
        tar.add_file_simple('manifest.json', 0644, manifest_list.to_json.bytesize) { |f| f.write(manifest_list.to_json) }
        tar.add_file_simple("#{config_digest}.json", 0644, config_content.bytesize) { |f| f.write(config_content) }
        tar.mkdir("#{layer_digest}", 0755)
        tar.add_file_simple("#{layer_digest}/layer.tar", 0644, layer_content.bytesize) { |f| f.write(layer_content) }
      end
    end

    tar_path
  end
end
