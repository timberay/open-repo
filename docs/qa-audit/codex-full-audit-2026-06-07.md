# Codex Full Feature Audit — Open Repo

- **Date:** 2026-06-07
- **Branch:** `main` (commit `262a396`)
- **Reviewer:** OpenAI Codex CLI (`/codex` consult mode, `model_reasoning_effort=medium`)
- **Scope:** Whole-codebase feature verification + prioritized improvement items
- **Codex session id:** `019e9ff3-41b4-70d2-92c7-490170fb6de0`
- **Tokens used:** 401,085

> Verdict legend: `[OK]` implemented & looks correct · `[BUG]` implemented but has a defect/gap · `[PARTIAL]` only partly implemented · `[MISSING]` claimed in README but absent in code.

---

## PART 1 — FEATURE VERIFICATION

- **Docker Registry V2 API:** `[BUG]` Core routes/controllers exist for push/pull, manifests, blobs, uploads, catalog, tags, HEAD, and pagination in `config/routes.rb:40`, `app/controllers/v2/manifests_controller.rb:13`, `app/controllers/v2/blob_uploads_controller.rb:2`, `app/controllers/v2/catalog_controller.rb:3`, and `app/controllers/v2/tags_controller.rb:3`. Gaps: upload UUIDs are global not repo-scoped (`app/controllers/v2/blob_uploads_controller.rb:90`), `Content-Range` is ignored (`app/controllers/v2/blob_uploads_controller.rb:29`), and cross-repo mount ignores `from` repo authorization/existence (`app/controllers/v2/blob_uploads_controller.rb:124`).
- **Web UI:** `[PARTIAL]` Repository browsing, metadata editing, tag protection, tag detail layer/config inspection, and tag history are implemented in `app/controllers/repositories_controller.rb:5`, `app/views/repositories/show.html.erb:51`, `app/views/tags/show.html.erb:70`, and `app/views/tags/history.html.erb:14`; tar import/export is absent and the tables were explicitly dropped in `db/migrate/20260424010032_drop_imports_and_exports_tables.rb:1`.
- **Service layer (`app/services`):** `[PARTIAL]` `BlobStore`, `DigestCalculator`, `ManifestProcessor`, and auth services exist (`app/services/blob_store.rb:1`, `app/services/digest_calculator.rb:1`, `app/services/manifest_processor.rb:1`, `app/services/auth/session_creator.rb:1`); README-claimed `TagDiffService` and `DependencyAnalyzer` are absent from `app/services`.
- **Background jobs + Solid Queue wiring:** `[OK]` Jobs exist for orphan cleanup, retention, and pull-event pruning (`app/jobs/cleanup_orphaned_blobs_job.rb:1`, `app/jobs/enforce_retention_policy_job.rb:1`, `app/jobs/prune_old_events_job.rb:1`); Solid Queue is configured in production (`config/environments/production.rb:52`) with recurring schedules in `config/recurring.yml:1`.
- **Retention policy:** `[OK]` Opt-in env-gated retention deletes stale low-pull tags, protects `latest`, and skips protected tags in `app/jobs/enforce_retention_policy_job.rb:4`.
- **Garbage collection:** `[BUG]` Cleanup deletes zero-ref blobs and orphan manifests in `app/jobs/cleanup_orphaned_blobs_job.rb:14`, but V2 blob delete removes referenced blobs (`app/controllers/v2/blobs_controller.rb:25`) and counters can go negative, making rows invisible to zero-ref cleanup (`test/models/blob_test.rb:41`).
- **Pull tracking & audit log:** `[PARTIAL]` GET manifest increments pulls and writes `PullEvent` (`app/controllers/v2/manifests_controller.rb:120`), tag mutations write `TagEvent` (`app/services/manifest_processor.rb:112`, `app/controllers/tags_controller.rb:14`), and UI shows tag history (`app/controllers/tags_controller.rb:30`); there is no UI for `PullEvent` history despite the audit-log claim.
- **Authentication / OAuth:** `[BUG]` Google OAuth and PAT auth are implemented (`config/initializers/omniauth.rb:1`, `app/controllers/auth/sessions_controller.rb:11`, `app/services/auth/pat_authenticator.rb:9`), but existing OAuth identities skip re-checking email verification/email consistency (`app/services/auth/session_creator.rb:7`; pinned as a documented gap in `test/services/auth/session_creator_test.rb:173`).

