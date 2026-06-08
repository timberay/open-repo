class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  # Blobs touched within this window are treated as in-flight pushes: the client
  # has uploaded, cross-repo mounted, HEAD-checked, or re-finalized the blob and
  # is about to PUT the manifest that references it. Deleting them mid-push would
  # fail the push with "layer blob not found". Keyed on updated_at (bumped by
  # every blob access — see BlobsController#show, BlobUploadsController) so a
  # long-lived blob that is briefly unreferenced but re-touched by a fresh push
  # is not reclaimed out from under it. Matches the stale-upload cleanup TTL.
  RECENT_GRACE = 1.hour

  def perform
    cleanup_orphaned_blobs
    cleanup_orphaned_manifests
    blob_store.cleanup_stale_uploads(max_age: 1.hour)
  end

  private

  def cleanup_orphaned_blobs
    # `<= 0` reclaims blobs whose counter drifted negative (over-decrement bug);
    # the referenced? guard ensures a blob any manifest still points to — as a
    # layer OR as the config blob — is never deleted even when its counter is
    # wrong. The counter is an index; real manifest references are the truth.
    Blob.where("references_count <= 0")
        .where("updated_at < ?", RECENT_GRACE.ago)
        .find_each(batch_size: BATCH_SIZE) do |blob|
      blob.reload
      next if blob.references_count > 0
      next if blob.referenced?

      blob_store.delete(blob.digest)
      blob.destroy!
    end
  end

  def cleanup_orphaned_manifests
    Manifest.left_joins(:tags).where(tags: { id: nil }).find_each(batch_size: BATCH_SIZE) do |manifest|
      manifest.layers.each { |layer| layer.blob.decrement!(:references_count) }
      manifest.destroy!
    end
  end

  def blob_store
    @blob_store ||= BlobStore.new
  end
end
