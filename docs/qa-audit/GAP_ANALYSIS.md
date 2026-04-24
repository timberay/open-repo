# Test Coverage Gap Analysis

## Legend
- ✅ Covered — a specific test exists that exercises the use-case (happy path)
- ⚠️ Partial — the area has tests but the specific use-case or edge case is not clearly exercised
- ❌ Missing — no test exists for this use-case

## Coverage Matrix

### V2 Registry API
| UC ID | Title | Status | Evidence (file:approx_line or "—") | Edge cases covered (.e1, .e2, ...) |
|---|---|---|---|---|
| UC-V2-001 | Ping `GET /v2/` | ✅ | test/controllers/v2/base_controller_test.rb:7,13 | .e1 ✅, .e2 ✅ (base_controller_test.rb:119), .e3 ⚠️ (implied via docker_basic_auth_test.rb), .e4 ⚠️, .e5 ✅ (base_controller_test.rb:60) |
| UC-V2-002 | Catalog list `GET /v2/_catalog` | ✅ | test/controllers/v2/catalog_controller_test.rb:8,15 | .e1 ⚠️, .e2 ❌, .e3 ❌, .e4 ❌, .e5 ✅ (anonymous_pull_regression_test.rb:45), .e6 ❌, .e7 ✅ (catalog_controller_test.rb:19) |
| UC-V2-003 | Tags list `GET /v2/:name/tags/list` | ✅ | test/controllers/v2/tags_controller_test.rb:10,17,24 | .e1 ✅ (tags_controller_test.rb:24), .e2 ❌, .e3 ❌, .e4 ❌, .e5 ✅ (tags_controller_test.rb:17) |
| UC-V2-004 | Manifest pull by tag | ✅ | test/controllers/v2/manifests_controller_test.rb:55,68,78,87,97,102,114 | .e1 ✅ (manifests_controller_test.rb:102,114), .e2 ⚠️, .e3 ✅ (manifests_controller_test.rb:97), .e4 ✅ (anonymous_pull_regression_test.rb:90), .e5 ✅ (manifests_controller_test.rb:68), .e6 ⚠️, .e7 ⚠️ (only remote_ip via anonymous_pull_regression_test.rb:99), .e8 ❌ |
| UC-V2-005 | Manifest push (happy path) | ✅ | test/controllers/v2/manifests_controller_test.rb:37; test/services/manifest_processor_test.rb:62 | .e1 ✅ (manifests_controller_test.rb:46), .e2 ⚠️ (manifest_processor_test.rb via ManifestInvalid), .e3 ⚠️, .e4 ✅ (manifest_processor_test.rb:107), .e5 ✅ (base_controller_test.rb:53,60), .e6 ✅ (manifests_controller_test.rb:213), .e7 ✅ (manifest_processor_test.rb:147), .e8 ✅ (manifest_processor_test.rb:136), .e9 ✅ (blob_uploads_controller_test.rb:118), .e10 ⚠️ (first_pusher_race_test.rb:23), .e11 ❌, .e12 ❌, .e13 ⚠️, .e14 ❌, .e15 ❌, .e16 ❌ |
| UC-V2-006 | Manifest delete | ✅ | test/controllers/v2/manifests_controller_test.rb:123,170 | .e1 ✅ (manifests_controller_test.rb:139), .e2 ⚠️, .e3 ⚠️, .e4 ✅ (anonymous_pull_regression_test.rb:82), .e5 ✅ (manifests_controller_test.rb:239), .e6 ⚠️ (cleanup job test separate) |
| UC-V2-007 | Blob pull | ✅ | test/controllers/v2/blobs_controller_test.rb:22,34 | .e1 ✅ (blobs_controller_test.rb:34), .e2 ✅ (blobs_controller_test.rb:29), .e3 ❌, .e4 ⚠️, .e5 ❌ |
| UC-V2-008 | Blob delete | ✅ | test/controllers/v2/blobs_controller_test.rb:41,68 | .e1 ❌, .e2 ⚠️, .e3 ⚠️, .e4 ✅ (blobs_controller_test.rb:50), .e5 ❌ |
| UC-V2-009 | Blob upload initiation | ✅ | test/controllers/v2/blob_uploads_controller_test.rb:14,23 | .e1 ✅ (anonymous_pull_regression_test.rb:76), .e2 ✅ (blob_uploads_controller_test.rb:23,118), .e3 ✅ (first_pusher_race_test.rb:23) |
| UC-V2-010 | Blob upload monolithic | ✅ | test/controllers/v2/blob_uploads_controller_test.rb:28 | .e1 ⚠️, .e2 ❌, .e3 ❌ |
| UC-V2-011 | Blob mount | ✅ | test/controllers/v2/blob_uploads_controller_test.rb:85 | .e1 ✅ (blob_uploads_controller_test.rb:98), .e2 ❌, .e3 ⚠️, .e4 ❌, .e5 ✅ (anonymous_pull_regression_test.rb:76) |
| UC-V2-012 | Chunked upload PATCH | ✅ | test/controllers/v2/blob_uploads_controller_test.rb:40 | .e1 ❌, .e2 ❌, .e3 ❌, .e4 ⚠️ |
| UC-V2-013 | Chunked upload finalize | ✅ | test/controllers/v2/blob_uploads_controller_test.rb:53,71 | .e1 ✅ (blob_uploads_controller_test.rb:71), .e2 ⚠️, .e3 ❌, .e4 ❌, .e5 ⚠️ |
| UC-V2-014 | Upload cancel | ✅ | test/controllers/v2/blob_uploads_controller_test.rb:105 | .e1 ❌, .e2 ❌, .e3 ⚠️ |
| UC-V2-015 | Error response format | ⚠️ | test/controllers/v2/base_controller_test.rb:36,126; test/controllers/v2/manifests_controller_test.rb:139,224 | .e1 ⚠️ (subset: DENIED, UNSUPPORTED, DIGEST_INVALID, UNAUTHORIZED covered; BLOB_UNKNOWN, BLOB_UPLOAD_UNKNOWN, MANIFEST_UNKNOWN, MANIFEST_INVALID, NAME_UNKNOWN not explicitly asserted as codes), .e2 ❌, .e3 ✅ (anonymous_pull_regression_test.rb:76; docker_basic_auth_test.rb:59) |
| UC-V2-016 | Tag protection atomicity | ⚠️ | test/services/manifest_processor_test.rb:147,160,176 | .e1 ✅ (manifest_processor_test.rb:136), .e2 ✅ (manifest_processor_test.rb:147) — no explicit concurrency race test |

