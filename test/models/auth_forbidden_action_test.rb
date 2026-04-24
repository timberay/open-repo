require "test_helper"

class AuthForbiddenActionTest < ActiveSupport::TestCase
  test "ForbiddenAction carries repository and action" do
    repo = Repository.create!(name: "forbidden-test-#{SecureRandom.hex(4)}", owner_identity: identities(:tonny_google))
    err = Auth::ForbiddenAction.new(repository: repo, action: :write)
    assert_equal repo, err.repository
    assert_equal :write, err.action
    assert_match(/forbidden/, err.message)
    assert_match(/write/, err.message)
    assert_match(repo.name, err.message)
  end

  test "ForbiddenAction is a subclass of Auth::Error" do
    assert Auth::ForbiddenAction < Auth::Error
  end
end
