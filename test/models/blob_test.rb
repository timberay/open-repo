require "test_helper"

class BlobTest < ActiveSupport::TestCase
  test "validations requires digest and size" do
    blob = Blob.new
    refute blob.valid?
    assert_includes blob.errors[:digest], "can't be blank"
    assert_includes blob.errors[:size], "can't be blank"
  end

  test "validations requires unique digest" do
    Blob.create!(digest: "sha256:abc", size: 1024)
    b2 = Blob.new(digest: "sha256:abc", size: 1024)
    refute b2.valid?
  end

  test "defaults has references_count defaulting to 0" do
    blob = Blob.create!(digest: "sha256:abc", size: 1024)
    assert_equal 0, blob.references_count
  end
end
