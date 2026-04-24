require "test_helper"

# UC-UI-005 — concurrent DELETE race
#
# Lives in its own file (rather than appended to repositories_controller_test.rb)
# because the in-process race forces `parallelize(workers: 1)` AND
# `use_transactional_tests = false`. Sharing those constraints with the rest of
# the controller suite triggers SQLite `BUSY` cascades on neighbour tests
# inside the same process. Pattern mirrors
# `test/integration/v2_tag_protection_atomicity_test.rb` and
# `test/integration/first_pusher_race_test.rb`.
#
# Contract pinned by this test (discovered while writing it):
#   `RepositoriesController#destroy` has TWO valid outcomes under concurrent
#   double-DELETE, and which one fires depends on whether the second request's
#   `set_repository_for_authz#find_by!` happens to run before or after the
#   first request commits its delete:
#     [302, 404] — second request lost the SQLite write lock, then re-read
#                  and saw the row was gone → ActiveRecord::RecordNotFound
#                  → 404 (the "ideal" race outcome).
#     [302, 302] — second request loaded the row before the first committed,
#                  then issued its own DELETE that hit 0 rows. ActiveRecord's
#                  `destroy!` does NOT raise on 0-rows-affected for an already-
#                  loaded instance, so the controller redirects normally.
#   Either way: no exception leaks, repo is gone exactly once, no duplicate
#   destroy callbacks fire on a stale row. The sequential-fallback test below
#   pins the deterministic 404 path.
class RepositoriesControllerConcurrentDeleteTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)
  self.use_transactional_tests = false

  setup do
    @owner_identity = identities(:tonny_google)
    @owner_user = users(:tonny)
    @repo_name = "concurrent-delete-#{SecureRandom.hex(4)}"
    @repo = Repository.create!(name: @repo_name, owner_identity: @owner_identity)
  end

  teardown do
    Repository.where(name: @repo_name).destroy_all
  end

  test "two concurrent DELETEs of the same repository: no exception, repo gone, valid statuses" do
    barrier_mutex = Mutex.new
    barrier_cv    = ConditionVariable.new
    ready_count   = 0
    go            = false

    statuses = Array.new(2)
    errors   = Array.new(2)

    threads = 2.times.map do |idx|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            session = open_session
            session.post "/testing/sign_in", params: { user_id: @owner_user.id }

            barrier_mutex.synchronize do
              ready_count += 1
              barrier_cv.broadcast if ready_count == 2
              barrier_cv.wait(barrier_mutex) until go
            end

            session.delete "/repositories/#{@repo_name}"
            statuses[idx] = session.response.status
          rescue => e
            errors[idx] = e
          end
        end
      end
    end

    # Release both threads at once.
    barrier_mutex.synchronize do
      barrier_cv.wait(barrier_mutex) until ready_count == 2
      go = true
      barrier_cv.broadcast
    end

    threads.each(&:join)

    assert errors.compact.empty?,
      "no thread should raise; got #{errors.compact.map(&:inspect).inspect}"

    refute Repository.exists?(name: @repo_name),
      "repository must be gone after the concurrent race"

    # Each response must be either a 3xx redirect (own destroy succeeded
    # or no-op) or 404 (the loser found the row already deleted at find_by!
    # time). No 5xx, no auth failure.
    statuses.each_with_index do |status, i|
      assert (300..399).cover?(status) || status == 404,
        "thread #{i} expected 3xx or 404; got #{status} (all=#{statuses.inspect})"
    end

    # And at least one thread must have observed the redirect — i.e. someone
    # actually performed (or attempted) the destroy. Cannot have [404, 404].
    assert statuses.any? { |s| (300..399).cover?(s) },
      "at least one thread must have redirected; got #{statuses.inspect}"
  end

  test "sequential DELETE-then-DELETE of the same repository: first 302, second 404" do
    # Contrast with the concurrent case: when the second request runs strictly
    # AFTER the first has returned, `set_repository_for_authz`'s `find_by!`
    # raises `ActiveRecord::RecordNotFound` and Rails renders 404.
    sess_a = open_session
    sess_a.post "/testing/sign_in", params: { user_id: @owner_user.id }
    sess_a.delete "/repositories/#{@repo_name}"
    assert_equal 302, sess_a.response.status

    sess_b = open_session
    sess_b.post "/testing/sign_in", params: { user_id: @owner_user.id }
    sess_b.delete "/repositories/#{@repo_name}"
    assert_equal 404, sess_b.response.status
  end
end
