require "test_helper"

class TagEventTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo")
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
end
