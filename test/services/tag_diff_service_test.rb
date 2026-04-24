require "test_helper"

class TagDiffServiceTest < ActiveSupport::TestCase
  def repo
    @repo ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
  end

  def shared_blob
    @shared_blob ||= Blob.create!(digest: "sha256:shared", size: 1024)
  end

  def old_blob
    @old_blob ||= Blob.create!(digest: "sha256:old", size: 512)
  end

  def new_blob
    @new_blob ||= Blob.create!(digest: "sha256:new", size: 2048)
  end

  def manifest_a
    @manifest_a ||= begin
      m = Manifest.create!(repository: repo, digest: "sha256:ma", media_type: "application/vnd.docker.distribution.manifest.v2+json",
                           payload: "{}", size: 100, docker_config: '{"Cmd":["/bin/sh"]}', architecture: "amd64", os: "linux")
      Layer.create!(manifest: m, blob: shared_blob, position: 0)
      Layer.create!(manifest: m, blob: old_blob, position: 1)
      m
    end
  end

  def manifest_b
    @manifest_b ||= begin
      m = Manifest.create!(repository: repo, digest: "sha256:mb", media_type: "application/vnd.docker.distribution.manifest.v2+json",
                           payload: "{}", size: 100, docker_config: '{"Cmd":["/bin/bash"]}', architecture: "amd64", os: "linux")
      Layer.create!(manifest: m, blob: shared_blob, position: 0)
      Layer.create!(manifest: m, blob: new_blob, position: 1)
      m
    end
  end

  test "call identifies common, added, and removed layers" do
    result = TagDiffService.new.call(manifest_a, manifest_b)

    assert_includes result[:common_layers], "sha256:shared"
    assert_includes result[:removed_layers], "sha256:old"
    assert_includes result[:added_layers], "sha256:new"
  end

  test "call computes size delta" do
    result = TagDiffService.new.call(manifest_a, manifest_b)
    assert_equal 2048 - 512, result[:size_delta]
  end

  test "call computes config diff" do
    result = TagDiffService.new.call(manifest_a, manifest_b)
    assert_kind_of Hash, result[:config_diff]
  end
end
