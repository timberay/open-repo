require 'rails_helper'

RSpec.describe 'V2 Blobs API', type: :request do
  let(:blob_store) { BlobStore.new }
  let(:repo_name) { 'test-repo' }
  let(:content) { 'blob content data' }
  let(:digest) { DigestCalculator.compute(content) }

  before do
    Repository.create!(name: repo_name)
    Blob.create!(digest: digest, size: content.bytesize)
    blob_store.put(digest, StringIO.new(content))
  end

  describe 'GET /v2/:name/blobs/:digest' do
    it 'returns blob content' do
      get "/v2/#{repo_name}/blobs/#{digest}"
      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
      expect(response.headers['Content-Length']).to eq(content.bytesize.to_s)
    end

    it 'returns 404 for unknown digest' do
      get "/v2/#{repo_name}/blobs/sha256:nonexistent"
      expect(response).to have_http_status(404)
    end
  end

  describe 'HEAD /v2/:name/blobs/:digest' do
    it 'returns headers without body' do
      head "/v2/#{repo_name}/blobs/#{digest}"
      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
      expect(response.body).to be_empty
    end
  end

  describe 'DELETE /v2/:name/blobs/:digest' do
    it 'deletes blob' do
      delete "/v2/#{repo_name}/blobs/#{digest}"
      expect(response).to have_http_status(202)
    end
  end
end
