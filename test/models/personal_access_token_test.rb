require "test_helper"

class PersonalAccessTokenTest < ActiveSupport::TestCase
  include TokenFixtures

  test ".active excludes revoked" do
    assert_not_includes PersonalAccessToken.active, personal_access_tokens(:tonny_revoked)
  end

  test ".active excludes expired" do
    assert_not_includes PersonalAccessToken.active, personal_access_tokens(:tonny_expired)
  end

  test ".active includes never-expiring ci kind" do
    assert_includes PersonalAccessToken.active, personal_access_tokens(:tonny_ci_never_expires)
  end

  test ".active includes unexpired cli" do
    assert_includes PersonalAccessToken.active, personal_access_tokens(:tonny_cli_active)
  end

  test ".authenticate_raw returns token for matching raw secret" do
    found = PersonalAccessToken.authenticate_raw(TONNY_CLI_RAW)
    assert_equal personal_access_tokens(:tonny_cli_active), found
  end

  test ".authenticate_raw returns nil for non-existent raw" do
    assert_nil PersonalAccessToken.authenticate_raw("oprk_nonexistent")
  end

  test ".authenticate_raw returns nil for revoked PAT (via .active)" do
    assert_nil PersonalAccessToken.authenticate_raw(TONNY_REVOKED_RAW)
  end

  test ".authenticate_raw returns nil for expired PAT" do
    assert_nil PersonalAccessToken.authenticate_raw(TONNY_EXPIRED_RAW)
  end

  test ".generate_raw returns oprk_-prefixed url-safe string" do
    raw = PersonalAccessToken.generate_raw
    assert_match(/\Aoprk_[A-Za-z0-9_-]+\z/, raw)
    assert_operator raw.length, :>=, 40
  end

  test "#revoke! sets revoked_at" do
    pat = personal_access_tokens(:tonny_cli_active)
    pat.revoke!
    assert_not_nil pat.reload.revoked_at
  end

  test "validates name uniqueness per identity" do
    dup = PersonalAccessToken.new(
      identity: identities(:tonny_google),
      name: "laptop",
      token_digest: "dup_digest",
      kind: "cli"
    )
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end

  # --- .revoke_disallowed! (one-shot policy-change cleanup) ---

  def outsider_active_pat(email: "outsider@example.com")
    user = User.create!(email: email)
    identity = user.identities.create!(
      provider: "google_oauth2", uid: "outsider-#{SecureRandom.hex(4)}",
      email: email, email_verified: true, name: "Outsider"
    )
    raw = PersonalAccessToken.generate_raw
    identity.personal_access_tokens.create!(
      name: "laptop", kind: "cli",
      token_digest: Digest::SHA256.hexdigest(raw),
      prefix: PersonalAccessToken.prefix_for(raw)
    )
  end

  test ".revoke_disallowed! revokes active PATs whose owner domain is not allowed" do
    pat = outsider_active_pat
    PersonalAccessToken.revoke_disallowed!([ "timberay.com" ])
    assert_not_nil pat.reload.revoked_at
  end

  test ".revoke_disallowed! keeps PATs whose owner domain is allowed" do
    allowed = personal_access_tokens(:tonny_cli_active) # tonny@timberay.com
    PersonalAccessToken.revoke_disallowed!([ "timberay.com" ])
    assert_nil allowed.reload.revoked_at
  end

  test ".revoke_disallowed! with an empty allowlist revokes nothing" do
    pat = outsider_active_pat
    PersonalAccessToken.revoke_disallowed!([])
    assert_nil pat.reload.revoked_at
  end

  test ".revoke_disallowed! returns the PATs it revoked" do
    pat = outsider_active_pat
    revoked = PersonalAccessToken.revoke_disallowed!([ "timberay.com" ])
    assert_includes revoked.map(&:id), pat.id
  end

  def pat_with_emails(user_email:, identity_email:)
    user = User.create!(email: user_email)
    identity = user.identities.create!(
      provider: "google_oauth2", uid: "drift-#{SecureRandom.hex(4)}",
      email: identity_email, email_verified: true, name: "Drift"
    )
    raw = PersonalAccessToken.generate_raw
    identity.personal_access_tokens.create!(
      name: "laptop", kind: "cli",
      token_digest: Digest::SHA256.hexdigest(raw),
      prefix: PersonalAccessToken.prefix_for(raw)
    )
  end

  test ".revoke_disallowed! checks the PAT identity's current email, not the stale user email" do
    # The identity's provider email drifted to a disallowed domain while the
    # user.email (set once at account creation) stayed on the allowed domain.
    pat = pat_with_emails(user_email: "drift@timberay.com", identity_email: "drift@example.com")
    PersonalAccessToken.revoke_disallowed!([ "timberay.com" ])
    assert_not_nil pat.reload.revoked_at, "identity email (example.com) is disallowed → must revoke"
  end

  test ".revoke_disallowed! keeps a PAT whose identity email is allowed despite a stale-disallowed user email" do
    pat = pat_with_emails(user_email: "stale@example.com", identity_email: "fresh@timberay.com")
    PersonalAccessToken.revoke_disallowed!([ "timberay.com" ])
    assert_nil pat.reload.revoked_at, "identity email (timberay.com) is allowed → must survive"
  end

  test ".revoke_disallowed! leaves already-revoked PATs untouched" do
    already = personal_access_tokens(:tonny_revoked)
    original = already.revoked_at
    # tonny@timberay.com is disallowed here, but the already-revoked token is
    # outside .active and must not be re-stamped.
    PersonalAccessToken.revoke_disallowed!([ "example.com" ])
    assert_equal original.to_i, already.reload.revoked_at.to_i
  end
end
