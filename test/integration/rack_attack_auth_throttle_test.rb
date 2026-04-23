require "test_helper"

class RackAttackAuthThrottleTest < ActionDispatch::IntegrationTest
  # rack-attack mutates class-level state (cache.store, enabled); pin to a
  # single worker so we don't race with other parallel test processes.
  parallelize(workers: 1)

  setup do
    @original_enabled = Rack::Attack.enabled
    @original_store   = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  teardown do
    Rack::Attack.cache.store = @original_store
    Rack::Attack.enabled = @original_enabled
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
