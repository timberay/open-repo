# Background, Data, and Test Coverage Discovery

## Models

| Model | Purpose | Key validations | Key callbacks | Notable scopes |
|---|---|---|---|---|
| User | User account record | email (uniqueness) | none | admin_email? class method |
| Identity | OAuth/auth provider link | provider (presence), uid (presence+uniqueness by provider), email (presence) | dependent destroy on PATs | none |
| Repository | Container image repository | name (uniqueness), tag_protection_pattern (regex if custom_regex) | clears pattern unless custom_regex, resets protection_regex cache | tag_protected?, enforce_tag_protection! |
| Tag | Ref to manifest within repo | name (presence+uniqueness per repo) | none | none |
| Manifest | Docker image manifest; owns layers | digest (uniqueness), media_type, payload, size | dependent destroy layers/pull_events; nullify tags | none |
| Layer | Ordered layer (blob ref) in manifest | position (uniqueness per manifest) | none | none |
| Blob | File content by SHA256 digest | digest (uniqueness), size | dependent destroy layers | none |
| BlobUpload | Resumable upload session | uuid (uniqueness) | none | none |
| PersonalAccessToken | API token | name (uniqueness per identity), token_digest (uniqueness), kind (cli/ci) | none | active (not revoked, not expired) |
| RepositoryMember | Access control: identity→repo | role (writer/admin) | none | none |
| TagEvent | Audit log: tag lifecycle | tag_name, action (create/update/delete/ownership_transfer), occurred_at | none | none (ordered by occurred_at in audit) |
| PullEvent | Audit log: pull ops | occurred_at | none | pruned by PruneOldEventsJob |

**Key relationships:**
- User → many Identities; Primary Identity backref
- Identity → many PATs (cascade delete), many RepositoryMembers (cascade delete)
- Repository → owns Tags, Manifests, TagEvents, BlobUploads; references owner_identity (restrict delete)
- Manifest → many Layers (destroy), many Tags (nullify), many PullEvents (destroy)
- Layer → Manifest + Blob; enforces unique (manifest_id, blob_id) and (manifest_id, position)
- Blob → many Layers (destroy)

---

## Services (non-auth)

| Service | Purpose | Public API (method signatures) | Side effects / IO | Errors raised |
|---|---|---|---|---|
| BlobStore | Filesystem abstraction for blob storage & upload sessions | `initialize(root_path=Rails.configuration.storage_path)`, `get(digest) → File`, `put(digest, io)`, `exists?(digest) → bool`, `delete(digest)`, `path_for(digest) → path`, `size(digest)`, `create_upload(uuid)`, `append_upload(uuid, io)`, `upload_size(uuid)`, `finalize_upload(uuid, digest)`, `cancel_upload(uuid)`, `cleanup_stale_uploads(max_age:1.hour)` | Writes blobs to disk in sharded dirs; creates/deletes upload session dirs; renames atomically | Errno::ENOENT (missing upload), DigestMismatch (verify fail) |
| DigestCalculator | Compute & verify SHA256 digests | `self.compute(io_or_string) → "sha256:..."`, `self.verify!(io, expected_digest)` | None (stateless) | Registry::DigestMismatch on verify fail |
| ManifestProcessor | Main manifest push logic: validates schema, stores blob refs, creates Tag/TagEvent, enforces tag protection | `initialize(blob_store=BlobStore.new)`, `call(repo_name, reference, content_type, payload, actor:) → Manifest` | DB writes (repository, manifest, tag, layers, tag_event, blob refs); filesystem (extracts config); row-locks repository; increments blob.references_count | Registry::ManifestInvalid (schema/blob validation), Registry::TagProtected (protection policy), JSON::ParserError (config parse) |

---

## Jobs

