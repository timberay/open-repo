require "test_helper"

class AuthErrorsTest < ActiveSupport::TestCase
  test "Auth::Error is the root" do
    assert_kind_of StandardError, Auth::Error.new
  end

  test "Stage 0 error classes inherit from Auth::Error" do
    [ Auth::InvalidProfile, Auth::EmailMismatch, Auth::ProviderOutage ].each do |k|
      assert k.ancestors.include?(Auth::Error), "#{k} must inherit Auth::Error"
    end
  end
end
