require "test_helper"

class V2::CatalogControllerTest < ActionDispatch::IntegrationTest
  setup do
    %w[alpha bravo charlie].each { |n| Repository.create!(name: n, owner_identity: identities(:tonny_google)) }
  end

  test "GET /v2/_catalog returns all repositories" do
    get "/v2/_catalog"
    assert_response 200
    body = JSON.parse(response.body)
    assert_equal %w[alpha bravo charlie], body["repositories"]
  end

  test "GET /v2/_catalog paginates with n and last" do
    get "/v2/_catalog?n=2"
    body = JSON.parse(response.body)
    assert_equal %w[alpha bravo], body["repositories"]
    assert_includes response.headers["Link"], "rel=\"next\""

    get "/v2/_catalog?n=2&last=bravo"
    body = JSON.parse(response.body)
    assert_equal %w[charlie], body["repositories"]
    assert_nil response.headers["Link"]
  end
end
