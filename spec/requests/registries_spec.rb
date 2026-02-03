require "rails_helper"

RSpec.describe "Registries", type: :request do
  let!(:registry) { Registry.create!(name: "Test Registry", url: "https://test.com") }

  describe "GET /registries" do
    it "returns http success" do
      get registries_path
      expect(response).to have_http_status(:success)
    end

    it "displays registry list" do
      get registries_path
      expect(response.body).to include("Registry Management")
      expect(response.body).to include("Test Registry")
    end
  end

  describe "GET /registries/new" do
    it "returns http success" do
      get new_registry_path
      expect(response).to have_http_status(:success)
    end

    it "displays form" do
      get new_registry_path
      expect(response.body).to include("Add New Registry")
    end
  end

  describe "POST /registries" do
    let(:valid_params) do
      { registry: { name: "New Registry", url: "https://new.com" } }
    end

    it "creates a new registry" do
      expect {
        post registries_path, params: valid_params
      }.to change(Registry, :count).by(1)
    end

    it "redirects to index after creation" do
      post registries_path, params: valid_params
      expect(response).to redirect_to(registries_path)
    end
  end

  describe "GET /registries/:id/edit" do
    it "returns http success" do
      get edit_registry_path(registry)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /registries/:id" do
    it "updates the registry" do
      patch registry_path(registry), params: { registry: { name: "Updated Name" } }
      expect(registry.reload.name).to eq("Updated Name")
    end
  end

  describe "DELETE /registries/:id" do
    it "destroys the registry" do
      expect {
        delete registry_path(registry)
      }.to change(Registry, :count).by(-1)
    end
  end

  describe "POST /registries/:id/switch" do
    it "sets current registry in session" do
      post switch_registry_path(registry)
      expect(session[:current_registry_id]).to eq(registry.id)
    end

    it "redirects to root" do
      post switch_registry_path(registry)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /registries/:id/test_connection" do
    before do
      stub_request(:get, "#{registry.url}/v2/")
        .to_return(status: 200, body: "", headers: {})
    end

    it "returns json response" do
      post test_connection_registry_path(registry), as: :json
      expect(response.content_type).to include("application/json")
    end

    it "returns success when connection works" do
      post test_connection_registry_path(registry), as: :json
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
    end

    it "updates last_connected_at on success" do
      expect {
        post test_connection_registry_path(registry), as: :json
      }.to change { registry.reload.last_connected_at }
    end
  end
end
