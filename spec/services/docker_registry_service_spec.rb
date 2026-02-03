require "rails_helper"

RSpec.describe DockerRegistryService do
  let(:url) { "https://registry.example.com" }
  let(:username) { "testuser" }
  let(:password) { "testpass" }
  let(:service) { described_class.new(url: url, username: username, password: password) }

  describe "#catalog" do
    let(:catalog_response) do
      {
        "repositories" => [ "repo1", "repo2", "repo3" ]
      }.to_json
    end

    before do
      stub_request(:get, "#{url}/v2/_catalog")
        .with(query: { n: 100 })
        .to_return(status: 200, body: catalog_response, headers: { "Content-Type" => "application/json" })
    end

    before do
      stub_request(:get, "#{url}/v2/_catalog")
        .with(query: hash_including(n: 100))
        .to_return(status: 200, body: catalog_response, headers: { "Content-Type" => "application/json" })
    end

    it "returns list of repositories" do
      result = service.catalog
      expect(result[:repositories]).to eq([ "repo1", "repo2", "repo3" ])
    end

    it "filters repositories by query" do
      result = service.catalog(query: "repo1")
      expect(result[:repositories]).to eq([ "repo1" ])
    end

    context "when authentication fails" do
      before do
        stub_request(:get, "#{url}/v2/_catalog")
          .with(query: { n: 100 })
          .to_return(status: 401, body: "", headers: {})
      end

      it "raises AuthenticationError" do
        expect { service.catalog }.to raise_error(DockerRegistryService::AuthenticationError)
      end
    end
  end

  describe "#tags" do
    let(:repository_name) { "test/repo" }
    let(:tags_response) do
      {
        "name" => repository_name,
        "tags" => [ "latest", "v1.0.0", "v2.0.0" ]
      }.to_json
    end

    before do
      stub_request(:get, "#{url}/v2/#{repository_name}/tags/list")
        .to_return(status: 200, body: tags_response, headers: { "Content-Type" => "application/json" })
    end

    it "returns list of tags" do
      tags = service.tags(repository_name)
      expect(tags).to eq([ "latest", "v1.0.0", "v2.0.0" ])
    end

    context "when repository not found" do
      before do
        stub_request(:get, "#{url}/v2/#{repository_name}/tags/list")
          .to_return(status: 404)
      end

      it "raises NotFoundError" do
        expect { service.tags(repository_name) }.to raise_error(DockerRegistryService::NotFoundError)
      end
    end
  end

  describe "#manifest" do
    let(:repository_name) { "test/repo" }
    let(:tag) { "latest" }
    let(:manifest_response) do
      {
        "schemaVersion" => 2,
        "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
        "config" => { "size" => 1234 },
        "layers" => [ { "size" => 5678 } ]
      }.to_json
    end
    let(:digest) { "sha256:abcdef123456" }

    before do
      stub_request(:get, "#{url}/v2/#{repository_name}/manifests/#{tag}")
        .to_return(
          status: 200,
          body: manifest_response,
          headers: {
            "Content-Type" => "application/vnd.docker.distribution.manifest.v2+json",
            "Docker-Content-Digest" => digest
          }
        )
    end

    it "returns manifest data and digest" do
      result = service.manifest(repository_name, tag)
      expect(result[:manifest]).to be_a(Hash)
      expect(result[:digest]).to eq(digest)
    end
  end
end
