class EnforceRetentionPolicyJob < ApplicationJob
  queue_as :default

  def perform
    return unless retention_enabled?

    days = ENV.fetch('RETENTION_DAYS_WITHOUT_PULL', 90).to_i
    min_pulls = ENV.fetch('RETENTION_MIN_PULL_COUNT', 5).to_i
    protect_latest = ENV.fetch('RETENTION_PROTECT_LATEST', 'true') == 'true'

    threshold = days.days.ago

    stale_manifests = Manifest
      .where('last_pulled_at < ? OR last_pulled_at IS NULL', threshold)
      .where('pull_count < ?', min_pulls)

    stale_manifests.find_each do |manifest|
      scope = manifest.tags
      scope = scope.where.not(name: 'latest') if protect_latest

      scope.find_each do |tag|
        # OV-2 (P0): do not touch tags protected by repo policy.
        next if manifest.repository.tag_protected?(tag.name)

        TagEvent.create!(
          repository: manifest.repository,
          tag_name: tag.name,
          action: 'delete',
          previous_digest: manifest.digest,
          actor: 'retention-policy',
          occurred_at: Time.current
        )
        tag.destroy!
      end
    end
  end

  private

  def retention_enabled?
    ENV.fetch('RETENTION_ENABLED', 'false') == 'true'
  end
end