---

## PART 2 — IMPROVEMENT ITEMS (prioritized)

### P1 — critical (security, data loss, correctness)

1. `app/services/auth/session_creator.rb:7` — Re-validate `profile.email_verified == true` and update/compare stored identity email on every existing-identity login.
2. `app/controllers/v2/blob_uploads_controller.rb:90` — Scope upload lookup to `@repository.blob_uploads.find_by!(uuid: params[:uuid])` after resolving the repo from the request path.
3. `app/controllers/v2/blob_uploads_controller.rb:124` — Validate `params[:from]` resolves to a readable source repository that actually references the mounted digest before returning `201`.
4. `app/controllers/v2/blobs_controller.rb:25` — Refuse or safely no-op `DELETE /blobs/:digest` when `references_count > 0`; do not delete shared content-addressed files still used by manifests.
5. `app/controllers/repositories_controller.rb:5` — Require sign-in and apply read authorization to repository index/show/tag pages if repositories are intended to be private.

### P2 — important (tests, error handling, performance, races)

1. `app/services/manifest_processor.rb:91` — Decrement old layer blob reference counts before `manifest.layers.destroy_all` to avoid leaking refs on manifest reprocessing.
2. `app/models/blob.rb:1` — Add a model validation and DB check constraint for `references_count >= 0`.
3. `app/controllers/v2/blob_uploads_controller.rb:29` — Parse and enforce `Content-Range` against `BlobUpload#byte_offset`; return `416`/Docker error on mismatched chunks.
4. `app/controllers/v2/blob_uploads_controller.rb:41` — Validate `digest` presence/format before calling `BlobStore#finalize_upload`.
5. `app/controllers/v2/catalog_controller.rb:10` — Escape `last` in the `Link` header with URL encoding.
6. `app/controllers/v2/tags_controller.rb:11` — Escape repo name and `last` in the tag-list `Link` header.
7. `app/jobs/cleanup_orphaned_blobs_job.rb:15` — Use `where("references_count <= 0")` only after adding the nonnegative constraint and repairing bad counters.
8. `app/controllers/repositories_controller.rb:39` — Wrap repository destroy, tag/manifest deletion, and reference decrements in one transaction.
9. `app/controllers/tags_controller.rb:11` — Decrement manifest layer blob references when the last tag for a manifest is deleted, or enqueue cleanup immediately.
10. `app/controllers/v2/manifests_controller.rb:61` — Wrap manifest delete TagEvent creation, tag destroy, ref decrements, and manifest destroy in one transaction.
11. `app/views/tags/history.html.erb:14` — Add a repository/tag pull-events page or stop claiming detailed pull audit viewing in README.
12. `db/migrate/20260424010032_drop_imports_and_exports_tables.rb:1` — Restore import/export models/controllers/jobs or remove tar import/export from README.

### P3 — nice-to-have (refactors, docs alignment, code smells)

1. `README.md:48` — Remove or implement README claims for `TagDiffService`.
2. `README.md:49` — Remove or implement README claims for `DependencyAnalyzer`.
3. `app/controllers/v2/manifests_controller.rb:1` — Align README supported-format text with code, because code accepts OCI manifests but README says OCI is rejected.
4. `config/initializers/registry.rb:4` — Make `REGISTRY_ANONYMOUS_PULL` default match README; code defaults true while README says false.
5. `app/views/repositories/show.html.erb:48` — Change "Edit description & maintainer" text to mention tag protection, since the form edits it too.
6. `app/controllers/v2/blob_uploads_controller.rb:78` — Remove the race-loss auth bypass or replace it with a narrow ownership/write recheck after reload.

---

## SUMMARY

- **P1 = 5, P2 = 12, P3 = 6**
- **Most urgent fix:** revalidate existing Google OAuth identities on every login (`app/services/auth/session_creator.rb:7`).