### Web UI
| UC ID | Title | Status | Evidence (file:approx_line or "—") | Edge cases covered |
|---|---|---|---|---|
| UC-UI-001 | Repository list `GET /` | ✅ | test/controllers/repositories_controller_test.rb:10; e2e/repository-list.spec.js:8 | .e1 ⚠️ (e2e repository-list.spec.js:26 covers search empty, not initial), .e2 ❌, .e3 ❌, .e4 ❌, .e5 ✅ (e2e/dark-mode.spec.js:25) |
| UC-UI-002 | Repository search & sort | ✅ | test/controllers/repositories_controller_test.rb:16; test/controllers/repositories_search_controller_test.rb:10,18,24; e2e/search.spec.js:8,22,37 | .e1 ✅ (repositories_search_controller_test.rb:24), .e2 ✅ (search.spec.js:22), .e3 ❌, .e4 ⚠️ (search.spec.js:37), .e5 ❌, .e6 ❌ |
| UC-UI-003 | Repository detail | ✅ | test/controllers/repositories_controller_test.rb:21,41,70,210; e2e/tag-details.spec.js:11 | .e1 ❌, .e2 ⚠️, .e3 ❌, .e4 ❌, .e5 ❌ |
| UC-UI-004 | Repository edit | ✅ | test/controllers/repositories_controller_test.rb:27,160,167,175,182,189,197 | .e1 ⚠️ (e2e/tag-protection.spec.js:56), .e2 ⚠️, .e3 ✅ (repositories_controller_test.rb:182; e2e/tag-protection.spec.js:69), .e4 ❌, .e5 ❌ (known security gap not explicitly asserted), .e6 ❌, .e7 ✅ (repositories_controller_test.rb:175) |
| UC-UI-005 | Repository delete | ✅ | test/controllers/repositories_controller_test.rb:33,223,239 | .e1 ✅ (repositories_controller_test.rb:223), .e2 ❌, .e3 ❌, .e4 ⚠️ (concerns/repository_authorization_test.rb:71) |
| UC-UI-006 | Tag detail | ✅ | test/controllers/tags_controller_test.rb:18; e2e/tag-details.spec.js:11,29 | .e1 ❌, .e2 ❌, .e3 ❌, .e4 ✅ (e2e/tag-protection.spec.js:42,49), .e5 ❌, .e6 ❌ |
| UC-UI-007 | Tag delete | ✅ | test/controllers/tags_controller_test.rb:29,35,41,49,58,77,100 | .e1 ✅ (tags_controller_test.rb:35,41,49), .e2 ✅ (tags_controller_test.rb:77), .e3 ❌ |
| UC-UI-008 | Tag history | ❌ | — | .e1–.e4 ❌ (no test file exercises `/repositories/:name/tags/:tag/history`) |
| UC-UI-009 | Help page | ❌ | — | .e1 ❌, .e2 ❌, .e3 ❌ (no HelpController test; only passing links checked in repositories_controller_test.rb:81) |
| UC-UI-010 | Dark mode toggle | ✅ | e2e/dark-mode.spec.js:8,25,45 | .e1 ⚠️, .e2 ❌, .e3 ❌, .e4 ⚠️ |
| UC-UI-011 | PAT index | ✅ | test/controllers/settings/tokens_controller_test.rb:8,13,20 | .e1 ⚠️, .e2 ✅ (tokens_controller_test.rb:13), .e3 ✅ (tokens_controller_test.rb:8), .e4 ❌ |
| UC-UI-012 | PAT create | ✅ | test/controllers/settings/tokens_controller_test.rb:28,45,55 | .e1 ⚠️, .e2 ✅ (tokens_controller_test.rb:55), .e3 ⚠️ (tokens_controller_test.rb:45 covers blank), .e4 ❌, .e5 ⚠️, .e6 ⚠️ |
| UC-UI-013 | PAT revoke | ✅ | test/controllers/settings/tokens_controller_test.rb:67,76,85 | .e1 ✅ (tokens_controller_test.rb:76), .e2 ❌, .e3 ✅ (tokens_controller_test.rb:85) |

