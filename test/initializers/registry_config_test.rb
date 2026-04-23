require "test_helper"

class RegistryConfigTest < ActiveSupport::TestCase
  test "loads admin_email from test_helper default" do
    assert_equal "admin@timberay.com", Rails.configuration.x.registry.admin_email
  end

  test "anonymous_pull_enabled is true by default" do
    assert_equal true, Rails.configuration.x.registry.anonymous_pull_enabled
  end
end
