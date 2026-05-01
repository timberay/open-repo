require "test_helper"

# QA TEST_PLAN coverage:
#   UC-AUTH-006 — Expired PAT (e1 boundary `>` semantics, e2 nil expires_at never expires)
#   UC-AUTH-007 — Revoked PAT (e1 revoke-then-401, e2 200→revoke→401 in-flight semantics)
#
# Endpoint choice: `POST /v2/<name>/blobs/uploads`. It is a write action, so
# `anonymous_pull_allowed?` is false even when `anonymous_pull_enabled=true`
# (the test_helper default), guaranteeing the PAT auth gate always runs.
# A successful auth returns 202 (BlobUploads#create); a 401 means the PAT
# was rejected by `PersonalAccessToken.active`. Either status proves the
# auth decision, which is all these lifecycle tests assert against.
class PatLifecycleTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  EMAIL = "tonny@timberay.com".freeze

  setup do
    @identity = identities(:tonny_google)
    @repo_name = "pat-lifecycle-#{SecureRandom.hex(4)}"
  end

  teardown do
    travel_back
  end

  # ---- UC-AUTH-006 e1: expires_at == now boundary -------------------------
  #
  # `PersonalAccessToken.active` uses `expires_at > ?, Time.current` (strictly
  # greater). When `expires_at` equals `Time.current` exactly, the token is NOT
  # active and must 401.

  test "UC-AUTH-006.e1: PAT expires_at exactly now is rejected (strict >, not >=)" do
    raw = PersonalAccessToken.generate_raw
    # Pin both `expires_at` and the request clock to the SAME instant so
    # `expires_at > Time.current` evaluates exactly at the boundary.
    # DB persistence may round to microseconds — `change(usec: 0)` ensures
    # the round-tripped value still equals `target` after reload.
    target = 1.second.from_now.change(usec: 0)
    pat = create_pat!(raw: raw, name: "boundary-now", expires_at: target)
    assert_equal target, pat.reload.expires_at,
                 "precondition: stored expires_at must equal target (no precision drift)"

    travel_to(target) do
      assert_equal target, Time.current,
                   "precondition: frozen Time.current must equal target"
      post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(raw)
      assert_response :unauthorized,
                      "expires_at == Time.current must NOT pass `active` (strict >); got #{response.status}"
    end

    assert_nil pat.reload.last_used_at,
               "rejected auth must not stamp last_used_at"
  end

  test "UC-AUTH-006.e1: PAT expires_at strictly in the future is accepted" do
    raw = PersonalAccessToken.generate_raw
    create_pat!(raw: raw, name: "boundary-future", expires_at: 1.second.from_now)

    # No travel_to — real wall clock leaves us strictly before expires_at.
    post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(raw)

    assert_not_equal 401, response.status,
                     "PAT with expires_at in the future must authenticate; got #{response.status}"
  end

  # ---- UC-AUTH-006 e2: nil expires_at never expires ----------------------

  test "UC-AUTH-006.e2: PAT with nil expires_at authenticates 100 years from now" do
    raw = PersonalAccessToken.generate_raw
    create_pat!(raw: raw, name: "never-expires", expires_at: nil)

    travel_to(100.years.from_now) do
      post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(raw)
      assert_not_equal 401, response.status,
                       "nil expires_at must never expire; got #{response.status} far in the future"
    end
  end

  # ---- UC-AUTH-007 e1: revoked PAT → 401 --------------------------------

  test "UC-AUTH-007.e1: PAT revoked before request returns 401" do
    raw = PersonalAccessToken.generate_raw
    pat = create_pat!(raw: raw, name: "to-be-revoked-e1", expires_at: 30.days.from_now)

    pat.revoke!
    assert_not_nil pat.reload.revoked_at, "precondition: revoked_at must be set"

    post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(raw)
    assert_response :unauthorized,
                    "active scope must filter revoked tokens; got #{response.status}"
  end

  # ---- UC-AUTH-007 e2: in-flight semantics (200 → revoke → 401) ---------
  #
  # Documented contract: a request that authenticated before revocation
  # may complete; the very next request 401s. This locks in the sequence.

  test "UC-AUTH-007.e2: prior request succeeds, revoke, next request 401s" do
    raw = PersonalAccessToken.generate_raw
    pat = create_pat!(raw: raw, name: "in-flight-revoke", expires_at: 30.days.from_now)

    # First request — token is valid; expect non-401 (auth gate passed).
    post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(raw)
    assert_not_equal 401, response.status,
                     "first request before revoke must authenticate; got #{response.status}"

    # Observability path: the controller stamps last_used_at on success.
    assert_not_nil pat.reload.last_used_at,
                   "successful auth must update last_used_at (UC-AUTH-007.e1 observability)"

    # Revoke between requests.
    pat.revoke!

    # Second request — must 401.
    post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(raw)
    assert_response :unauthorized,
                    "post-revoke request must 401; got #{response.status}"
  end

  # ---- B-35: Mistyped password (typo) → 401, no last_used_at mutation ----
  #
  # Locks in that authentication side-effects only happen on a successful
  # match. A single-character truncation on the raw value must be rejected
  # without touching the real PAT's observability fields. Complements the
  # existing expired/revoked coverage with the typo path.

  test "B-35: typo password returns 401 and does not update last_used_at" do
    raw = PersonalAccessToken.generate_raw
    pat = create_pat!(raw: raw, name: "typo-test", expires_at: 1.day.from_now)
    pat.update_column(:last_used_at, nil)

    # Drop a single character to simulate a typo.
    typo = raw[0..-2]

    post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(typo)
    assert_response :unauthorized

    pat.reload
    assert_nil pat.last_used_at,
               "typo'd password must not advance last_used_at"
  end

  private

  def create_pat!(raw:, name:, expires_at:)
    PersonalAccessToken.create!(
      identity: @identity,
      name: name,
      kind: "cli",
      token_digest: Digest::SHA256.hexdigest(raw),
      expires_at: expires_at
    )
  end

  def pat_headers(raw)
    {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(EMAIL, raw)
    }
  end
end
