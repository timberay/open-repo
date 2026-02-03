require "rails_helper"

RSpec.describe MockRegistryService do
  let(:service) { described_class.new }

  describe "#catalog" do
    it "returns mock repositories" do
      result = service.catalog
      expect(result[:repositories]).to be_an(Array)
      expect(result[:repositories]).not_to be_empty
      expect(result[:repositories].first).to be_a(String)
    end

    it "filters repositories by query" do
      result = service.catalog(query: "backend")
      expect(result[:repositories]).to all(include("backend"))
    end

    it "returns repositories without query" do
      result = service.catalog
      expect(result[:repositories].size).to be > 0
    end
  end

  describe "#tags" do
    it "returns tags for a repository" do
      tags = service.tags("app/backend")
      expect(tags).to be_an(Array)
      expect(tags).not_to be_empty
      expect(tags).to all(be_a(String))
    end

    it "returns different tag sets based on repository name" do
      backend_tags = service.tags("app/backend")
      infra_tags = service.tags("infra/nginx")

      expect(backend_tags).not_to eq(infra_tags)
    end
  end

  describe "#manifest" do
    let(:repository_name) { "test/repo" }
    let(:tag) { "latest" }

    it "returns manifest with proper structure" do
      result = service.manifest(repository_name, tag)

      expect(result[:manifest]).to be_a(Hash)
      expect(result[:manifest]["schemaVersion"]).to eq(2)
      expect(result[:manifest]["layers"]).to be_an(Array)
      expect(result[:digest]).to start_with("sha256:")
    end

    it "generates random sizes for layers" do
      result1 = service.manifest(repository_name, tag)
      result2 = service.manifest(repository_name, tag)

      expect(result1[:digest]).not_to eq(result2[:digest])
    end
  end
end
