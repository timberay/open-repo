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
end
