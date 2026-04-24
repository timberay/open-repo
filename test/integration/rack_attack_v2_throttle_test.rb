require "test_helper"

class RackAttackV2ThrottleTest < ActionDispatch::IntegrationTest
  # rack-attack mutates class-level state (cache.store, enabled); pin to a
  # single worker so we don't race with other tests in this process.
  parallelize(workers: 1)

  setup do
    @original_enabled = Rack::Attack.enabled
    @original_store   = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!

    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
  end

  teardown do
    Rack::Attack.cache.store = @original_store
    Rack::Attack.enabled = @original_enabled
    FileUtils.rm_rf(@storage_dir)
  end

  test "POST /v2/:name/blobs/uploads is throttled at 30/min/IP (31st returns 429 + Retry-After)" do
    headers = { "REMOTE_ADDR" => "198.51.100.20" }.merge(basic_auth_for)

    30.times do |i|
      post "/v2/rack-v2-throttle-#{i}/blobs/uploads", headers: headers
      refute_equal 429, response.status, "request #{i + 1} should not be throttled"
    end

    post "/v2/rack-v2-throttle-final/blobs/uploads", headers: headers
    assert_equal 429, response.status
    assert_equal "60", response.headers["Retry-After"]
    body = JSON.parse(response.body)
    assert_equal "TOO_MANY_REQUESTS", body.dig("errors", 0, "code")
  end

  test "GET /v2/_catalog is NOT throttled by the v2 mutation limiter (non-GET scope)" do
    headers = { "REMOTE_ADDR" => "198.51.100.21" }.merge(basic_auth_for)

    31.times do |i|
      get "/v2/_catalog", headers: headers
      refute_equal 429, response.status, "GET request #{i + 1} must not be throttled"
    end
  end

  test "throttle counter is per-IP — a different IP starts a fresh budget" do
    ip_a = { "REMOTE_ADDR" => "198.51.100.30" }.merge(basic_auth_for)
    30.times do |i|
      post "/v2/rack-v2-ip-a-#{i}/blobs/uploads", headers: ip_a
    end
    post "/v2/rack-v2-ip-a-final/blobs/uploads", headers: ip_a
    assert_equal 429, response.status, "IP A's 31st request should be throttled"

    ip_b = { "REMOTE_ADDR" => "198.51.100.31" }.merge(basic_auth_for)
    post "/v2/rack-v2-ip-b-1/blobs/uploads", headers: ip_b
    refute_equal 429, response.status,
      "IP B's first request must not be throttled — counter is IP-scoped"
  end
end
