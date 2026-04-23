require "test_helper"
require "rubygems/package"

class ImageImportServiceTest < ActiveSupport::TestCase
  def store_dir
    @store_dir ||= Dir.mktmpdir
  end

  def blob_store
    @blob_store ||= BlobStore.new(store_dir)
  end

  def service
    @service ||= ImageImportService.new(blob_store)
  end

  teardown do
    FileUtils.rm_rf(store_dir)
  end

  test "call imports a docker save tar file" do
    tar_path = create_test_docker_tar(store_dir)

    result = service.call(tar_path, actor: "anonymous", repository_name: "imported-image", tag_name: "v1")

    assert_kind_of Manifest, result
    assert Repository.find_by(name: "imported-image").present?
    assert Tag.find_by(name: "v1").present?
  end

  test "call without actor: raises ArgumentError" do
    tar_path = create_test_docker_tar(store_dir)
    err = assert_raises(ArgumentError) do
      service.call(tar_path, repository_name: "r", tag_name: "v1")
    end
    assert_match(/missing keyword: :actor/, err.message)
  end

  private

  def create_test_docker_tar(dir)
    tar_path = File.join(dir, "test.tar")

    config_content = '{"architecture":"amd64","os":"linux","config":{"Cmd":["/bin/sh"]}}'
    config_digest = Digest::SHA256.hexdigest(config_content)

    layer_content = SecureRandom.random_bytes(256)
    layer_digest = Digest::SHA256.hexdigest(layer_content)

    manifest_list = [ {
      "Config" => "#{config_digest}.json",
      "RepoTags" => [ "imported-image:v1" ],
      "Layers" => [ "#{layer_digest}/layer.tar" ]
    } ]

    File.open(tar_path, "wb") do |tar_io|
      Gem::Package::TarWriter.new(tar_io) do |tar|
        tar.add_file_simple("manifest.json", 0644, manifest_list.to_json.bytesize) { |f| f.write(manifest_list.to_json) }
        tar.add_file_simple("#{config_digest}.json", 0644, config_content.bytesize) { |f| f.write(config_content) }
        tar.mkdir("#{layer_digest}", 0755)
        tar.add_file_simple("#{layer_digest}/layer.tar", 0644, layer_content.bytesize) { |f| f.write(layer_content) }
      end
    end

    tar_path
  end
end
