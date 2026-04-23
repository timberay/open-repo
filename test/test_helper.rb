ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Disable external HTTP calls by default
WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  fixtures :all

  setup do
    Rails.configuration.x.registry.admin_email            = "admin@timberay.com"
    Rails.configuration.x.registry.anonymous_pull_enabled = true
  end
end

class ActionDispatch::IntegrationTest
  include TokenFixtures

  # Build PAT Basic auth headers for V2 protected endpoints.
  # Default: tonny@timberay.com / tonny_cli_active PAT.
  def basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(email, pat_raw) }
  end
end
