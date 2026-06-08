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

  test "GET /v2/_catalog encodes slash-containing last cursor in Link header" do
    Repository.create!(name: "delta/app", owner_identity: identities(:tonny_google))
    Repository.create!(name: "echo", owner_identity: identities(:tonny_google))

    get "/v2/_catalog?n=4"

    assert_response :ok
    assert_equal %w[alpha bravo charlie delta/app], JSON.parse(response.body)["repositories"]
    assert_includes response.headers["Link"], "last=delta%2Fapp"
    assert_includes response.headers["Link"], "rel=\"next\""
  end
end
