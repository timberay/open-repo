require "test_helper"

# G3 — a real multi-layer docker push must not be rate-limited mid-push, while
# the /auth brute-force throttle stays intact.
#
# Before G3 the v2 write throttle was 30/min keyed on req.ip, so a single
# 8-15 layer push (≈30-50 write requests in seconds) — or several pushers
# behind one CI NAT — burned the budget and got a 429 mid-push.
class RegistryThrottleTest < ActionDispatch::IntegrationTest
  # rack-attack mutates class-level state (cache.store, enabled); pin to a
  # single worker so we don't race with other tests in this process.
  parallelize(workers: 1)

  setup do
    @original_enabled = Rack::Attack.enabled
    @original_store   = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!

    # Pin the fixed-window key to a single minute so a long request loop that
    # straddles a wall-clock minute boundary cannot split the counter.
    travel_to Time.current.beginning_of_minute

    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
  end

  teardown do
    travel_back
    Rack::Attack.cache.store = @original_store
    Rack::Attack.enabled = @original_enabled
    FileUtils.rm_rf(@storage_dir)
  end

  test "a multi-layer push (45 authenticated writes from one IP) is never throttled" do
    headers = { "REMOTE_ADDR" => "203.0.113.50" }.merge(basic_auth_for)

    45.times do |i|
      post "/v2/throttle-push-#{i}/blobs/uploads", headers: headers
      refute_equal 429, response.status,
                   "write ##{i + 1} of a normal push must not be throttled (got #{response.status})"
    end
  end

  test "the /auth brute-force throttle stays intact (11th POST /auth is 429)" do
    headers = { "REMOTE_ADDR" => "203.0.113.51" }

    10.times do |i|
      post "/auth/google_oauth2", headers: headers
      refute_equal 429, response.status, "auth attempt ##{i + 1} should not yet be throttled"
    end

    post "/auth/google_oauth2", headers: headers
    assert_equal 429, response.status, "the 11th auth attempt must be throttled"
  end
end
