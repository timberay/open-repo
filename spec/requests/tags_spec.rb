require 'rails_helper'

RSpec.describe 'Tags', type: :request do
  let!(:repo) { Repository.create!(name: 'example') }
  let!(:manifest) do
    repo.manifests.create!(
      digest: 'sha256:abc',
      media_type: 'application/vnd.docker.distribution.manifest.v2+json',
      payload: '{}', size: 2
    )
  end
  let!(:tag) { repo.tags.create!(name: 'v1.0.0', manifest: manifest) }

  describe 'GET /repositories/:name/tags/:name' do
    let!(:blob) { Blob.create!(digest: 'sha256:1d1ddb624e47aabbccddeeff0011223344556677', size: 4096) }
    let!(:layer) { Layer.create!(manifest: manifest, blob: blob, position: 0) }

    it 'renders each layer digest with a click-to-copy affordance carrying the full digest' do
      get "/repositories/#{repo.name}/tags/#{tag.name}"

      expect(response).to be_successful
      # Both the desktop grid cell and the mobile card render the component,
      # so the clipboard wiring should appear twice for a single layer.
      expect(response.body.scan("data-clipboard-text-value=\"#{blob.digest}\"").size).to eq(2)
      expect(response.body.scan(%r{aria-label="Copy digest 1d1ddb624e47"}).size).to eq(2)
    end
  end

  describe 'DELETE /repositories/:name/tags/:name' do
    context 'when tag is not protected' do
      it 'deletes the tag and redirects' do
        delete "/repositories/#{repo.name}/tags/#{tag.name}"
        expect(response).to redirect_to(repository_path(repo.name))
        expect(Tag.find_by(id: tag.id)).to be_nil
      end
    end

    context 'when tag is protected by semver policy' do
      before { repo.update!(tag_protection_policy: 'semver') }

      it 'does NOT delete the tag' do
        delete "/repositories/#{repo.name}/tags/#{tag.name}"
        expect(Tag.find_by(id: tag.id)).to be_present
      end

      it 'redirects to the repository page with a flash error' do
        delete "/repositories/#{repo.name}/tags/#{tag.name}"
        expect(response).to redirect_to(repository_path(repo.name))
        expect(flash[:alert]).to include("protected")
        expect(flash[:alert]).to include("semver")
      end

      it 'does NOT record a tag_event' do
        expect {
          delete "/repositories/#{repo.name}/tags/#{tag.name}"
        }.not_to change { TagEvent.count }
      end
    end
  end
end
