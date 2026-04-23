require "test_helper"

class Auth::ProviderProfileTest < ActiveSupport::TestCase
  test "stores provider, uid, email, email_verified, name, avatar_url" do
    p = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "xxx",
      email: "a@b.c",
      email_verified: true,
      name: "A",
      avatar_url: nil
    )
    assert_equal "google_oauth2", p.provider
    assert_equal "a@b.c", p.email
    assert_nil p.avatar_url
  end

  test "is frozen (Data)" do
    p = Auth::ProviderProfile.new(
      provider: "x", uid: "y", email: "z@w", email_verified: nil, name: nil, avatar_url: nil
    )
    assert p.frozen?
  end
end