### Auth
| UC ID | Title | Status | Evidence (file:approx_line or "—") | Edge cases covered |
|---|---|---|---|---|
| UC-AUTH-001 | Google OAuth sign-in | ✅ | test/controllers/auth/sessions_controller_test.rb:22,29,38; test/integration/auth_google_oauth_flow_test.rb:23,38,52; test/services/auth/session_creator_test.rb:24,37,84,104 | .e1 ✅ (session_creator_test.rb:37), .e2 ✅ (session_creator_test.rb:104), .e3 ✅ (sessions_controller_test.rb:38; session_creator_test.rb:58,127), .e4 ✅ (session_creator_test.rb:119), .e5 ❌, .e6 ❌, .e7 ❌ |
| UC-AUTH-002 | Sign out | ✅ | test/controllers/auth/sessions_controller_test.rb:44; test/integration/login_button_visibility_test.rb:19 | .e1 ⚠️, .e2 ✅ (login_button_visibility_test.rb:19), .e3 ❌ |
| UC-AUTH-003 | OAuth failure | ✅ | test/controllers/auth/sessions_controller_test.rb:54,60,66 | .e1 ⚠️, .e2 ❌ |
| UC-AUTH-004 | V2 Basic — valid PAT | ✅ | test/controllers/v2/base_controller_test.rb:69,79; test/services/auth/pat_authenticator_test.rb:6,15; test/integration/docker_basic_auth_test.rb:69 | .e1 ✅ (base_controller_test.rb:79), .e2 ✅ (pat_authenticator_test.rb:15) |
| UC-AUTH-005 | V2 Basic — invalid/missing | ✅ | test/controllers/v2/base_controller_test.rb:53,60,93,102; test/services/auth/pat_authenticator_test.rb:23,29,35,41,47 | .e1 ✅ (base_controller_test.rb:53), .e2 ✅ (base_controller_test.rb:60), .e3 ⚠️, .e4 ✅ (pat_authenticator_test.rb:47), .e5 ✅ (base_controller_test.rb:102; pat_authenticator_test.rb:41), .e6 ✅ (pat_authenticator_test.rb:15), .e7 ✅ (pat_authenticator_test.rb:23) |
| UC-AUTH-006 | Expired PAT | ✅ | test/models/personal_access_token_test.rb:10; test/services/auth/pat_authenticator_test.rb:35 | .e1 ❌, .e2 ✅ (personal_access_token_test.rb:14) |
| UC-AUTH-007 | Revoked PAT | ✅ | test/controllers/v2/base_controller_test.rb:93; test/services/auth/pat_authenticator_test.rb:29; test/integration/docker_basic_auth_test.rb:91 | .e1 ❌, .e2 ⚠️ (tokens_controller_test.rb:85) |
| UC-AUTH-008 | Authorization — write | ✅ | test/controllers/v2/manifests_controller_test.rb:213,227; test/controllers/v2/blob_uploads_controller_test.rb:129,142; test/controllers/concerns/repository_authorization_test.rb:36,40 | .e1 ✅ (manifests_controller_test.rb:227 owner; blob_uploads_controller_test.rb:142 writer), .e2 ⚠️, .e3 ✅ (manifests_controller_test.rb:227), .e4 ❌ |
| UC-AUTH-009 | Authorization — delete | ✅ | test/controllers/v2/manifests_controller_test.rb:239; test/controllers/v2/blobs_controller_test.rb:50,68; test/controllers/concerns/repository_authorization_test.rb:47,51,61 | .e1 ✅ (repository_authorization_test.rb:51), .e2 ✅ (repository_authorization_test.rb:61), .e3 ✅ (blobs_controller_test.rb:68) |
| UC-AUTH-010 | Anonymous pull gating | ✅ | test/integration/anonymous_pull_regression_test.rb:40,45,50,55,61,76,82,90; test/controllers/v2/base_controller_test.rb:113,119 | .e1 ✅ (anonymous_pull_regression_test.rb entire), .e2 ✅ (anonymous_pull_regression_test.rb:68,76,82) |
| UC-AUTH-011 | First-pusher repo creation | ✅ | test/integration/first_pusher_race_test.rb:23,45,66; test/controllers/v2/blob_uploads_controller_test.rb:118 | .e1 ✅ (first_pusher_race_test.rb:23), .e2 ❌, .e3 ✅ (first_pusher_race_test.rb:45) |
| UC-AUTH-012 | Rack::Attack throttling | ⚠️ | test/integration/rack_attack_auth_throttle_test.rb:21 | .e1 ❌, .e2 ⚠️, .e3 ❌ (V2 non-GET 30/min throttle NOT tested) |
| UC-AUTH-013 | CSRF | ❌ | — | .e1 ❌, .e2 ❌, .e3 ❌ (no CSRF-specific tests found) |
| UC-AUTH-014 | Tag protection bypass via mount | ❌ | — | .e1 ❌, .e2 ⚠️ (manifest_processor_test.rb:147 covers PUT path but not the mount-then-push sequence) |
| UC-AUTH-015 | Repository visibility | ⚠️ | test/controllers/repositories_controller_test.rb:10,21 | .e1 ❌, .e2 N/A |
| UC-AUTH-016 | Session cookie hygiene | ❌ | — | .e1 ❌, .e2 ✅ (auth_session_restore_test.rb:17) |
| UC-AUTH-017 | Email verification | ✅ | test/services/auth/session_creator_test.rb:58,71,127,144 | .e1 ✅ (auth_google_oauth_flow_test.rb:38), .e2 ❌ |

