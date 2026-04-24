require "test_helper"

class PullEventTest < ActiveSupport::TestCase
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

  test "validations requires occurred_at" do
    event = PullEvent.new(manifest: manifest, repository: repository)
    refute event.valid?
    assert_includes event.errors[:occurred_at], "can't be blank"
  end
end
