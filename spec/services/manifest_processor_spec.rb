require 'rails_helper'

RSpec.describe ManifestProcessor do
  let(:store_dir) { Dir.mktmpdir }
  let(:blob_store) { BlobStore.new(store_dir) }
  let(:processor) { ManifestProcessor.new(blob_store) }

  after { FileUtils.rm_rf(store_dir) }

  let(:config_content) { File.read(Rails.root.join('spec/fixtures/configs/image_config.json')) }
  let(:config_digest) { DigestCalculator.compute(config_content) }

  let(:layer1_content) { SecureRandom.random_bytes(1024) }
  let(:layer1_digest) { DigestCalculator.compute(layer1_content) }

  let(:layer2_content) { SecureRandom.random_bytes(2048) }
  let(:layer2_digest) { DigestCalculator.compute(layer2_content) }

  let(:manifest_json) do
    {
      schemaVersion: 2,
      mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
      config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
      layers: [
        { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: layer1_content.bytesize, digest: layer1_digest },
        { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: layer2_content.bytesize, digest: layer2_digest }
      ]
    }.to_json
  end

  before do
    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(layer1_digest, StringIO.new(layer1_content))
    blob_store.put(layer2_digest, StringIO.new(layer2_content))
  end

  describe '#call' do
    it 'creates repository, manifest, tag, layers, and blobs' do
      result = processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)

      expect(result).to be_a(Manifest)
      expect(Repository.find_by(name: 'test-repo')).to be_present
      expect(Tag.find_by(name: 'v1.0.0')).to be_present
      expect(result.layers.count).to eq(2)
      expect(result.architecture).to eq('amd64')
      expect(result.os).to eq('linux')
      expect(result.docker_config).to include('Cmd')
    end

    it 'creates a tag_event on new tag' do
      processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)

      event = TagEvent.last
      expect(event.action).to eq('create')
      expect(event.tag_name).to eq('v1.0.0')
      expect(event.previous_digest).to be_nil
    end

    it 'creates an update tag_event when tag is reassigned' do
      result1 = processor.call('test-repo', 'latest', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
      old_digest = result1.digest

      # Push a different manifest to same tag
      new_layer = SecureRandom.random_bytes(512)
      new_layer_digest = DigestCalculator.compute(new_layer)
      blob_store.put(new_layer_digest, StringIO.new(new_layer))

      new_manifest_json = {
        schemaVersion: 2,
        mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
        config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
        layers: [
          { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: new_layer.bytesize, digest: new_layer_digest }
        ]
      }.to_json

      processor.call('test-repo', 'latest', 'application/vnd.docker.distribution.manifest.v2+json', new_manifest_json)

      event = TagEvent.where(action: 'update').last
      expect(event.previous_digest).to eq(old_digest)
    end

    it 'raises ManifestInvalid for missing referenced blob' do
      bad_json = {
        schemaVersion: 2,
        mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
        config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: 100, digest: 'sha256:nonexistent' },
        layers: []
      }.to_json

      expect {
        processor.call('test-repo', 'v1', 'application/vnd.docker.distribution.manifest.v2+json', bad_json)
      }.to raise_error(Registry::ManifestInvalid, /config blob not found/)
    end

    it 'handles digest reference instead of tag name' do
      result = processor.call('test-repo', nil, 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
      expect(result).to be_a(Manifest)
      expect(Tag.count).to eq(0)
    end

    it 'increments blob references_count' do
      processor.call('test-repo', 'v1', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)

      layer1_blob = Blob.find_by(digest: layer1_digest)
      expect(layer1_blob.references_count).to eq(1)
    end
  end

  describe '#call with tag protection' do
    let!(:repo) do
      # Create with initial manifest and tag, then turn on protection.
      r = Repository.create!(name: 'test-repo')
      processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
      r.update!(tag_protection_policy: 'semver')
      r.reload
    end

    context 'same digest re-push (idempotent)' do
      it 'succeeds' do
        expect {
          processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
        }.not_to raise_error
      end
    end

    context 'different digest push on protected tag' do
      let(:different_manifest_json) do
        new_layer = SecureRandom.random_bytes(512)
        new_layer_digest = DigestCalculator.compute(new_layer)
        blob_store.put(new_layer_digest, StringIO.new(new_layer))
        {
          schemaVersion: 2,
          mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
          config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
          layers: [
            { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: new_layer.bytesize, digest: new_layer_digest }
          ]
        }.to_json
      end

      it 'raises Registry::TagProtected' do
        expect {
          processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', different_manifest_json)
        }.to raise_error(Registry::TagProtected)
      end

      # REGRESSION guards for decision 1-A (check at entry, not inside assign_tag!)
      it 'does NOT create a new manifest row' do
        expect {
          begin
            processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', different_manifest_json)
          rescue Registry::TagProtected
          end
        }.not_to change { Manifest.count }
      end

      it 'does NOT increment layer blob references_count' do
        layer_blob = Blob.find_by(digest: layer1_digest)
        before_refs = layer_blob.references_count
        begin
          processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', different_manifest_json)
        rescue Registry::TagProtected
        end
        expect(layer_blob.reload.references_count).to eq(before_refs)
      end
    end

    context 'unprotected tag (latest with semver policy)' do
      it 'permits push (latest not semver)' do
        expect {
          processor.call('test-repo', 'latest', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
        }.not_to raise_error
      end
    end

    context 'digest reference (sha256: prefix, not a tag mutation)' do
      it 'bypasses protection check' do
        r = Repository.find_by!(name: 'test-repo')
        r.update!(tag_protection_policy: 'all_except_latest')
        expect {
          processor.call('test-repo', 'sha256:dummy-ignored-anyway', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
        }.not_to raise_error
      end
    end
  end
end