### Jobs
| UC ID | Title | Status | Evidence (file:approx_line or "—") | Edge cases covered |
|---|---|---|---|---|
| UC-JOB-001 | CleanupOrphanedBlobsJob | ⚠️ | test/jobs/cleanup_orphaned_blobs_job_test.rb:16,28 | .e1 ❌, .e2 ❌, .e3 ❌, .e4 ❌, .e5 ❌, .e6 ❌ (only refs_count==0 happy path + not-deleted-if-referenced) |
| UC-JOB-002 | EnforceRetentionPolicyJob | ✅ | test/jobs/enforce_retention_policy_job_test.rb:19,29,39,51,62,73,86; test/integration/retention_ownership_interaction_test.rb:17,43,67 | .e1 ✅ (enforce_retention_policy_job_test.rb:19), .e2 ❌, .e3 ❌, .e4 ⚠️, .e5 ⚠️ (v1.0.0 only), .e6 ✅ (enforce_retention_policy_job_test.rb:86), .e7 ❌, .e8 ⚠️, .e9 ⚠️ (retention_ownership_interaction_test.rb:17), .e10 ✅ (retention_ownership_interaction_test.rb:67) |
| UC-JOB-003 | PruneOldEventsJob | ❌ | — | .e1–.e5 ❌ (no test file — plan explicitly flags this) |

