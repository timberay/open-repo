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

  # ---------------------------------------------------------------------------
  # UC-MODEL-006 .e3: RepositoryMember destroy cascade semantics
  #
  # Cascading is layered:
  #   - Repository declares `has_many :repository_members, dependent: :destroy`
  #     (Rails-level), AND repository_members.repository_id FK has
  #     on_delete: :cascade (DB-level safety net).
  #   - Identity does NOT declare `has_many :repository_members`. Cascading on
  #     identity destroy is enforced ONLY by the DB FK on_delete: :cascade on
  #     repository_members.identity_id.
  #   - Destroying a RepositoryMember row is a pure delete with no side-effects
  #     on its Identity or Repository.
  # ---------------------------------------------------------------------------

  test "destroying a Repository cascade-deletes all its RepositoryMember rows" do
    target_repo = Repository.create!(
      name: "rm-repo-destroy-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    other_repo = Repository.create!(
      name: "rm-repo-untouched-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    member_a = RepositoryMember.create!(
      repository: target_repo,
      identity: identities(:admin_google),
      role: "writer"
    )
    member_b = RepositoryMember.create!(
      repository: other_repo,
      identity: identities(:admin_google),
      role: "admin"
    )

    target_repo.destroy!

    refute RepositoryMember.exists?(member_a.id),
           "Member of destroyed repo must be cascade-deleted"
    assert RepositoryMember.exists?(member_b.id),
           "Member of unrelated repo must be untouched"
    assert Identity.exists?(identities(:admin_google).id),
           "Identity must NOT be cascaded by member deletion"
  end

  test "destroying an Identity cascade-deletes its RepositoryMember rows but leaves the Repository" do
    user = User.create!(email: "rm-id-destroy-#{SecureRandom.hex(3)}@example.com")
    identity = Identity.create!(
      user: user,
      provider: "google_oauth2",
      uid: "rm-id-#{SecureRandom.hex(4)}",
      email: user.email
    )
    target_repo = Repository.create!(
      name: "rm-id-repo-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    member = RepositoryMember.create!(repository: target_repo, identity: identity, role: "admin")

    identity.destroy!

    refute RepositoryMember.exists?(member.id),
           "RepositoryMember must be cascade-deleted when its Identity is destroyed (DB FK on_delete: :cascade)"
    assert Repository.exists?(target_repo.id),
           "Repository must survive a member identity being destroyed"
  end

  test "destroying a RepositoryMember row has no side-effects on Identity or Repository" do
    target_repo = Repository.create!(
      name: "rm-row-destroy-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    identity = identities(:admin_google)
    member = RepositoryMember.create!(repository: target_repo, identity: identity, role: "writer")

    member.destroy!

    refute RepositoryMember.exists?(member.id)
    assert Repository.exists?(target_repo.id), "Repository must be untouched by member row delete"
    assert Identity.exists?(identity.id), "Identity must be untouched by member row delete"
  end
end
