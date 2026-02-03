require "rails_helper"

RSpec.describe "Repositories", type: :request do
  before do
    allow(Rails.application.config).to receive(:use_mock_registry).and_return(true)
  end

  describe "GET /repositories" do
    it "returns http success" do
      get repositories_path
      expect(response).to have_http_status(:success)
    end

    it "displays repository list" do
      get repositories_path
      expect(response.body).to include("Docker Registry")
    end

    it "filters repositories by query parameter" do
      get repositories_path(query: "backend")
      expect(response).to have_http_status(:success)
    end

    it "sorts repositories by name" do
      get repositories_path(sort_by: "name")
      expect(response).to have_http_status(:success)
    end

    context "with turbo_stream format" do
      it "returns turbo_stream response" do
        get repositories_path(format: :turbo_stream)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end
  end

  describe "GET /repositories/:id" do
    let(:repository_name) { "app/backend" }

    it "returns http success" do
      get repository_path(repository_name)
      expect(response).to have_http_status(:success)
    end

    it "displays repository name" do
      get repository_path(repository_name)
      expect(response.body).to include(repository_name)
    end

    it "displays tags table" do
      get repository_path(repository_name)
      expect(response.body).to include("Tag")
      expect(response.body).to include("Digest")
      expect(response.body).to include("Size")
    end
  end
end
