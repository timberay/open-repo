require "test_helper"

class RepositoryMemberTest < ActiveSupport::TestCase
  def repo
    @repo ||= Repository.create!(
      name: "member-test-#{SecureRandom.hex(4)}",
      owner_identity_id: identities(:tonny_google).id
    )
  end

  test "valid with writer role" do
    member = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )
    assert member.valid?
  end

  test "valid with admin role" do
    member = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "admin"
    )
    assert member.valid?
  end

  test "invalid with unknown role" do
    member = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "superuser"
    )
    refute member.valid?
    assert_includes member.errors[:role], "is not included in the list"
  end

  test "uniqueness: cannot add same identity twice to same repo" do
    RepositoryMember.create!(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )
    duplicate = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "admin"
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:identity_id], "has already been taken"
  end

  test "belongs_to :repository" do
    assert_equal :belongs_to, RepositoryMember.reflect_on_association(:repository).macro
  end

  test "belongs_to :identity" do
    assert_equal :belongs_to, RepositoryMember.reflect_on_association(:identity).macro
  end
end
