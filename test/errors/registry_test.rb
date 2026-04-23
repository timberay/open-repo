require "test_helper"

class RegistryErrorsTest < ActiveSupport::TestCase
  test "exception hierarchy all exceptions inherit from Registry::Error" do
    assert_kind_of Registry::Error, Registry::BlobUnknown.new
    assert_kind_of Registry::Error, Registry::BlobUploadUnknown.new
    assert_kind_of Registry::Error, Registry::ManifestUnknown.new
    assert_kind_of Registry::Error, Registry::ManifestInvalid.new
    assert_kind_of Registry::Error, Registry::NameUnknown.new
    assert_kind_of Registry::Error, Registry::DigestMismatch.new
    assert_kind_of Registry::Error, Registry::Unsupported.new
  end

  test "exception hierarchy Registry::Error inherits from StandardError" do
    assert_kind_of StandardError, Registry::Error.new
  end

  test "exception hierarchy carries custom messages" do
    error = Registry::BlobUnknown.new("blob sha256:abc not found")
    assert_equal "blob sha256:abc not found", error.message
  end

  test "Registry::TagProtected inherits from Registry::Error" do
    assert_kind_of Registry::Error, Registry::TagProtected.new(tag: "v1.0.0", policy: "semver")
  end

  test "Registry::TagProtected builds a default message from tag and policy" do
    error = Registry::TagProtected.new(tag: "v1.0.0", policy: "semver")
    assert_equal "tag 'v1.0.0' is protected by immutability policy 'semver'", error.message
  end

  test "Registry::TagProtected accepts an explicit message override" do
    error = Registry::TagProtected.new(tag: "v1.0.0", policy: "semver", message: "custom")
    assert_equal "custom", error.message
  end

  test "Registry::TagProtected exposes detail hash for Docker Registry error envelope" do
    error = Registry::TagProtected.new(tag: "v1.0.0", policy: "semver")
    assert_equal({ tag: "v1.0.0", policy: "semver" }, error.detail)
  end
end
