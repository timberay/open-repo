require "test_helper"

class DependencyAnalyzerTest < ActiveSupport::TestCase
  def shared_blob
    @shared_blob ||= Blob.create!(digest: "sha256:shared", size: 1024)
  end

  def unique_blob
    @unique_blob ||= Blob.create!(digest: "sha256:unique", size: 512)
  end

  def repo_a
    @repo_a ||= Repository.create!(name: "repo-a")
  end

  def repo_b
    @repo_b ||= Repository.create!(name: "repo-b")
  end

  setup do
    ma = Manifest.create!(repository: repo_a, digest: "sha256:ma", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 100)
    Layer.create!(manifest: ma, blob: shared_blob, position: 0)
    Layer.create!(manifest: ma, blob: unique_blob, position: 1)

    mb = Manifest.create!(repository: repo_b, digest: "sha256:mb", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 100)
    Layer.create!(manifest: mb, blob: shared_blob, position: 0)
  end

  test "call identifies repositories sharing layers" do
    result = DependencyAnalyzer.new.call(repo_a)
    assert_equal 1, result.length
    assert_equal "repo-b", result[0][:repository]
    assert_equal 1, result[0][:shared_layers]
  end
end
