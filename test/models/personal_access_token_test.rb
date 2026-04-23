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
end
