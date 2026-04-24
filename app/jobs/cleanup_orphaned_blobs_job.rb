class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    cleanup_orphaned_blobs
    cleanup_orphaned_manifests
    blob_store.cleanup_stale_uploads(max_age: 1.hour)
  end

  private

  def cleanup_orphaned_blobs
    Blob.where(references_count: 0).find_each(batch_size: BATCH_SIZE) do |blob|
      blob.reload
      next if blob.references_count > 0

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