| Job | Trigger (recurring? enqueued from where?) | Cadence | What it does | Failure modes |
|---|---|---|---|---|
| CleanupOrphanedBlobsJob | Recurring via config/recurring.yml (SolidQueue) | every 30 minutes | Deletes Blob rows & filesystem entries where references_count == 0; destroys Manifests with no Tags (orphaned); calls BlobStore.cleanup_stale_uploads(max_age: 1.hour) | Blob with references_count > 0 reloaded during loop (race-safe); manifest destroy triggers cascading deletes of layers, which decrement blob refs; stale upload dir parse error ignored silently |
| EnforceRetentionPolicyJob | Recurring via config/recurring.yml | every day at 3am | If RETENTION_ENABLED env var is "true": finds Manifests with last_pulled_at < (RETENTION_DAYS_WITHOUT_PULL=90, default) days OR pull_count < (RETENTION_MIN_PULL_COUNT=5); deletes unprotected tags via TagEvent.create!(action:"delete"); respects tag_protection_policy (skips protected tags) | RETENTION_PROTECT_LATEST env var (default "true") protects "latest" tag; protected tags (semver, all_except_latest, custom_regex) are skipped; disabled by default (RETENTION_ENABLED=false) |
| PruneOldEventsJob | Recurring via config/recurring.yml | every day at 4am | Batch-deletes PullEvent rows older than 90 days; in_batches.delete_all (no N+1) | Silent no-op if no old events exist |

---

## Test coverage map

### Ruby tests (`test/`)

| Test file | File under test | Type | Rough # of test cases |
|---|---|---|---|
| models/user_test.rb | app/models/user.rb | model | ~10 |
| models/identity_test.rb | app/models/identity.rb | model | ~6 |
| models/repository_test.rb | app/models/repository.rb | model | 42 |
| models/tag_test.rb | app/models/tag.rb | model | ~4 |
| models/manifest_test.rb | app/models/manifest.rb | model | ~6 |
| models/layer_test.rb | app/models/layer.rb | model | ~6 |
| models/blob_test.rb | app/models/blob.rb | model | ~3 |
| models/blob_upload_test.rb | app/models/blob_upload.rb | model | ~4 |
| models/personal_access_token_test.rb | app/models/personal_access_token.rb | model | ~8 |
| models/repository_member_test.rb | app/models/repository_member.rb | model | ~8 |
| models/tag_event_test.rb | app/models/tag_event.rb | model | ~10 |
| models/pull_event_test.rb | app/models/pull_event.rb | model | ~3 |
| models/auth_forbidden_action_test.rb | (error handling) | model | ~2 |
| controllers/repositories_controller_test.rb | app/controllers/repositories_controller.rb | controller | ~12 |
| controllers/repositories_search_controller_test.rb | app/controllers/repositories_search_controller.rb | controller | ~4 |
| controllers/tags_controller_test.rb | app/controllers/tags_controller.rb | controller | ~6 |
| controllers/settings/tokens_controller_test.rb | app/controllers/settings/tokens_controller.rb | controller | ~4 |
| controllers/v2/base_controller_test.rb | app/controllers/v2/base_controller.rb | controller | ~4 |
| controllers/v2/blobs_controller_test.rb | app/controllers/v2/blobs_controller.rb | controller | ~4 |
| controllers/v2/blob_uploads_controller_test.rb | app/controllers/v2/blob_uploads_controller.rb | controller | ~6 |
| controllers/v2/manifests_controller_test.rb | app/controllers/v2/manifests_controller.rb | controller | 20 |
| controllers/v2/tags_controller_test.rb | app/controllers/v2/tags_controller.rb | controller | ~4 |
| controllers/v2/catalog_controller_test.rb | app/controllers/v2/catalog_controller.rb | controller | ~3 |
| controllers/concerns/repository_authorization_test.rb | app/controllers/concerns/repository_authorization.rb | controller | ~4 |
| services/blob_store_test.rb | app/services/blob_store.rb | service | 11 |
| services/digest_calculator_test.rb | app/services/digest_calculator.rb | service | ~5 |
| services/manifest_processor_test.rb | app/services/manifest_processor.rb | service | 14 |
| jobs/cleanup_orphaned_blobs_job_test.rb | app/jobs/cleanup_orphaned_blobs_job.rb | job | 2 |
| jobs/enforce_retention_policy_job_test.rb | app/jobs/enforce_retention_policy_job.rb | job | ~20 |
| integration/docker_basic_auth_test.rb | (end-to-end) | integration | ~6 |
| integration/first_pusher_race_test.rb | (race condition) | integration | ~4 |
| integration/rack_attack_auth_throttle_test.rb | (rate limiting) | integration | ~4 |
| integration/auth_google_oauth_flow_test.rb | (OAuth flow) | integration | ~3 |
| integration/auth_session_restore_test.rb | (session) | integration | ~3 |
| integration/anonymous_pull_regression_test.rb | (anonymous pulls) | integration | ~3 |
| integration/login_button_visibility_test.rb | (UI state) | integration | ~2 |
| integration/retention_ownership_interaction_test.rb | (retention + ownership) | integration | ~4 |
| components/badge_component_test.rb | app/components/badge_component.rb | component | ~4 |
| components/button_component_test.rb | app/components/button_component.rb | component | ~4 |
| components/card_component_test.rb | app/components/card_component.rb | component | ~4 |
| components/digest_component_test.rb | app/components/digest_component.rb | component | ~4 |
| components/input_component_test.rb | app/components/input_component.rb | component | ~4 |
| components/select_component_test.rb | app/components/select_component.rb | component | ~4 |
| components/textarea_component_test.rb | app/components/textarea_component.rb | component | ~4 |

