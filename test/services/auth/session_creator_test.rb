require "test_helper"

class Auth::SessionCreatorTest < ActiveSupport::TestCase
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

    user = Auth::SessionCreator.new.call(profile)

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
      result = Auth::SessionCreator.new.call(profile)
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
    assert_raises(Auth::EmailMismatch) { Auth::SessionCreator.new.call(profile) }
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
    assert_raises(Auth::EmailMismatch) { Auth::SessionCreator.new.call(profile) }
  end

  test "Case C — new email creates User + Identity" do
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "brand-new-uid",
      email: "newbie@timberay.com",
      email_verified: true,
      name: "New Bie",
      avatar_url: nil
    )

    assert_difference -> { User.count }, +1 do
      assert_difference -> { Identity.count }, +1 do
        user = Auth::SessionCreator.new.call(profile)
        assert_equal "newbie@timberay.com", user.email
        assert_equal user.identities.first.id, user.primary_identity_id
        refute user.admin?
      end
    end
  end

  test "Case C — REGISTRY_ADMIN_EMAIL match grants admin=true" do
    Rails.configuration.x.registry.admin_email = "boss@timberay.com"
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "boss-uid",
      email: "boss@timberay.com",
      email_verified: true,
      name: "The Boss",
      avatar_url: nil
    )

    user = Auth::SessionCreator.new.call(profile)
    assert user.admin?
  end

  test "InvalidProfile raised for blank email" do
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2", uid: "x", email: "",
      email_verified: true, name: nil, avatar_url: nil
    )
    assert_raises(Auth::InvalidProfile) { Auth::SessionCreator.new.call(profile) }
  end

  test "Case C — email_verified=false raises EmailMismatch (no User or Identity created)" do
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "unverified-new-uid",
      email: "stranger@example.com",
      email_verified: false,
      name: "Stranger",
      avatar_url: nil
    )

    assert_no_difference -> { User.count } do
      assert_no_difference -> { Identity.count } do
        assert_raises(Auth::EmailMismatch) { Auth::SessionCreator.new.call(profile) }
      end
    end
  end

  test "Case C — email_verified=nil raises EmailMismatch (admin candidate denied)" do
    Rails.configuration.x.registry.admin_email = "boss@timberay.com"
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "boss-unverified-uid",
      email: "boss@timberay.com",
      email_verified: nil,
      name: "Not The Boss",
      avatar_url: nil
    )

    assert_no_difference -> { User.count } do
      assert_raises(Auth::EmailMismatch) { Auth::SessionCreator.new.call(profile) }
    end
  end
end
