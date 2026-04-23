require "test_helper"

# Stub controller that includes the concern so we can unit-test authorize_for!
# without wiring a real route.
class StubAuthzController
  include RepositoryAuthorization

  attr_accessor :current_user, :repository

  def initialize(user: nil, repo: nil)
    @current_user = user
    @repository   = repo
  end
end

class RepositoryAuthorizationTest < ActiveSupport::TestCase
  def owner
    @owner ||= users(:tonny)
  end

  def other_user
    @other_user ||= users(:admin)
  end

  def repo
    @repo ||= Repository.create!(
      name: "authz-test-#{SecureRandom.hex(4)}",
      owner_identity: owner.primary_identity
    )
  end

  def ctrl(user: owner, repository: repo)
    StubAuthzController.new(user: user, repo: repository)
  end

  test "authorize_for!(:write) does not raise for owner" do
    assert_nothing_raised { ctrl.authorize_for!(:write) }
  end

  test "authorize_for!(:write) raises ForbiddenAction for non-member" do
    c = ctrl(user: other_user)
    err = assert_raises(Auth::ForbiddenAction) { c.authorize_for!(:write) }
    assert_equal :write, err.action
    assert_equal repo, err.repository
  end

  test "authorize_for!(:delete) does not raise for owner" do
    assert_nothing_raised { ctrl.authorize_for!(:delete) }
  end

  test "authorize_for!(:delete) raises ForbiddenAction for writer member" do
    RepositoryMember.create!(
      repository: repo,
      identity: other_user.primary_identity,
      role: "writer"
    )
    c = ctrl(user: other_user)
    assert_raises(Auth::ForbiddenAction) { c.authorize_for!(:delete) }
  end

  test "authorize_for!(:delete) does not raise for admin member" do
    RepositoryMember.create!(
      repository: repo,
      identity: other_user.primary_identity,
      role: "admin"
    )
    c = ctrl(user: other_user)
    assert_nothing_raised { c.authorize_for!(:delete) }
  end

  test "authorize_for! raises Unauthenticated when current_user is nil" do
    c = ctrl(user: nil)
    assert_raises(Auth::Unauthenticated) { c.authorize_for!(:write) }
  end

  test "authorize_for!(:read) always returns without raising" do
    c = ctrl(user: other_user)
    assert_nothing_raised { c.authorize_for!(:read) }
  end
end
