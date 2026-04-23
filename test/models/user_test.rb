require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin fixture has admin=true" do
    assert users(:admin).admin?
  end

  test "non-admin fixture has admin=false" do
    refute users(:tonny).admin?
  end

  test "email must be present" do
    u = User.new(admin: false)
    refute u.valid?
    assert_includes u.errors[:email], "can't be blank"
  end

  test "email must be unique" do
    User.create!(email: "dupe@x.com", admin: false)
    dup = User.new(email: "dupe@x.com", admin: false)
    refute dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end
end
