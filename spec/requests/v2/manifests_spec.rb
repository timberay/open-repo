require 'rails_helper'

RSpec.describe 'V2 Manifests API', type: :request do
  let(:blob_store) { BlobStore.new }
  let(:repo_name) { 'test-repo' }

  let(:config_content) { File.read(Rails.root.join('spec/fixtures/configs/image_config.json')) }
  let(:config_digest) { DigestCalculator.compute(config_content) }
  let(:layer_content) { SecureRandom.random_bytes(1024) }
  let(:layer_digest) { DigestCalculator.compute(layer_content) }

  let(:manifest_payload) do
    {
      schemaVersion: 2,
      mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
      config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
      layers: [ { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: layer_content.bytesize, digest: layer_digest } ]
    }.to_json
  end

  before do
    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(layer_digest, StringIO.new(layer_content))
    Blob.create!(digest: config_digest, size: config_content.bytesize)
    Blob.create!(digest: layer_digest, size: layer_content.bytesize)
  end

  describe 'PUT /v2/:name/manifests/:reference' do
    it 'creates manifest and tag' do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to start_with('sha256:')
    end

    it 'rejects unsupported media type' do
      put "/v2/#{repo_name}/manifests/v1",
          params: '{}',
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.list.v2+json' }

      expect(response).to have_http_status(415)
      expect(JSON.parse(response.body)['errors'][0]['code']).to eq('UNSUPPORTED')
    end
  end

  describe 'GET /v2/:name/manifests/:reference' do
    before do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }
    end

    it 'returns manifest by tag' do
      get "/v2/#{repo_name}/manifests/v1.0.0"

      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to start_with('sha256:')
      expect(response.headers['Content-Type']).to eq('application/vnd.docker.distribution.manifest.v2+json')
      expect(JSON.parse(response.body)['schemaVersion']).to eq(2)
    end

    it 'returns manifest by digest' do
      digest = response.headers['Docker-Content-Digest']
      get "/v2/#{repo_name}/manifests/#{digest}"
      expect(response).to have_http_status(200)
    end

    it 'increments pull_count on GET' do
      get "/v2/#{repo_name}/manifests/v1.0.0"
      manifest = Manifest.last
      expect(manifest.pull_count).to eq(1)
    end

    it 'creates a PullEvent on GET' do
      get "/v2/#{repo_name}/manifests/v1.0.0"
      expect(PullEvent.count).to eq(1)
      expect(PullEvent.last.tag_name).to eq('v1.0.0')
    end

    it 'returns 404 for unknown tag' do
      get "/v2/#{repo_name}/manifests/nonexistent"
      expect(response).to have_http_status(404)
    end
  end

  describe 'HEAD /v2/:name/manifests/:reference' do
    before do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }
    end

    it 'returns headers without body' do
      head "/v2/#{repo_name}/manifests/v1.0.0"

      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to start_with('sha256:')
      expect(response.body).to be_empty
    end

    it 'does NOT increment pull_count' do
      head "/v2/#{repo_name}/manifests/v1.0.0"
      manifest = Manifest.last
      expect(manifest.pull_count).to eq(0)
    end
  end

  describe 'DELETE /v2/:name/manifests/:digest' do
    before do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }
    end

    it 'deletes manifest and associated tags' do
      digest = Manifest.last.digest
      delete "/v2/#{repo_name}/manifests/#{digest}"

      expect(response).to have_http_status(202)
      expect(Manifest.find_by(digest: digest)).to be_nil
      expect(Tag.count).to eq(0)
    end
  end

  describe 'DELETE /v2/:name/manifests/:reference (tag protection)' do
    let!(:repo) { Repository.create!(name: 'example') }
    let!(:manifest) do
      repo.manifests.create!(
        digest: 'sha256:abc',
        media_type: 'application/vnd.docker.distribution.manifest.v2+json',
        payload: '{}', size: 2
      )
    end
    let!(:tag) { repo.tags.create!(name: 'v1.0.0', manifest: manifest) }

    context 'when any connected tag is protected' do
      before { repo.update!(tag_protection_policy: 'semver') }

      it 'returns 409 Conflict with DENIED envelope (digest reference)' do
        delete "/v2/#{repo.name}/manifests/#{manifest.digest}"
        expect(response).to have_http_status(:conflict)
        body = JSON.parse(response.body)
        expect(body['errors'].first).to include('code' => 'DENIED')
        expect(body['errors'].first['detail']).to include('tag' => 'v1.0.0', 'policy' => 'semver')
      end

      it 'returns 409 even when called with tag reference (decision 1-B)' do
        delete "/v2/#{repo.name}/manifests/v1.0.0"
        expect(response).to have_http_status(:conflict)
      end

      it 'does NOT destroy the manifest' do
        delete "/v2/#{repo.name}/manifests/#{manifest.digest}"
        expect(Manifest.find_by(id: manifest.id)).to be_present
      end
    end

    context 'when no connected tag is protected' do
      it 'returns 202 Accepted and destroys the manifest' do
        delete "/v2/#{repo.name}/manifests/#{manifest.digest}"
        expect(response).to have_http_status(:accepted)
      end
    end
  end
end
