require "test_helper"

class Auth::SessionCreatorTest < ActiveSupport::TestCase
  setup do
    @original_admin_email     = Rails.configuration.x.registry.admin_email
    @original_allowed_domains = Rails.configuration.x.registry.allowed_email_domains
  end

  teardown do
    Rails.configuration.x.registry.admin_email            = @original_admin_email
    Rails.configuration.x.registry.allowed_email_domains  = @original_allowed_domains
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

  # UC-AUTH-017.e1 — existing user with verified email re-signs in succeeds.
  test "UC-AUTH-017.e1 — existing verified identity re-sign-in succeeds (no new identity)" do
    existing = identities(:tonny_google)
    profile = profile_for(identity: existing) # email_verified: true via helper

    assert_no_difference -> { Identity.count } do
      assert_no_difference -> { User.count } do
        user = Auth::SessionCreator.new.call(profile)
        assert_equal existing.user, user
      end
    end
  end

  # UC-AUTH-017.e2 — Case A now re-verifies on every sign-in (GAP CLOSED).
  # Case A finds the identity by (provider, uid) and MUST re-check
  # `email_verified` just like Cases B/C. A provider-side email change with
  # email_verified=false must be rejected, not silently accepted.
  test "UC-AUTH-017.e2 — Case A rejects re-sign-in when email_verified=false" do
    existing = identities(:tonny_google)
    profile = Auth::ProviderProfile.new(
      provider: existing.provider,
      uid: existing.uid,
      email: "tonny+changed@timberay.com", # email changed at Google
      email_verified: false,                # and no longer verified
      name: existing.name,
      avatar_url: nil
    )

    assert_raises(Auth::EmailMismatch) do
      Auth::SessionCreator.new.call(profile)
    end
  end

  # UC-AUTH-017.e2b — a nil email_verified flag is treated as unverified,
  # matching the strict `== true` policy already enforced in Cases B/C.
  test "UC-AUTH-017.e2b — Case A rejects re-sign-in when email_verified=nil" do
    existing = identities(:tonny_google)
    profile = Auth::ProviderProfile.new(
      provider: existing.provider,
      uid: existing.uid,
      email: existing.email,
      email_verified: nil,
      name: existing.name,
      avatar_url: nil
    )

    assert_raises(Auth::EmailMismatch) do
      Auth::SessionCreator.new.call(profile)
    end
  end

  # --- Domain allowlist (REGISTRY_ALLOWED_EMAIL_DOMAINS) ---

  test "domain allowlist — rejects verified sign-in whose email domain is not allowed" do
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "outsider-uid",
      email: "stranger@example.com",
      email_verified: true,
      name: "Stranger",
      avatar_url: nil
    )

    assert_no_difference -> { User.count } do
      assert_no_difference -> { Identity.count } do
        assert_raises(Auth::UnauthorizedDomain) { Auth::SessionCreator.new.call(profile) }
      end
    end
  end

  test "domain allowlist — allows verified sign-in whose email domain is in the allowlist" do
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "insider-uid",
      email: "newbie@timberay.com",
      email_verified: true,
      name: "New Bie",
      avatar_url: nil
    )

    assert_difference -> { User.count }, +1 do
      user = Auth::SessionCreator.new.call(profile)
      assert_equal "newbie@timberay.com", user.email
    end
  end

  test "domain allowlist — empty allowlist allows any verified domain (opt-in default)" do
    Rails.configuration.x.registry.allowed_email_domains = []
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "anydomain-uid",
      email: "someone@example.com",
      email_verified: true,
      name: "Some One",
      avatar_url: nil
    )

    assert_difference -> { User.count }, +1 do
      user = Auth::SessionCreator.new.call(profile)
      assert_equal "someone@example.com", user.email
    end
  end

  test "domain allowlist — rejects spoofed multi-@ email even if it ends with an allowed domain" do
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "spoof-uid",
      email: "attacker@evil.com@timberay.com",
      email_verified: true,
      name: "Spoof",
      avatar_url: nil
    )

    assert_no_difference -> { User.count } do
      assert_raises(Auth::UnauthorizedDomain) { Auth::SessionCreator.new.call(profile) }
    end
  end

  test "domain allowlist — rejects a trailing-@ spoof that ends with an allowed domain" do
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "trailing-at-uid",
      email: "attacker@timberay.com@",
      email_verified: true,
      name: "Trailing At",
      avatar_url: nil
    )

    assert_no_difference -> { User.count } do
      assert_raises(Auth::UnauthorizedDomain) { Auth::SessionCreator.new.call(profile) }
    end
  end

  test "domain allowlist — rejects an email with no @ that matches an allowed domain literally" do
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "noat-uid",
      email: "timberay.com",
      email_verified: true,
      name: "No At",
      avatar_url: nil
    )

    assert_no_difference -> { User.count } do
      assert_raises(Auth::UnauthorizedDomain) { Auth::SessionCreator.new.call(profile) }
    end
  end

  test "domain allowlist — verification precedes domain check (unverified disallowed → EmailMismatch)" do
    # An unverified profile must fail the same way regardless of its domain, so
    # the failure cannot be used as an oracle for allowlist membership.
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "unverified-disallowed-uid",
      email: "stranger@example.com",
      email_verified: false,
      name: "Stranger",
      avatar_url: nil
    )

    assert_raises(Auth::EmailMismatch) { Auth::SessionCreator.new.call(profile) }
  end

  test "domain allowlist — domain match is case-insensitive" do
    Rails.configuration.x.registry.allowed_email_domains = [ "timberay.com" ]
    profile = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "mixedcase-uid",
      email: "person@TIMBERAY.com",
      email_verified: true,
      name: "Mixed Case",
      avatar_url: nil
    )

    assert_difference -> { User.count }, +1 do
      assert_nothing_raised { Auth::SessionCreator.new.call(profile) }
    end
  end

  # UC-AUTH-017.e2d — a verified provider-side email change also keeps the
  # canonical user.email in sync (not just identity.email), so PAT auth and the
  # domain policy see the current address. Guards the SessionCreator ordering.
  test "UC-AUTH-017.e2d — Case A syncs user.email on verified email change" do
    existing = identities(:tonny_google)
    profile = Auth::ProviderProfile.new(
      provider: existing.provider,
      uid: existing.uid,
      email: "tonny+synced@timberay.com",
      email_verified: true,
      name: existing.name,
      avatar_url: nil
    )

    user = Auth::SessionCreator.new.call(profile)
    assert_equal "tonny+synced@timberay.com", user.reload.email
  end

  # UC-AUTH-017.e2c — a verified provider-side email change updates the stored
  # identity email (and still resolves to the same user).
  test "UC-AUTH-017.e2c — Case A updates stored identity email on verified change" do
    existing = identities(:tonny_google)
    profile = Auth::ProviderProfile.new(
      provider: existing.provider,
      uid: existing.uid,
      email: "tonny+rotated@timberay.com",
      email_verified: true,
      name: existing.name,
      avatar_url: nil
    )

    assert_no_difference -> { Identity.count } do
      user = Auth::SessionCreator.new.call(profile)
      assert_equal existing.user, user
    end
    assert_equal "tonny+rotated@timberay.com", existing.reload.email
  end
end
