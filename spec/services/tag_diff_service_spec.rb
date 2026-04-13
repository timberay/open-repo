require 'rails_helper'

RSpec.describe TagDiffService do
  let(:repo) { Repository.create!(name: 'test-repo') }
  let(:shared_blob) { Blob.create!(digest: 'sha256:shared', size: 1024) }
  let(:old_blob) { Blob.create!(digest: 'sha256:old', size: 512) }
  let(:new_blob) { Blob.create!(digest: 'sha256:new', size: 2048) }

  let(:manifest_a) do
    m = Manifest.create!(repository: repo, digest: 'sha256:ma', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
                         payload: '{}', size: 100, docker_config: '{"Cmd":["/bin/sh"]}', architecture: 'amd64', os: 'linux')
    Layer.create!(manifest: m, blob: shared_blob, position: 0)
    Layer.create!(manifest: m, blob: old_blob, position: 1)
    m
  end

  let(:manifest_b) do
    m = Manifest.create!(repository: repo, digest: 'sha256:mb', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
                         payload: '{}', size: 100, docker_config: '{"Cmd":["/bin/bash"]}', architecture: 'amd64', os: 'linux')
    Layer.create!(manifest: m, blob: shared_blob, position: 0)
    Layer.create!(manifest: m, blob: new_blob, position: 1)
    m
  end

  describe '#call' do
    it 'identifies common, added, and removed layers' do
      result = TagDiffService.new.call(manifest_a, manifest_b)

      expect(result[:common_layers]).to include('sha256:shared')
      expect(result[:removed_layers]).to include('sha256:old')
      expect(result[:added_layers]).to include('sha256:new')
    end

    it 'computes size delta' do
      result = TagDiffService.new.call(manifest_a, manifest_b)
      expect(result[:size_delta]).to eq(2048 - 512)
    end

    it 'computes config diff' do
      result = TagDiffService.new.call(manifest_a, manifest_b)
      expect(result[:config_diff]).to be_a(Hash)
    end
  end
end
