require "test_helper"

class Auth::SafeReturnTest < ActiveSupport::TestCase
  # We exercise the concern via a throwaway host class so the test does not
  # depend on ApplicationController (and so it can call the private method
  # without going through controller machinery).
  class Host
    include Auth::SafeReturn
    public :safe_return_to
  end

  setup { @host = Host.new }

  test "returns the path for an existing relative route" do
    assert_equal "/repositories/foo", @host.safe_return_to("/repositories/foo")
  end

  test "preserves the query string when the path resolves to a route" do
    assert_equal "/settings/tokens?x=1", @host.safe_return_to("/settings/tokens?x=1")
  end

  test "blocks protocol-relative URLs" do
    assert_nil @host.safe_return_to("//evil.com/x")
  end

  test "blocks absolute URLs" do
    assert_nil @host.safe_return_to("https://evil.com/x")
  end

  test "blocks paths that do not match any route" do
    assert_nil @host.safe_return_to("/no/such/path-#{SecureRandom.hex(2)}")
  end

  test "returns nil for nil input" do
    assert_nil @host.safe_return_to(nil)
  end

  test "returns nil for empty string" do
    assert_nil @host.safe_return_to("")
  end

  test "returns nil for paths without a leading slash" do
    assert_nil @host.safe_return_to("not-a-path")
  end

  test "swallows URI::InvalidURIError and returns nil" do
    assert_nil @host.safe_return_to("/%")
  end
end
