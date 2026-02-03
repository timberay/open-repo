require "rails_helper"

RSpec.describe Tag do
  describe ".from_manifest" do
    let(:tag_name) { "v1.0.0" }
    let(:manifest_data) do
      {
        "schemaVersion" => 2,
        "layers" => [
          { "size" => 1000 },
          { "size" => 2000 }
        ]
      }
    end
    let(:digest) { "sha256:abcdef123456" }

    it "creates Tag instance with calculated size" do
      tag = described_class.from_manifest(tag_name, manifest_data, digest)

      expect(tag.name).to eq(tag_name)
      expect(tag.digest).to eq(digest)
      expect(tag.size).to eq(3000)
    end

    it "handles manifest without layers" do
      tag = described_class.from_manifest(tag_name, {}, digest)
      expect(tag.size).to eq(0)
    end
  end

  describe "#pull_command" do
    let(:tag) { described_class.new(name: "latest") }

    it "returns correct docker pull command" do
      command = tag.pull_command("registry.example.com", "myrepo")
      expect(command).to eq("docker pull registry.example.com/myrepo:latest")
    end
  end

  describe "#short_digest" do
    it "returns first 12 characters of digest hash" do
      tag = described_class.new(digest: "sha256:abcdef1234567890")
      expect(tag.short_digest).to eq("abcdef123456")
    end

    it "returns nil when digest is nil" do
      tag = described_class.new(digest: nil)
      expect(tag.short_digest).to be_nil
    end
  end

  describe "#human_size" do
    it "returns size in bytes" do
      tag = described_class.new(size: 500)
      expect(tag.human_size).to eq("500.0 B")
    end

    it "returns size in KB" do
      tag = described_class.new(size: 2048)
      expect(tag.human_size).to eq("2.0 KB")
    end

    it "returns size in MB" do
      tag = described_class.new(size: 5_242_880)
      expect(tag.human_size).to eq("5.0 MB")
    end

    it "returns size in GB" do
      tag = described_class.new(size: 2_147_483_648)
      expect(tag.human_size).to eq("2.0 GB")
    end

    it "returns N/A for nil size" do
      tag = described_class.new(size: nil)
      expect(tag.human_size).to eq("N/A")
    end

    it "returns N/A for zero size" do
      tag = described_class.new(size: 0)
      expect(tag.human_size).to eq("N/A")
    end
  end
end
