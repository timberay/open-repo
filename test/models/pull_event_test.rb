require "test_helper"

class PullEventTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
  end

  def manifest
    @manifest ||= Manifest.create!(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
  end

  test "validations requires occurred_at" do
    event = PullEvent.new(manifest: manifest, repository: repository)
    refute event.valid?
    assert_includes event.errors[:occurred_at], "can't be blank"
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-005 .e3: pull history ordering
  #
  # `occurred_at` is the source-of-truth for ordering pull history, NOT
  # `created_at`. Insertion order can diverge from occurred_at when rows are
  # backfilled or written out-of-sequence; the index `index_pull_events_on_*_occurred_at`
  # exists precisely so ordered queries hit it.
  #
  # Pruning boundary (UC-MODEL-005 .e2 / UC-JOB-003 .e1): the 90-day strict-`<`
  # boundary for PruneOldEventsJob is already covered in
  # test/jobs/prune_old_events_job_test.rb (3 boundary tests + a mixed
  # dataset). Not duplicated here.
  # ---------------------------------------------------------------------------

  test "order(occurred_at: :desc) honours occurred_at, not insertion / created_at order" do
    base = Time.current.change(usec: 0)

    # Insert oldest occurred_at FIRST, then newest, then middle — so
    # auto-incrementing PK / insertion order does NOT match occurred_at order.
    oldest = PullEvent.create!(
      manifest: manifest, repository: repository, occurred_at: base - 2.days, tag_name: "latest"
    )
    newest = PullEvent.create!(
      manifest: manifest, repository: repository, occurred_at: base, tag_name: "latest"
    )
    middle = PullEvent.create!(
      manifest: manifest, repository: repository, occurred_at: base - 1.day, tag_name: "latest"
    )

    ordered_ids = PullEvent.where(repository: repository).order(occurred_at: :desc).pluck(:id)
    assert_equal [ newest.id, middle.id, oldest.id ], ordered_ids,
                 "PullEvent ordering must use occurred_at, not insertion / created_at order"
  end
end
