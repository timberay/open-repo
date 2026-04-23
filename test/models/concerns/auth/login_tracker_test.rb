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
end
