require "test_helper"

class TagEventTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
  end

  test "validations requires tag_name, action, occurred_at" do
    event = TagEvent.new(repository: repository)
    refute event.valid?
    assert_includes event.errors[:tag_name], "can't be blank"
    assert_includes event.errors[:action], "can't be blank"
    assert_includes event.errors[:occurred_at], "can't be blank"
  end

  test "display_actor returns email unchanged for email-looking actor" do
    event = TagEvent.new(actor: "tonny@timberay.com")
    assert_equal "tonny@timberay.com", event.display_actor
  end

  test "display_actor wraps legacy 'anonymous' as system tag" do
    event = TagEvent.new(actor: "anonymous")
    assert_equal "<system: anonymous>", event.display_actor
  end

  test "display_actor strips 'system:' prefix" do
    event = TagEvent.new(actor: "system:import")
    assert_equal "<system: import>", event.display_actor
  end

  test "display_actor passes through retention-policy as system" do
    event = TagEvent.new(actor: "retention-policy")
    assert_equal "<system: retention-policy>", event.display_actor
  end

  test "display_actor handles nil" do
    event = TagEvent.new(actor: nil)
    assert_equal "<system: >", event.display_actor
  end

  test "action inclusion allows ownership_transfer" do
    event = TagEvent.new(
      repository: repository,
      tag_name: "-",
      action: "ownership_transfer",
      actor: "tonny@timberay.com",
      occurred_at: Time.current
    )
    assert event.valid?, event.errors.full_messages.inspect
  end

  test "belongs_to :actor_identity is optional" do
    event = TagEvent.new(
      repository: repository,
      tag_name: "v1",
      action: "delete",
      actor: "retention-policy",
      occurred_at: Time.current
    )
    # actor_identity_id = nil — should still be valid
    assert event.valid?, event.errors.full_messages.inspect
  end

  test "display_actor prefers actor_identity email when present" do
    identity = identities(:tonny_google)
    event = TagEvent.new(actor: "some-old-string", actor_identity: identity)
    assert_equal identity.email, event.display_actor
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-005 .e3: tag history ordering
  #
  # `occurred_at` is the source-of-truth for tag history ordering, NOT
  # `created_at`. The migration backfilled historical rows with synthetic
  # occurred_at values; ordering must respect those values even when rows are
  # inserted out-of-sequence (later-created row carrying an earlier occurred_at).
  # ---------------------------------------------------------------------------

  test "order(occurred_at: :desc) honours occurred_at, not insertion / created_at order" do
    repo = Repository.create!(
      name: "tag-event-order-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    base = Time.current.change(usec: 0)

    # Insert oldest occurred_at FIRST, then a row with the newest occurred_at,
    # then a middle one — so created_at order is NOT the same as occurred_at order.
    oldest = TagEvent.create!(
      repository: repo, tag_name: "v1", action: "create",
      actor: "tonny@timberay.com", occurred_at: base - 2.days
    )
    newest = TagEvent.create!(
      repository: repo, tag_name: "v1", action: "update",
      actor: "tonny@timberay.com", occurred_at: base
    )
    middle = TagEvent.create!(
      repository: repo, tag_name: "v1", action: "update",
      actor: "tonny@timberay.com", occurred_at: base - 1.day
    )

    ordered_ids = repo.tag_events.order(occurred_at: :desc).pluck(:id)
    assert_equal [ newest.id, middle.id, oldest.id ], ordered_ids,
                 "TagEvent.order(occurred_at: :desc) must rely on occurred_at, not insertion / created_at order"
  end
end