**Totals (Ruby tests):**
- Model tests: 13 files, ~130 cases
- Controller tests: 12 files, ~70 cases
- Service tests: 3 files, 30 cases
- Job tests: 2 files, ~22 cases
- Integration tests: 8 files, ~32 cases
- Component tests: 7 files, ~28 cases
- **Total: ~312 test cases**

### Playwright E2E (`e2e/`)

| Spec file | User journey covered | Rough # of cases |
|---|---|---|
| tag-protection.spec.js | Tag protection policy enforcement (semver, all_except_latest, custom_regex); badge visibility; delete button disabled state | 5 |
| tag-details.spec.js | Tag detail view; pull count display; last pulled time | 4 |
| repository-list.spec.js | List repos; pagination; owner badge | 4 |
| search.spec.js | Global search by repo name/description | 3 |
| dark-mode.spec.js | Dark mode toggle; persistence | 2 |
| example.spec.js | (Example/template) | 1 |

**Totals (E2E specs):**
- 6 spec files, ~21 cases

---

## Edge cases worth testing (per job/service)

### CleanupOrphanedBlobsJob
- **Race condition**: blob references_count incremented after loop iteration but before reload → reload before destroy (mitigated by reload in loop)
- **Partial work**: job interrupted mid-batch → next run continues (BATCH_SIZE=100)
- **Orphaned manifests without tags**: correctly found by left_join on tags with null check
- **Stale upload session timezone handling**: Time.parse on ISO8601; timezone edge cases
- **Stale upload max_age.ago comparison**: handles DST, leap seconds
- **Filesystem race**: blob file deleted between exists? check and delete() → silently handled (FileUtils.rm_f)

### EnforceRetentionPolicyJob
- **Environment variables missing/invalid**: ENV.fetch with defaults; to_i coercion
- **Disabled by default**: RETENTION_ENABLED must be "true" (case-sensitive string check)
- **Protection policies**: semver pattern matching; all_except_latest special case; custom_regex compile errors
- **Multiple tags on same manifest**: each tag evaluated separately; only protected ones skipped
- **Tag with null actor_identity_id**: TagEvent.create! with actor: "retention-policy" (string, not Identity)
- **Concurrent tag deletes**: manifest.tags.find_each re-queries; safe from orphan rows if another process deletes tag
- **Pull count = 0, last_pulled_at = NULL**: both conditions checked with OR; NULL < threshold evaluates true

