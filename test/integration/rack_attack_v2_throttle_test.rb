require "test_helper"

class RackAttackV2ThrottleTest < ActionDispatch::IntegrationTest
  # rack-attack mutates class-level state (cache.store, enabled); pin to a
  # single worker so we don't race with other tests in this process.
  parallelize(workers: 1)

  setup do
    @original_enabled = Rack::Attack.enabled
    @original_store   = Rack::Attack.cache.store
    @original_limit   = ENV["REGISTRY_V2_WRITE_LIMIT"]
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!

    # Pin the v2 write budget low so the boundary + keying can be exercised in
    # a handful of requests instead of the production default (600).
    ENV["REGISTRY_V2_WRITE_LIMIT"] = "3"

    # Pin the fixed-window key to a single minute so a request loop that
    # straddles a wall-clock minute boundary cannot split the counter and
    # silently grant a fresh budget mid-test.
    travel_to Time.current.beginning_of_minute

    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
  end

  teardown do
    travel_back
    Rack::Attack.cache.store = @original_store
    Rack::Attack.enabled = @original_enabled
    ENV["REGISTRY_V2_WRITE_LIMIT"] = @original_limit # nil value deletes the key
    FileUtils.rm_rf(@storage_dir)
  end

  test "v2 writes are throttled per authenticated token (limit+1 returns 429 + Retry-After)" do
    tonny = { "REMOTE_ADDR" => "198.51.100.20" }
            .merge(basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com"))

    3.times do |i|
      post "/v2/rack-v2-token-#{i}/blobs/uploads", headers: tonny
      refute_equal 429, response.status, "write #{i + 1} should be within the per-token budget"
    end

    post "/v2/rack-v2-token-final/blobs/uploads", headers: tonny
    assert_equal 429, response.status
    assert_equal "60", response.headers["Retry-After"]
    body = JSON.parse(response.body)
    assert_equal "TOO_MANY_REQUESTS", body.dig("errors", 0, "code")
  end

  test "throttle is keyed on the token, not the IP — a different token from the same IP is fresh" do
    same_ip = "198.51.100.30"
    tonny = { "REMOTE_ADDR" => same_ip }
            .merge(basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com"))
    3.times { |i| post "/v2/rack-v2-tok-a-#{i}/blobs/uploads", headers: tonny }
    post "/v2/rack-v2-tok-a-final/blobs/uploads", headers: tonny
    assert_equal 429, response.status, "tonny's 4th write should be throttled"

    admin = { "REMOTE_ADDR" => same_ip }
            .merge(basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com"))
    post "/v2/rack-v2-tok-b-1/blobs/uploads", headers: admin
    refute_equal 429, response.status,
      "a different token must not share tonny's budget even from the same IP"
  end

  test "unauthenticated v2 writes fall back to a per-IP budget" do
    ip_a = { "REMOTE_ADDR" => "198.51.100.40" } # no Authorization header
    3.times do |i|
      post "/v2/rack-v2-anon-#{i}/blobs/uploads", headers: ip_a
      refute_equal 429, response.status, "anon write #{i + 1} should be within the IP budget"
    end
    post "/v2/rack-v2-anon-final/blobs/uploads", headers: ip_a
    assert_equal 429, response.status, "the 4th unauthenticated write from one IP is throttled"

    ip_b = { "REMOTE_ADDR" => "198.51.100.41" }
    post "/v2/rack-v2-anon-b/blobs/uploads", headers: ip_b
    refute_equal 429, response.status, "a different IP starts a fresh budget"
  end

  test "GET /v2/_catalog is NOT throttled by the v2 write limiter (non-GET scope)" do
    headers = { "REMOTE_ADDR" => "198.51.100.21" }.merge(basic_auth_for)

    10.times do |i|
      get "/v2/_catalog", headers: headers
      refute_equal 429, response.status, "GET request #{i + 1} must not be throttled"
    end
  end
end
