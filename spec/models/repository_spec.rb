require "rails_helper"

RSpec.describe Repository do
  describe ".from_catalog" do
    let(:catalog_data) { [ "repo1", "repo2", "repo3" ] }

    it "creates Repository instances from catalog data" do
      repositories = described_class.from_catalog(catalog_data)

      expect(repositories).to all(be_a(Repository))
      expect(repositories.map(&:name)).to eq(catalog_data)
    end
  end

  describe "#to_param" do
    let(:repository) { described_class.new(name: "test/repo") }

    it "returns the repository name" do
      expect(repository.to_param).to eq("test/repo")
    end
  end

  describe "attributes" do
    it "has name attribute" do
      repository = described_class.new(name: "test/repo")
      expect(repository.name).to eq("test/repo")
    end

    it "has tag_count attribute with default value" do
      repository = described_class.new
      expect(repository.tag_count).to eq(0)
    end

    it "has last_updated attribute" do
      time = Time.current
      repository = described_class.new(last_updated: time)
      expect(repository.last_updated).to eq(time)
    end
  end
end
