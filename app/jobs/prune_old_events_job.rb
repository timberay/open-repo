class PruneOldEventsJob < ApplicationJob
  queue_as :default

  def perform
    PullEvent.where('occurred_at < ?', 90.days.ago).in_batches.delete_all
  end
end
