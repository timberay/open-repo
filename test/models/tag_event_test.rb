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
end
