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

  test "primary_identity returns the associated identity" do
    assert_equal identities(:tonny_google), users(:tonny).primary_identity
  end

  test "destroying primary_identity nullifies users.primary_identity_id" do
    u = users(:tonny)
    i = u.primary_identity
    i.destroy!
    assert_nil u.reload.primary_identity_id
  end

  test "user with primary_identity_id set can be destroyed" do
    u = users(:tonny)
    assert u.primary_identity_id
    assert_nothing_raised { u.destroy! }
    assert u.destroyed?
  end

  test "User.admin_email? returns true for REGISTRY_ADMIN_EMAIL" do
    Rails.configuration.x.registry.admin_email = "admin@timberay.com"
    assert User.admin_email?("admin@timberay.com")
    refute User.admin_email?("someone-else@timberay.com")
  end

  test "User.admin_email? returns false when admin_email unset" do
    Rails.configuration.x.registry.admin_email = nil
    refute User.admin_email?("admin@timberay.com")
  end

  test "User.admin_email? is case-insensitive" do
    original = Rails.configuration.x.registry.admin_email
    begin
      Rails.configuration.x.registry.admin_email = "Admin@Timberay.com"
      assert User.admin_email?("admin@timberay.com")
      assert User.admin_email?("ADMIN@TIMBERAY.COM")
      assert User.admin_email?("Admin@Timberay.com")
      refute User.admin_email?("admin2@timberay.com")
    ensure
      Rails.configuration.x.registry.admin_email = original
    end
  end
end
