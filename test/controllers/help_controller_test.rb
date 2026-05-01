require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "GET /help returns 200 when signed out" do
    get "/help"
    assert_response 200
    assert_includes response.body, Rails.configuration.registry_host
  end

  test "GET /help returns 200 when signed in" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/help"
    assert_response 200
    assert_includes response.body, Rails.configuration.registry_host
  end

  test "GET /help renders the setup guide template" do
    get "/help"
    assert_response 200
    assert_includes response.body, "docker push"
    assert_includes response.body, "Setup Guide"
  end

  # B-40: /help must explain that oprk_ identifies open-repo PATs.
  test "GET /help explains the oprk_ token prefix" do
    get "/help"
    assert_response 200
    assert_includes response.body, "oprk_",
      "expected /help to mention the oprk_ prefix"
    assert_match(/personal access token/i, response.body,
      "expected /help to describe oprk_ as a personal access token prefix")
  end

  # B-37: /help must guide users through PAT generation.
  test "GET /help renders PAT generation guidance" do
    get "/help"
    assert_response :ok
    assert_select "h2", text: /Personal Access Token/i
    assert_select "a[href=?]", "/settings/tokens"
  end

  # B-39: /help must explain the HTTP-vs-HTTPS choice.
  test "GET /help renders HTTP vs HTTPS guidance" do
    get "/help"
    assert_response :ok
    assert_select "h2", text: /HTTP vs HTTPS/i
    assert_select "*", text: /insecure-registries/
  end

  # B-46: /help must walk users from sign-in through docker login.
  test "GET /help shows sign-in to docker-login walkthrough" do
    get "/help"
    assert_response :ok
    assert_select "h2", text: /Sign in.*docker login/i
    assert_select "*", text: /docker login/
  end
end
