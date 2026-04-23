require "test_helper"

class RackAttackAuthThrottleTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    Rack::Attack.enabled = true
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = Rails.cache
  end

  test "POST /auth/google_oauth2 is throttled at 10/min/IP (11th returns 429 + Retry-After)" do
    headers = { "REMOTE_ADDR" => "198.51.100.10" }
    10.times do |i|
      post "/auth/google_oauth2", headers: headers
      refute_equal 429, response.status, "request #{i + 1} should not be throttled"
    end
    post "/auth/google_oauth2", headers: headers
    assert_equal 429, response.status
    assert_equal "60", response.headers["Retry-After"]
    body = JSON.parse(response.body)
    assert_equal "TOO_MANY_REQUESTS", body.dig("errors", 0, "code")
  end
end
