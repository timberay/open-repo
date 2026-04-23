require "test_helper"

class Auth::PatAuthenticatorTest < ActiveSupport::TestCase
  include TokenFixtures

  test "returns (user, pat) for matching email + active raw token" do
    result = Auth::PatAuthenticator.new.call(
      email: "tonny@timberay.com",
      raw_token: TONNY_CLI_RAW
    )
    assert_equal users(:tonny), result.user
    assert_equal personal_access_tokens(:tonny_cli_active), result.pat
  end

  test "email matching is case-insensitive" do
    result = Auth::PatAuthenticator.new.call(
      email: "Tonny@Timberay.COM",
      raw_token: TONNY_CLI_RAW
    )
    assert_equal users(:tonny), result.user
  end

  test "raises PatInvalid when raw token is unknown" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "tonny@timberay.com", raw_token: "oprk_bogus")
    end
  end

  test "raises PatInvalid when PAT is revoked" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "tonny@timberay.com", raw_token: TONNY_REVOKED_RAW)
    end
  end

  test "raises PatInvalid when PAT is expired" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "tonny@timberay.com", raw_token: TONNY_EXPIRED_RAW)
    end
  end

  test "raises PatInvalid when email does not match pat.identity.user.email" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "admin@timberay.com", raw_token: TONNY_CLI_RAW)
    end
  end

  test "raises PatInvalid when email is blank" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "", raw_token: TONNY_CLI_RAW)
    end
  end
end
