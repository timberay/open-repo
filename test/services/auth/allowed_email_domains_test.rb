require "test_helper"

class Auth::AllowedEmailDomainsTest < ActiveSupport::TestCase
  # --- parse (config env string → normalized domain list) ---

  test "parse — empty string is no restriction (allow all)" do
    assert_equal [], Auth::AllowedEmailDomains.parse("")
  end

  test "parse — whitespace-only is treated as unset (allow all)" do
    assert_equal [], Auth::AllowedEmailDomains.parse("   ")
  end

  test "parse — single domain" do
    assert_equal [ "timberay.com" ], Auth::AllowedEmailDomains.parse("timberay.com")
  end

  test "parse — normalizes case/whitespace and splits on comma" do
    assert_equal [ "timberay.com", "example.org" ],
                 Auth::AllowedEmailDomains.parse(" Timberay.COM , example.org ")
  end

  test "parse — tolerates a trailing comma when a valid entry exists" do
    assert_equal [ "timberay.com" ], Auth::AllowedEmailDomains.parse("timberay.com,")
  end

  test "parse — present but no valid domains fails closed (raises)" do
    assert_raises(ArgumentError) { Auth::AllowedEmailDomains.parse(",") }
  end

  test "parse — fails closed on tokens with characters invalid in a domain" do
    assert_raises(ArgumentError) { Auth::AllowedEmailDomains.parse("@") }
    assert_raises(ArgumentError) { Auth::AllowedEmailDomains.parse("http://timberay.com") }
    assert_raises(ArgumentError) { Auth::AllowedEmailDomains.parse("timberay.com example.org") }
    assert_raises(ArgumentError) { Auth::AllowedEmailDomains.parse("timberay.com\nexample.org") }
  end

  # --- domain_for (email → normalized domain or nil) ---

  test "domain_for — extracts normalized domain" do
    assert_equal "timberay.com", Auth::AllowedEmailDomains.domain_for("user@timberay.com")
  end

  test "domain_for — downcases and strips a single trailing dot" do
    assert_equal "timberay.com", Auth::AllowedEmailDomains.domain_for("User@TIMBERAY.com.")
  end

  test "domain_for — returns nil for an email with no @" do
    assert_nil Auth::AllowedEmailDomains.domain_for("timberay.com")
  end

  test "domain_for — returns nil for an email with multiple @ (spoof guard)" do
    assert_nil Auth::AllowedEmailDomains.domain_for("attacker@evil.com@timberay.com")
  end

  test "domain_for — returns nil for a trailing @ (split drops trailing empty fields)" do
    assert_nil Auth::AllowedEmailDomains.domain_for("attacker@timberay.com@")
  end

  test "domain_for — returns nil when the local part is empty" do
    assert_nil Auth::AllowedEmailDomains.domain_for("@timberay.com")
  end

  test "domain_for — returns nil when the domain part is empty" do
    assert_nil Auth::AllowedEmailDomains.domain_for("user@")
  end

  test "domain_for — returns nil for a blank/empty email" do
    assert_nil Auth::AllowedEmailDomains.domain_for("")
  end
end
