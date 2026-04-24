require "test_helper"

class PruneOldEventsJobTest < ActiveJob::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    @repo = Repository.create!(name: "prune-test-repo", owner_identity: identities(:tonny_google))
    @manifest = Manifest.create!(
      repository: @repo,
      digest: "sha256:prune-test",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100,
      pull_count: 0,
      last_pulled_at: nil
    )
  end

  def teardown
    travel_back
  end

  # --- boundary cases (UC-JOB-003 .e1) ---

  test "event exactly 90 days old is NOT deleted (strict <)" do
    freeze_time do
      event = create_pull_event(occurred_at: 90.days.ago)

      PruneOldEventsJob.perform_now

      assert PullEvent.exists?(event.id), "event exactly at the 90-day boundary should be preserved"
    end
  end

  test "event 91 days old IS deleted" do
    freeze_time do
      event = create_pull_event(occurred_at: 91.days.ago)

      PruneOldEventsJob.perform_now

      assert_not PullEvent.exists?(event.id), "event older than 90 days should be pruned"
    end
  end

  test "event created today is NOT deleted" do
    freeze_time do
      event = create_pull_event(occurred_at: Time.current)

      PruneOldEventsJob.perform_now

      assert PullEvent.exists?(event.id), "recent event must not be pruned"
    end
  end

  # --- mixed dataset ---

  test "prunes only old events, leaves new ones intact" do
    freeze_time do
      old_event_a = create_pull_event(occurred_at: 100.days.ago)
      old_event_b = create_pull_event(occurred_at: 91.days.ago)
      boundary_event = create_pull_event(occurred_at: 90.days.ago)
      fresh_event   = create_pull_event(occurred_at: 1.day.ago)

      assert_difference -> { PullEvent.count }, -2 do
        PruneOldEventsJob.perform_now
      end

      assert_not PullEvent.exists?(old_event_a.id)
      assert_not PullEvent.exists?(old_event_b.id)
      assert PullEvent.exists?(boundary_event.id)
      assert PullEvent.exists?(fresh_event.id)
    end
  end

  # --- empty dataset (UC-JOB-003 .e2) ---

  test "no-op when there are no events" do
    freeze_time do
      assert_equal 0, PullEvent.count

      assert_nothing_raised do
        PruneOldEventsJob.perform_now
      end

      assert_equal 0, PullEvent.count
    end
  end

  # --- batching boundary (UC-JOB-003 .e3) ---
  #
  # The job uses `in_batches.delete_all` (default batch size: 1000). Verify no
  # row is skipped across batch boundaries when the matched set spans multiple
  # batches. We insert 1,050 old rows via `insert_all` so traversal must cross
  # at least one 1000-row batch boundary, plus a handful of fresh rows that
  # must survive.

  test "batched delete removes every old row across batch boundaries" do
    freeze_time do
      old_rows = Array.new(1_050) do
        {
          manifest_id: @manifest.id,
          repository_id: @repo.id,
          occurred_at: 120.days.ago,
          tag_name: "latest"
        }
      end
      PullEvent.insert_all!(old_rows)
      old_ids = PullEvent.where("occurred_at < ?", 90.days.ago).pluck(:id)
      fresh_ids = Array.new(3) { create_pull_event(occurred_at: 2.days.ago).id }

      assert_equal 1_050, old_ids.size, "sanity: seeded 1,050 old rows (>1 default batch)"

      PruneOldEventsJob.perform_now

      assert_equal 0, PullEvent.where(id: old_ids).count,
                   "all old rows must be deleted regardless of batch boundaries"
      assert_equal fresh_ids.size, PullEvent.where(id: fresh_ids).count,
                   "fresh rows must survive batched traversal"
    end
  end

  private

  def create_pull_event(occurred_at:)
    PullEvent.create!(
      manifest: @manifest,
      repository: @repo,
      occurred_at: occurred_at,
      tag_name: "latest"
    )
  end
end
