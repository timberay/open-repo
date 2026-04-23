require "test_helper"

class LayerTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo")
  end

  def manifest
    @manifest ||= Manifest.create!(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
  end

  def blob
    @blob ||= Blob.create!(digest: "sha256:layer1", size: 2048)
  end

  test "validations requires position" do
    layer = Layer.new(manifest: manifest, blob: blob, position: nil)
    refute layer.valid?
  end

  test "validations requires unique position per manifest" do
    Layer.create!(manifest: manifest, blob: blob, position: 0)
    l2 = Layer.new(manifest: manifest, blob: blob, position: 0)
    refute l2.valid?
  end
end
