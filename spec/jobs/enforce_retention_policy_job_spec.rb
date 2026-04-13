require 'rails_helper'

RSpec.describe EnforceRetentionPolicyJob do
  let(:repo) { Repository.create!(name: 'test-repo') }
  let(:manifest) do
    Manifest.create!(repository: repo, digest: 'sha256:stale', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
                     payload: '{}', size: 100, pull_count: 0, last_pulled_at: 100.days.ago)
  end

  describe '#perform' do
    it 'does nothing when retention is disabled' do
      Tag.create!(repository: repo, manifest: manifest, name: 'old-tag')

      EnforceRetentionPolicyJob.perform_now

      expect(Tag.find_by(name: 'old-tag')).to be_present
    end

    context 'when retention is enabled' do
      around do |example|
        original = ENV.to_h.slice('RETENTION_ENABLED', 'RETENTION_DAYS_WITHOUT_PULL', 'RETENTION_MIN_PULL_COUNT')
        ENV['RETENTION_ENABLED'] = 'true'
        ENV['RETENTION_DAYS_WITHOUT_PULL'] = '90'
        ENV['RETENTION_MIN_PULL_COUNT'] = '5'
        example.run
      ensure
        original.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
      end

      it 'deletes stale tags' do
        Tag.create!(repository: repo, manifest: manifest, name: 'old-tag')

        EnforceRetentionPolicyJob.perform_now

        expect(Tag.find_by(name: 'old-tag')).to be_nil
      end

      it 'protects latest tag by default' do
        Tag.create!(repository: repo, manifest: manifest, name: 'latest')

        EnforceRetentionPolicyJob.perform_now

        expect(Tag.find_by(name: 'latest')).to be_present
      end
    end
  end
end
