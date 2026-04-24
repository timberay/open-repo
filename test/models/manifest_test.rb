require "test_helper"

class ManifestTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
  end

  test "validations requires digest, media_type, payload, size" do
    manifest = Manifest.new(repository: repository)
    refute manifest.valid?
    assert_includes manifest.errors[:digest], "can't be blank"
    assert_includes manifest.errors[:media_type], "can't be blank"
    assert_includes manifest.errors[:payload], "can't be blank"
    assert_includes manifest.errors[:size], "can't be blank"
  end

  test "validations requires unique digest" do
    Manifest.create!(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    m2 = Manifest.new(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    refute m2.valid?
  end

  test "associations has many tags" do
    assert_equal :has_many, Manifest.reflect_on_association(:tags).macro
  end

  test "associations has many layers" do
    assert_equal :has_many, Manifest.reflect_on_association(:layers).macro
  end

  test "associations has many pull_events" do
    assert_equal :has_many, Manifest.reflect_on_association(:pull_events).macro
  end
end
