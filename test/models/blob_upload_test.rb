require "test_helper"

class BlobUploadTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo")
  end

  test "validations requires uuid" do
    upload = BlobUpload.new(repository: repository, uuid: nil)
    refute upload.valid?
  end

  test "validations requires unique uuid" do
    BlobUpload.create!(repository: repository, uuid: "abc-123")
    u2 = BlobUpload.new(repository: repository, uuid: "abc-123")
    refute u2.valid?
  end

  test "defaults byte_offset defaults to 0" do
    upload = BlobUpload.create!(repository: repository, uuid: "abc-123")
    assert_equal 0, upload.byte_offset
  end
end
