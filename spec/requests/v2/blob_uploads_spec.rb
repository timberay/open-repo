require 'rails_helper'

RSpec.describe 'V2 Blob Uploads API', type: :request do
  let(:repo_name) { 'test-repo' }

  describe 'POST /v2/:name/blobs/uploads (start upload)' do
    it 'returns 202 with Location and upload UUID' do
      post "/v2/#{repo_name}/blobs/uploads"

      expect(response).to have_http_status(202)
      expect(response.headers['Location']).to match(%r{/v2/#{repo_name}/blobs/uploads/.+})
      expect(response.headers['Docker-Upload-UUID']).to be_present
      expect(response.headers['Range']).to eq('0-0')
    end

    it 'creates repository if not exists' do
      post "/v2/#{repo_name}/blobs/uploads"
      expect(Repository.find_by(name: repo_name)).to be_present
    end
  end

  describe 'POST /v2/:name/blobs/uploads?digest= (monolithic upload)' do
    it 'stores blob in single request' do
      content = 'monolithic blob data'
      digest = DigestCalculator.compute(content)

      post "/v2/#{repo_name}/blobs/uploads?digest=#{digest}",
           params: content,
           headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
    end
  end

  describe 'PATCH /v2/:name/blobs/uploads/:uuid (chunk upload)' do
    it 'appends data and returns updated range' do
      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
            params: 'chunk data',
            headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      expect(response).to have_http_status(202)
      expect(response.headers['Range']).to eq('0-9')
      expect(response.headers['Docker-Upload-UUID']).to eq(uuid)
    end
  end

  describe 'PUT /v2/:name/blobs/uploads/:uuid?digest= (complete upload)' do
    it 'finalizes upload and creates blob record' do
      content = 'final blob content'
      digest = DigestCalculator.compute(content)

      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
            params: content,
            headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      put "/v2/#{repo_name}/blobs/uploads/#{uuid}?digest=#{digest}"

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
      expect(Blob.find_by(digest: digest)).to be_present
    end

    it 'rejects wrong digest' do
      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
            params: 'some data',
            headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      put "/v2/#{repo_name}/blobs/uploads/#{uuid}?digest=sha256:wrong"

      expect(response).to have_http_status(400)
      expect(JSON.parse(response.body)['errors'][0]['code']).to eq('DIGEST_INVALID')
    end
  end

  describe 'POST /v2/:name/blobs/uploads?mount=&from= (cross-repo mount)' do
    it 'mounts existing blob from another repo' do
      content = 'shared layer'
      digest = DigestCalculator.compute(content)
      Repository.create!(name: 'source-repo')
      Blob.create!(digest: digest, size: content.bytesize)
      BlobStore.new.put(digest, StringIO.new(content))

      post "/v2/#{repo_name}/blobs/uploads?mount=#{digest}&from=source-repo"

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
    end

    it 'falls back to regular upload if blob not found' do
      post "/v2/#{repo_name}/blobs/uploads?mount=sha256:nonexistent&from=other-repo"

      expect(response).to have_http_status(202)
      expect(response.headers['Docker-Upload-UUID']).to be_present
    end
  end

  describe 'DELETE /v2/:name/blobs/uploads/:uuid' do
    it 'cancels upload' do
      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      delete "/v2/#{repo_name}/blobs/uploads/#{uuid}"
      expect(response).to have_http_status(204)
      expect(BlobUpload.find_by(uuid: uuid)).to be_nil
    end
  end
end
