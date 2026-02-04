require "rails_helper"

RSpec.describe RegistryHealthCheckService do
  describe ".check_all!" do
    let!(:active_registry) { Registry.create!(name: "Active", url: "http://localhost:5000", is_active: true) }
    let!(:unreachable_registry) { Registry.create!(name: "Unreachable", url: "http://localhost:5001", is_active: true) }

    before do
      allow(RegistryConnectionTester).to receive(:test).with(active_registry.url, any_args).and_return(
        RegistryConnectionTester::ConnectionTestResult.new(success: true, message: "Success", response_time: 10)
      )
      allow(RegistryConnectionTester).to receive(:test).with(unreachable_registry.url, any_args).and_return(
        RegistryConnectionTester::ConnectionTestResult.new(success: false, message: "Failed")
      )
    end

    it "updates status for all registries" do
      described_class.check_all!

      expect(active_registry.reload.is_active).to be true
      expect(active_registry.last_connected_at).to be_within(1.second).of(Time.current)

      expect(unreachable_registry.reload.is_active).to be false
    end

    it "logs warnings for unreachable registries" do
      expect(Rails.logger).to receive(:warn).with(/Unreachable.*Marked as inactive/)
      described_class.check_all!
    end
  end
end
