require "test_helper"

class BlobTest < ActiveSupport::TestCase
  test "validations requires digest and size" do
    blob = Blob.new
    refute blob.valid?
    assert_includes blob.errors[:digest], "can't be blank"
    assert_includes blob.errors[:size], "can't be blank"
  end

  test "validations requires unique digest" do
    Blob.create!(digest: "sha256:abc", size: 1024)
    b2 = Blob.new(digest: "sha256:abc", size: 1024)
    refute b2.valid?
  end

  test "defaults has references_count defaulting to 0" do
    blob = Blob.create!(digest: "sha256:abc", size: 1024)
    assert_equal 0, blob.references_count
  end

  # UC-MODEL-004.e2 — references_count contract used by CleanupOrphanedBlobsJob.
  test "blob created with references_count: 0 is allowed (orphan; reaped by CleanupOrphanedBlobsJob)" do
    blob = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1024, references_count: 0)
    assert blob.persisted?
    assert_equal 0, blob.references_count
  end

  test "scope Blob.where(references_count: 0) returns only zero-ref blobs (cleanup-job query)" do
    orphan_a = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1, references_count: 0)
    orphan_b = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1, references_count: 0)
    referenced = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1, references_count: 3)

    zero_ids = Blob.where(references_count: 0).pluck(:id)

    assert_includes zero_ids, orphan_a.id
    assert_includes zero_ids, orphan_b.id
    refute_includes zero_ids, referenced.id
  end

  # CONTRACT SURPRISE pinned by this test: `decrement!(:references_count)` does
  # NOT clamp at zero. There is no DB CHECK constraint and no model-level
  # validation on `references_count >= 0`. The cleanup job uses
  # `where(references_count: 0)` (strict equality), so a negative count makes
  # the blob *invisible* to the orphan reaper (safe in one direction — no
  # accidental deletion of referenced rows; risky in the other — a row that
  # ended up at -1 due to a bookkeeping bug will leak forever). This test
  # locks in current behavior so a future floor change is observable.
  test "decrement! on references_count goes below zero (no floor)" do
    blob = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1, references_count: 0)

    blob.decrement!(:references_count)
    assert_equal(-1, blob.reload.references_count)

    # And the cleanup-job scope skips it (the canary).
    refute_includes Blob.where(references_count: 0).pluck(:id), blob.id
  end

  test "decrement! is the canonical decrement path and round-trips through the DB" do
    blob = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1, references_count: 3)
    blob.decrement!(:references_count)
    assert_equal 2, blob.reload.references_count
    blob.decrement!(:references_count)
    blob.decrement!(:references_count)
    assert_equal 0, blob.reload.references_count
  end
end
