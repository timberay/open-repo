require "rails_helper"

RSpec.describe Registry, type: :model do
  describe "validations" do
    it "validates presence of name" do
      registry = Registry.new(url: "https://registry.example.com")
      expect(registry).not_to be_valid
      expect(registry.errors[:name]).to include("can't be blank")
    end

    it "validates uniqueness of name" do
      Registry.create!(name: "Test Registry", url: "https://test.com")
      duplicate = Registry.new(name: "Test Registry", url: "https://other.com")
      expect(duplicate).not_to be_valid
    end

    it "validates presence of url" do
      registry = Registry.new(name: "Test")
      expect(registry).not_to be_valid
      expect(registry.errors[:url]).to include("can't be blank")
    end

    it "validates url format" do
      registry = Registry.new(name: "Test", url: "invalid-url")
      expect(registry).not_to be_valid
      expect(registry.errors[:url]).to include("must be a valid HTTP/HTTPS URL")
    end

    it "accepts valid http url" do
      registry = Registry.new(name: "Test", url: "http://localhost:5000")
      expect(registry).to be_valid
    end

    it "accepts valid https url" do
      registry = Registry.new(name: "Test", url: "https://registry.example.com")
      expect(registry).to be_valid
    end
  end

  describe "default registry behavior" do
    it "ensures only one default registry" do
      first = Registry.create!(name: "First", url: "https://first.com", is_default: true)
      second = Registry.create!(name: "Second", url: "https://second.com", is_default: true)

      expect(Registry.where(is_default: true).count).to eq(1)
      expect(second.reload.is_default).to be true
      expect(first.reload.is_default).to be false
    end
  end

  describe "#display_name" do
    it "returns plain name for regular registries" do
      registry = Registry.new(name: "Production")
      expect(registry.display_name).to eq("Production")
    end
  end

  describe "#connection_status" do
    it "returns :unknown when never connected" do
      registry = Registry.new(last_connected_at: nil)
      expect(registry.connection_status).to eq(:unknown)
    end

    it "returns :connected when recently connected" do
      registry = Registry.new(last_connected_at: 2.minutes.ago)
      expect(registry.connection_status).to eq(:connected)
    end

    it "returns :stale when connection is old" do
      registry = Registry.new(last_connected_at: 10.minutes.ago)
      expect(registry.connection_status).to eq(:stale)
    end
  end

  describe "#connection_status_icon" do
    it "returns ● for connected" do
      registry = Registry.new(last_connected_at: 1.minute.ago)
      expect(registry.connection_status_icon).to eq("●")
    end

    it "returns ◐ for stale" do
      registry = Registry.new(last_connected_at: 10.minutes.ago)
      expect(registry.connection_status_icon).to eq("◐")
    end

    it "returns ○ for unknown" do
      registry = Registry.new(last_connected_at: nil)
      expect(registry.connection_status_icon).to eq("○")
    end
  end

  describe "scopes" do
    before do
      Registry.create!(name: "Active", url: "https://active.com", is_active: true)
      Registry.create!(name: "Inactive", url: "https://inactive.com", is_active: false)
      Registry.create!(name: "Default", url: "https://default.com", is_default: true)
    end

    it "returns only active registries" do
      expect(Registry.active.count).to eq(2)
      expect(Registry.active.pluck(:name)).to include("Active", "Default")
    end

    it "returns default registry" do
      expect(Registry.default.name).to eq("Default")
    end
  end
end
