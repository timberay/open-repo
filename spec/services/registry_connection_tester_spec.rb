require "rails_helper"

RSpec.describe RegistryConnectionTester do
  let(:url) { "https://registry.example.com" }
  let(:username) { "testuser" }
  let(:password) { "testpass" }

  describe ".test" do
    context "when connection succeeds" do
      before do
        stub_request(:get, "#{url}/v2/")
          .to_return(status: 200, body: "", headers: {})
      end

      it "returns successful result" do
        result = described_class.test(url)

        expect(result).to be_success
        expect(result.message).to include("Successfully connected")
        expect(result.response_time).to be_a(Numeric)
      end
    end

    context "when authentication fails" do
      before do
        stub_request(:get, "#{url}/v2/")
          .to_return(status: 401, body: "", headers: {})
      end

      it "returns authentication error" do
        result = described_class.test(url, username: username, password: password)

        expect(result).not_to be_success
        expect(result.message).to include("Authentication failed")
      end
    end

    context "when connection times out" do
      before do
        stub_request(:get, "#{url}/v2/")
          .to_timeout
      end

      it "returns timeout error" do
        result = described_class.test(url, timeout: 1)

        expect(result).not_to be_success
        expect(result.message).to include("Connection failed")
      end
    end

    context "when connection fails" do
      before do
        stub_request(:get, "#{url}/v2/")
          .to_raise(Faraday::ConnectionFailed.new("Failed to open TCP connection"))
      end

      it "returns connection error" do
        result = described_class.test(url)

        expect(result).not_to be_success
        expect(result.message).to include("Connection failed")
      end
    end
  end
end
