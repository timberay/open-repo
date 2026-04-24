require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "belongs to user" do
    assert_instance_of User, identities(:tonny_google).user
  end

  test "provider and uid pair must be unique" do
    identity = Identity.new(
      user: users(:admin),
      provider: "google_oauth2",
      uid: identities(:tonny_google).uid,
      email: "x@y.z"
    )
    refute identity.valid?
  end

  test "presence validations" do
    i = Identity.new
    refute i.valid?
    %w[provider uid email].each { |f| assert_includes i.errors.attribute_names, f.to_sym }
  end

  test "email_verified is tri-state (nil allowed)" do
    i = Identity.new(
      user: users(:admin),
      provider: "google_oauth2",
      uid: "xxx",
      email: "x@y.z",
      email_verified: nil
    )
    assert i.valid?
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-003 .e3: Identity destroy cascade semantics
  #
  # NOTE: `Identity` does NOT declare `has_many :tag_events` or
  # `has_many :repository_members`. Cascading is enforced at the DB level via
  # foreign-key `on_delete:` clauses (see db/schema.rb add_foreign_key lines):
  #   - tag_events.actor_identity_id        on_delete: :nullify
  #   - repository_members.identity_id      on_delete: :cascade
  #   - users.primary_identity_id           on_delete: :nullify
  # The tests below pin those observed behaviours so a future migration that
  # accidentally drops a clause is caught.
  # ---------------------------------------------------------------------------

  test "destroying an Identity nullifies referencing TagEvent.actor_identity_id (DB FK on_delete: :nullify)" do
    user = User.create!(email: "destroy-tagevent-#{SecureRandom.hex(3)}@example.com")
    identity = Identity.create!(
      user: user,
      provider: "google_oauth2",
      uid: "destroy-te-#{SecureRandom.hex(4)}",
      email: user.email
    )
    repo = Repository.create!(
      name: "id-destroy-te-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    event = TagEvent.create!(
      repository: repo,
      tag_name: "v1",
      action: "create",
      actor: identity.email,
      actor_identity_id: identity.id,
      occurred_at: Time.current
    )

    identity.destroy!

    event.reload
    assert_nil event.actor_identity_id,
               "TagEvent.actor_identity_id must be nullified, not cascade-deleted, when its actor Identity is destroyed"
    assert TagEvent.exists?(event.id), "TagEvent row must survive its actor Identity being destroyed"
  end

  test "destroying an Identity cascade-deletes its RepositoryMember rows (DB FK on_delete: :cascade)" do
    user = User.create!(email: "destroy-rm-#{SecureRandom.hex(3)}@example.com")
    identity = Identity.create!(
      user: user,
      provider: "google_oauth2",
      uid: "destroy-rm-#{SecureRandom.hex(4)}",
      email: user.email
    )
    repo = Repository.create!(
      name: "id-destroy-rm-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    member = RepositoryMember.create!(repository: repo, identity: identity, role: "writer")

    identity.destroy!

    refute RepositoryMember.exists?(member.id),
           "RepositoryMember row must be cascade-deleted when its Identity is destroyed"
  end

  test "destroying primary Identity nullifies User.primary_identity_id (DB FK on_delete: :nullify)" do
    user = User.create!(email: "primary-nullify-#{SecureRandom.hex(3)}@example.com")
    primary = Identity.create!(
      user: user,
      provider: "google_oauth2",
      uid: "primary-#{SecureRandom.hex(4)}",
      email: user.email
    )
    secondary = Identity.create!(
      user: user,
      provider: "github",
      uid: "secondary-#{SecureRandom.hex(4)}",
      email: user.email
    )
    user.update!(primary_identity_id: primary.id)

    primary.destroy!

    user.reload
    assert_nil user.primary_identity_id,
               "User.primary_identity_id is nullified by DB FK; Rails does NOT auto-rotate to another identity"
    assert User.exists?(user.id), "User row must survive primary identity destroy"
    assert Identity.exists?(secondary.id), "Sibling identity must be untouched"
  end

  test "destroying the only Identity of a User nullifies primary_identity_id but leaves User intact" do
    user = User.create!(email: "only-identity-#{SecureRandom.hex(3)}@example.com")
    only = Identity.create!(
      user: user,
      provider: "google_oauth2",
      uid: "only-#{SecureRandom.hex(4)}",
      email: user.email
    )
    user.update!(primary_identity_id: only.id)

    only.destroy!

    user.reload
    assert_nil user.primary_identity_id
    assert User.exists?(user.id),
           "Identity destroy does NOT cascade up to User (User survives identity-less)"
    assert_equal 0, user.identities.count
  end
end
