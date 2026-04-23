require "test_helper"

class Auth::GoogleAdapterTest < ActiveSupport::TestCase
  def valid_auth_hash
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-123",
      info: { email: "tonny@timberay.com", name: "Tonny Kim", image: "https://lh3.example/pic.jpg" },
      extra: { raw_info: { email_verified: true } }
    )
  end

  test "returns ProviderProfile from valid auth_hash" do
    profile = Auth::GoogleAdapter.new.to_profile(valid_auth_hash)
    assert_instance_of Auth::ProviderProfile, profile
    assert_equal "google_oauth2", profile.provider
    assert_equal "google-uid-123", profile.uid
    assert_equal "tonny@timberay.com", profile.email
    assert_equal true, profile.email_verified
    assert_equal "Tonny Kim", profile.name
    assert_equal "https://lh3.example/pic.jpg", profile.avatar_url
  end

  test "raises Auth::InvalidProfile when email is blank" do
    h = valid_auth_hash
    h.info.email = ""
    assert_raises(Auth::InvalidProfile) { Auth::GoogleAdapter.new.to_profile(h) }
  end

  test "raises Auth::InvalidProfile when uid is blank" do
    h = valid_auth_hash
    h.uid = ""
    assert_raises(Auth::InvalidProfile) { Auth::GoogleAdapter.new.to_profile(h) }
  end

  test "email_verified defaults to nil when provider doesn't report" do
    h = valid_auth_hash
    h.extra.raw_info = {}
    profile = Auth::GoogleAdapter.new.to_profile(h)
    assert_nil profile.email_verified
  end
end