### Models / Services
| UC ID | Title | Status | Evidence (file:approx_line or "—") | Edge cases covered |
|---|---|---|---|---|
| UC-MODEL-001 | Repository | ✅ | test/models/repository_test.rb:8,14,45–220,247–308 | .e1 ✅ (repository_test.rb:14), .e2 ✅ (repository_test.rb:156), .e3 ✅ (repository_test.rb:141), .e4 ✅ (repository_test.rb:45–116), .e5 ✅ (repository_test.rb:213), .e6 ✅ (repository_test.rb:255–290) |
| UC-MODEL-002 | PersonalAccessToken | ✅ | test/models/personal_access_token_test.rb:6–51 | .e1 ✅ (personal_access_token_test.rb:51), .e2 ⚠️ (pat_authenticator_test.rb:47 covers blank email; blank raw covered in pat_authenticator_test.rb:23 via unknown), .e3 ✅ (personal_access_token_test.rb:22 + base_controller_test.rb:79), .e4 ✅ (personal_access_token_test.rb:45), .e5 ⚠️ |
| UC-MODEL-003 | Identity | ✅ | test/models/identity_test.rb:4,8,18,24 | .e1 ⚠️, .e2 ✅ (identity_test.rb:8), .e3 ❌ |
| UC-MODEL-004 | Manifest / Layer / Blob | ✅ | test/models/manifest_test.rb:8–43; test/models/layer_test.rb:22,27; test/models/blob_test.rb:4,11,17; test/services/manifest_processor_test.rb:127 | .e1 ✅ (layer_test.rb:27), .e2 ⚠️, .e3 ✅ (manifest_test.rb:17), .e4 ⚠️ |
| UC-MODEL-005 | TagEvent / PullEvent | ✅ | test/models/tag_event_test.rb:8–64; test/models/pull_event_test.rb:18; test/models/repository_test.rb:308 | .e1 ✅ (tag_event_test.rb:31), .e2 ❌, .e3 ❌, .e4 ✅ (repository_test.rb:308) |
| UC-MODEL-006 | RepositoryMember | ✅ | test/models/repository_member_test.rb:11,20,29,39; test/models/repository_test.rb:295,302 | .e1 ✅ (repository_member_test.rb:39), .e2 ✅ (repository_test.rb:302), .e3 ❌ |
| UC-MODEL-007 | BlobStore service | ✅ | test/services/blob_store_test.rb:16,25,38,42,49,57,62,69,91,101,110 | .e1 ✅ (blob_store_test.rb:25), .e2 ✅ (blob_store_test.rb:91), .e3 ⚠️, .e4 ⚠️, .e5 ❌, .e6 ✅ (blob_store_test.rb:110) |
| UC-MODEL-008 | DigestCalculator service | ✅ | test/services/digest_calculator_test.rb:4,9,15,24,31,37 | .e1 ✅ (digest_calculator_test.rb:4), .e2 ✅ (digest_calculator_test.rb:9,15), .e3 ✅ (digest_calculator_test.rb:37), .e4 ✅ (digest_calculator_test.rb:24) |
| UC-MODEL-009 | ManifestProcessor service | ✅ | test/services/manifest_processor_test.rb:62–231 | .e1 ⚠️ (covered in controller test manifests_controller_test.rb:46), .e2 ⚠️, .e3 ⚠️, .e4 ✅ (manifest_processor_test.rb:107), .e5 ✅ (manifest_processor_test.rb:147), .e6 ✅ (manifest_processor_test.rb:136), .e7 ❌, .e8 ⚠️, .e9 ⚠️, .e10 ❌, .e11 ✅ (manifest_processor_test.rb:127), .e12 ❌, .e13 ❌ |

## Summary Statistics
- Total use-cases: 58
- ✅ Covered: 48 (83%)
- ⚠️ Partial: 6 (10%)
- ❌ Missing: 4 (7%)