### PruneOldEventsJob
- **Large dataset**: in_batches.delete_all handles pagination automatically
- **90-day boundary edge case**: "< 90.days.ago" is strict inequality; events exactly 90 days old are NOT pruned
- **Zero events to delete**: silent no-op
- **Concurrent deletes**: delete_all uses batch iteration; safe

### BlobStore
- **Concurrent put(digest, io)**: return early if target exists (idempotent, safe for retries)
- **Upload interruption**: finalize_upload verifies digest; if verification fails, upload dir is NOT cleaned (manual cancel needed)
- **Chunk reading failure**: io.read() raises → exception bubbles; tmp file is cleaned (in rescue block)
- **IO rewind failure**: respond_to?(:rewind) check; StringIO always supports rewind; File handles lazy rewind
- **Very large blobs**: CHUNK_SIZE = 64KB; streaming handles any size
- **Filesystem full**: File.write or File.rename raises → caught in rescue; tmp cleaned

### DigestCalculator
- **String vs IO coercion**: handles both; rewinds IO if possible
- **Partial digest verification**: stream is rewound after compute; verify! re-reads entire stream
- **Large IO verify!**: CHUNK_SIZE=64KB; memory efficient

### ManifestProcessor
- **Concurrent manifest push (same digest, same repo)**: repository.with_lock ensures serialization; manifest.find_or_initialize_by is safe
- **Tag protection race**: existing_tag queried inside lock; enforce_tag_protection! called inside lock (Decision 1-A); prevents orphan manifests
- **Concurrent tag reassign (different manifests, same tag)**: manifest.update! inside lock; TagEvent created atomically
- **Config blob missing**: raises Registry::ManifestInvalid before any writes
- **Layer blob missing**: raises Registry::ManifestInvalid before any writes
- **Missing repository owner (admin_email not found)**: User.find_by! raises RecordNotFound (not rescued; deployment error)
- **Malformed config JSON**: JSON::ParserError caught; returns {architecture: nil, os: nil, config_json: nil} (fallback)
- **References count cascade**: Blob.increment! called per layer; destroy_all layers triggers decrement in BlobStore cleanup
- **Large payload bytesize**: size: payload.bytesize is computed; no overflow risk in Ruby
- **Repository creation race**: find_or_create_by! is atomic; multiple processes create once
- **Tag idempotency (CI retry)**: existing_tag && same digest → no TagEvent, no error (safe for kubectl apply retries)

---

## Coverage gaps at a glance

### Models with no dedicated test file
- ApplicationRecord (base model; no custom logic)

### Services with no test coverage
- Auth services (owned by auth agent): auth/provider_profile, auth/google_adapter, auth/session_creator, auth/pat_authenticator

### Jobs with no test coverage
- **PruneOldEventsJob** (critical data deletion job) — NO DEDICATED TEST FILE

### Controllers with minimal/no coverage
- (All tested, but some auth controllers tested via integration tests, not controller unit tests)

### Integration test gaps
- Concurrent manifest push under contention (e2e/first_pusher_race_test.rb exists; tests race, not retention+ownership interaction edge cases)
- Blob upload cancellation after interruption (BlobStore tested; ManifestProcessor tested; but upload session cancellation not e2e)
- Large manifest (100+ layers) processing
- Symlink/hardlink filesystem edge cases in BlobStore (no tests for unusual filesystems)

### E2E gaps
- Tag protection policy enforcement on API (V2 Registry DELETE) — covered by controller tests, not E2E
- Pull event creation & pruning (model/job tests only; no UI verification)
- Tag ownership transfer workflow (model test + integration test exist; no E2E)
- Repository deletion with cascading cleanup
- Personal access token expiry & revocation on pull
- Blob upload resumption after network failure (no E2E; BlobStore unit tested)

