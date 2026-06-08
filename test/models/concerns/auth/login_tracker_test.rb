require "test_helper"

class Auth::LoginTrackerTest < ActiveSupport::TestCase
  test "track_login! sets primary_identity_id and last_seen_at and identity.last_login_at" do
    user = users(:tonny)
    other_identity = user.identities.create!(
      provider: "google_oauth2",
      uid: "second-google",
      email: user.email
    )

    freeze_time = Time.current
    travel_to(freeze_time) do
      user.track_login!(other_identity)
    end

    user.reload
    other_identity.reload
    assert_equal other_identity.id, user.primary_identity_id
    assert_in_delta freeze_time, user.last_seen_at, 1.second
    assert_in_delta freeze_time, other_identity.last_login_at, 1.second
  end

  test "track_login! syncs user.email to the primary identity's email" do
    user = users(:tonny) # tonny@timberay.com
    moved = user.identities.create!(
      provider: "google_oauth2", uid: "moved-google",
      email: "tonny+moved@timberay.com"
    )

    user.track_login!(moved)

    assert_equal "tonny+moved@timberay.com", user.reload.email
  end

  test "track_login! does not sync user.email when another user already holds it" do
    user = users(:tonny) # tonny@timberay.com
    taken = users(:admin).email # admin@timberay.com — owned by a different user
    identity = user.identities.create!(
      provider: "google_oauth2", uid: "conflict-google", email: taken
    )

    assert_nothing_raised { user.track_login!(identity) }

    assert_equal "tonny@timberay.com", user.reload.email # unchanged (conflict)
    assert_equal identity.id, user.primary_identity_id   # login still tracked
  end

  test "track_login! survives a uniqueness race on the email mirror (no 500)" do
    user = users(:tonny)
    identity = user.identities.create!(
      provider: "google_oauth2", uid: "race-google", email: "tonny+race@timberay.com"
    )
    # Simulate losing a concurrent race: the guard passes (no other user holds
    # the email yet) but the unique index rejects the email write.
    def user.update!(*args)
      if args.first.is_a?(Hash) && args.first.key?(:email)
        raise ActiveRecord::RecordNotUnique, "duplicate key"
      end
      super
    end

    assert_nothing_raised { user.track_login!(identity) }
    assert_equal identity.id, user.reload.primary_identity_id
  end

  test "track_login! is atomic — rollback on identity save failure" do
    user = users(:tonny)
    original_primary = user.primary_identity_id

    bad_identity = Identity.new  # unsaved, validations will fail
    assert_raises(ActiveRecord::RecordInvalid) do
      user.track_login!(bad_identity)
    end

    user.reload
    assert_equal original_primary, user.primary_identity_id
  end

  test "track_login! is atomic — rollback on user update failure (identity already saved)" do
    user = users(:tonny)
    identity = user.primary_identity
    original_last_login = identity.last_login_at

    def user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      user.track_login!(identity)
    end

    identity.reload
    assert_equal original_last_login.to_i, identity.last_login_at.to_i
  end
end
