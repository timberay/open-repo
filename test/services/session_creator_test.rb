require "test_helper"

class SessionCreatorTest < ActiveSupport::TestCase
  setup do
    @original_admin_email = Rails.configuration.x.registry.admin_email
  end

  teardown do
    Rails.configuration.x.registry.admin_email = @original_admin_email
  end

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

  test "Case B — email matches existing user, verified → attaches new identity" do
    user = users(:tonny)
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "different-google-uid",     # new identity for this user
      email: user.email,
      email_verified: true,
      name: "Tonny Kim",
      avatar_url: nil
    )

    assert_difference -> { user.identities.count }, +1 do
      result = SessionCreator.new.call(profile)
      assert_equal user, result
    end

    new_identity = user.identities.find_by!(uid: "different-google-uid")
    user.reload
    assert_equal new_identity.id, user.primary_identity_id
  end

  test "Case B — email_verified=false raises EmailMismatch" do
    user = users(:tonny)
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "untrusted-uid",
      email: user.email,
      email_verified: false,
      name: "X",
      avatar_url: nil
    )
    assert_raises(Auth::EmailMismatch) { SessionCreator.new.call(profile) }
  end

  test "Case B — email_verified=nil raises EmailMismatch (strict)" do
    user = users(:tonny)
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "untrusted-nil-uid",
      email: user.email,
      email_verified: nil,
      name: "X",
      avatar_url: nil
    )
    assert_raises(Auth::EmailMismatch) { SessionCreator.new.call(profile) }
  end
end