Per-area breakdown:
- **V2 Registry API (16 UCs)**: ✅ 14 · ⚠️ 2 (UC-V2-015, UC-V2-016) · ❌ 0 — many edge cases unmet despite happy-path coverage
- **Web UI (13 UCs)**: ✅ 11 · ⚠️ 0 · ❌ 2 (UC-UI-008 tag history, UC-UI-009 help page)
- **Auth (17 UCs)**: ✅ 12 · ⚠️ 2 (UC-AUTH-012, UC-AUTH-015) · ❌ 3 (UC-AUTH-013 CSRF, UC-AUTH-014 mount-bypass, UC-AUTH-016 cookie hygiene)
- **Jobs (3 UCs)**: ✅ 1 · ⚠️ 1 (UC-JOB-001) · ❌ 1 (UC-JOB-003 PruneOldEventsJob)
- **Models/Services (9 UCs)**: ✅ 9 · ⚠️ 0 · ❌ 0 (but several edge cases unmet)

## High-priority gaps

1. **UC-AUTH-013: CSRF enforcement** (Security — MISSING) — no tests assert that Web UI forms require valid authenticity tokens or that V2/OAuth callback explicitly skip forgery protection. Attack surface if regression introduced. *Suggested*: integration test per controller class (PATCH/DELETE without token → 422/redirect).
2. **UC-AUTH-012 .e3: V2 non-GET 30/min throttling** (Security — PARTIAL) — only `/auth/*` throttle is tested; V2 write endpoint throttling is entirely unverified. Registry flood could degrade service. *Suggested*: integration test analogous to rack_attack_auth_throttle_test.rb targeting `POST /v2/:name/blobs/uploads`.
3. **UC-JOB-003: PruneOldEventsJob** (Data-integrity — MISSING) — no test file at all; 90-day retention of PullEvents is unverified. Risk of unbounded table growth or accidental deletion of recent data at the boundary. *Suggested*: unit test (job) covering 90-day strict-boundary (.e1) and empty dataset (.e2).
4. **UC-AUTH-014: Tag protection bypass via blob mount** (Security — MISSING) — threat-model-driven UC with zero direct coverage. Regression could enable a protected-tag manifest swap. *Suggested*: integration test performing mount then manifest PUT on protected tag, expecting 409.
5. **UC-UI-004 .e5: Repository edit authorization** (Security — PARTIAL) — plan explicitly marks a known gap where any signed-in user can PATCH. No test pins current behavior nor the eventual fix. *Suggested*: controller test asserting non-owner/non-member PATCH result (redirect w/ alert or 403).

Runner-ups worth noting: UC-JOB-001 edge cases .e1–.e6 (cleanup concurrency / FS drift), UC-V2-005 .e12–.e15 (empty layers, malformed config, namespace repo), UC-UI-008 (tag history — whole page untested), UC-UI-009 (help page has no controller test).

## Notes
- Test style is classical Minitest with Rails fixtures (`test/fixtures/*.yml`). Integration tests in `test/integration/*` use `ActionDispatch::IntegrationTest`.
- PAT integration tests use a `basic_auth_for` helper (seen in `test/controllers/v2/*_test.rb`) — good reuse pattern.
- OAuth tests use OmniAuth mocks (`OmniAuth.config.mock_auth[:google_oauth2]`) — consistent across sessions_controller_test.rb and auth_google_oauth_flow_test.rb.
- Anonymous-pull regression file (`test/integration/anonymous_pull_regression_test.rb`) doubles as the de-facto UC-AUTH-010 matrix — clean, enumerated table of endpoints.
- The `test/services/manifest_processor_test.rb` has excellent tag-protection edge-case coverage that complements the shallower controller-level tests.
- E2E specs live in `e2e/*.spec.js` (Playwright) and focus on visual/behavioral flows — cover dark mode, tag-protection UI, search. They do NOT replicate backend assertions (session cookies, HTTP headers).
- Surprising: no dedicated `test/controllers/help_controller_test.rb` despite `HelpController` existing at `app/controllers/help_controller.rb`.
- Surprising: PruneOldEventsJob is checked into `app/jobs/` with zero test file (UC-JOB-003 .e5 — plan already flagged).
- Surprising: Tag history route (`GET /repositories/:name/tags/:tag/history`) is wired in `app/controllers/tags_controller.rb:3` but never exercised in tests.
