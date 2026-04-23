require "test_helper"

class SessionCreatorTest < ActiveSupport::TestCase
  def profile_for(identity:, overrides: {})
    Auth::ProviderProfile.new(
      provider: identity.provider,
      uid: identity.uid,
      email: identity.email,
      email_verified: true,
      name: identity.name || "Test",
      avatar_url: nil,
      **overrides
    )
  end

  test "Case A — existing (provider, uid) → returns existing user, updates last_login_at" do
    existing = identities(:tonny_google)
    profile = profile_for(identity: existing)

    user = SessionCreator.new.call(profile)

    assert_equal existing.user, user
    existing.reload
    assert_in_delta Time.current, existing.last_login_at, 5.seconds
    user.reload
    assert_equal existing.id, user.primary_identity_id
  end
end
