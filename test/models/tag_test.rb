require "test_helper"

class TagTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
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

  test "validations requires name" do
    tag = Tag.new(repository: repository, manifest: manifest, name: nil)
    refute tag.valid?
  end

  test "validations requires unique name per repository" do
    Tag.create!(repository: repository, manifest: manifest, name: "latest")
    t2 = Tag.new(repository: repository, manifest: manifest, name: "latest")
    refute t2.valid?
  end
end
