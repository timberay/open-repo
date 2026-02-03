require "rails_helper"

RSpec.describe LocalRegistryScanner do
  describe "#scan" do
    let(:scanner) { described_class.new(ports: [ 5000, 5001 ], timeout: 1) }

    context "when local registries are found" do
      before do
        stub_request(:get, "http://localhost:5000/v2/")
          .to_return(status: 200, body: "", headers: {})
        stub_request(:get, "http://localhost:5001/v2/")
          .to_timeout
      end

      it "returns discovered registries" do
        results = scanner.scan

        expect(results).to be_an(Array)
        expect(results.size).to eq(1)
        expect(results.first[:name]).to eq("Local Registry (5000)")
        expect(results.first[:url]).to eq("http://localhost:5000")
        expect(results.first[:port]).to eq(5000)
      end
    end

    context "when no registries are found" do
      before do
        stub_request(:get, /localhost:\d+\/v2\//)
          .to_timeout
      end

      it "returns empty array" do
        results = scanner.scan
        expect(results).to be_empty
      end
    end
  end

  describe "#scan_and_register!" do
    let(:scanner) { described_class.new(ports: [ 5000 ], timeout: 1) }

    before do
      stub_request(:get, "http://localhost:5000/v2/")
        .to_return(status: 200, body: "", headers: {})
    end

    it "creates new registry for discovered local registry" do
      expect {
        scanner.scan_and_register!
      }.to change(Registry, :count).by(1)

      registry = Registry.last
      expect(registry.name).to eq("Local Registry (5000)")
      expect(registry.url).to eq("http://localhost:5000")
    end

    it "does not create duplicate registries" do
      Registry.create!(name: "Existing", url: "http://localhost:5000")

      expect {
        scanner.scan_and_register!
      }.not_to change(Registry, :count)
    end

    it "returns count of discovered registries" do
      count = scanner.scan_and_register!
      expect(count).to eq(1)
    end
  end
end
