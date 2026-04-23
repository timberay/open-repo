ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Disable external HTTP calls by default
WebMock.disable_net_connect!(allow_localhost: true)

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  fixtures :all

  setup do
    Rails.configuration.x.registry.admin_email            = "admin@timberay.com"
    Rails.configuration.x.registry.anonymous_pull_enabled = true
  end
end
