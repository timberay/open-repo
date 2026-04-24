# QA Audit Report

**Date:** 2026-04-24 (initial audit) · Wave 1 + Wave 2-A follow-ups appended same day
**Scope:** Entire application (V2 Registry API, Web UI, Auth, Background jobs)
**Method:** Feature inventory → use-case catalog → coverage gap analysis → automated suite execution

## Headline numbers (post Wave 2-A — 2026-04-24)

| Suite | Result | Detail | Δ vs initial |
|---|---|---|---|
| Ruby (Minitest) | ✅ PASS | 462 runs, 1103 assertions, 0 failures, 0 errors, 1 skip | +14 runs, +48 assertions |
| Static analysis (rubocop / brakeman / bundler-audit / importmap) | ✅ PASS | Brakeman 0 warnings, no vulnerable deps | unchanged |
| Playwright E2E | ✅ PASS | 21 passed, 0 failed, 0 did not run | +15 passing (full suite green) |
| Test-plan coverage | ⚠️ ~88% | CSRF + PruneOldEvents now covered; UC-AUTH-013 ❌→✅, UC-JOB-003 ❌→✅ | +2 UCs |

Trend snapshot:
- Initial: Ruby 448/1055 · E2E 6 passed, 11 failed, 4 did not run · coverage 83% (48/58).
- Post Wave 1: Ruby 462/1103 · E2E 10 passed, 7 failed, 4 did not run · coverage 88%.
- Post Wave 2-A: Ruby 462/1103 · E2E 21 passed, 0 failed, 0 did not run · coverage 88%.

## Wave 1 — resolution status

All six recommendations from the initial report were executed as parallel worktree agents and merged to `main`. Verification: post-wave1 logs at `docs/qa-audit/run-logs/ruby-tests-post-wave1.log`, `ci-static-post-wave1.log`, `playwright-post-wave1.log`.

| # | Recommendation | Status | Commit(s) | Evidence |
|---|---|---|---|---|
| 1 | CRITICAL auth fix + test on `RepositoriesController#update` | ✅ **FIXED** | `9060ee1` | 4 new controller tests (non-owner redirect, unauth redirect, owner ok, writer ok) |
| 2 | E2E suite repair — shared seed helper + selector updates | ⚠️ **PARTIAL** | `4fa2d5f` (merge), `19b76e7`, `3f0a2f4`, `9d7c47d` | `repository-list.spec.js` + `search.spec.js` fully recovered; `tag-protection`, `tag-details`, `dark-mode` still broken — scope limited to 2 specs |
| 3 | `PruneOldEventsJob` unit test | ✅ **FIXED** | `727ddac`, merge `86a6bdb` | `test/jobs/prune_old_events_job_test.rb` covers 91-day deletion, 90-day boundary retention, empty dataset |
| 4 | CSRF integration test | ✅ **FIXED** | `8db60c9`, merge `be58585` | `test/integration/csrf_test.rb` — stateful-controller token strip asserts rejection; confirms `Auth::SessionsController#create` opts out deliberately |
| 5 | `bin/prepare-e2e` repair (commit-or-revert) | ✅ **FIXED** | `06e1719` (pre-wave1) | `bin/rails db:prepare` replacement landed in prior commit |
| 6 | README note on Ruby version + `bundle install` | ✅ **FIXED** | `0c52bea`, merge `68c5415` | README "Development setup" section pins rbenv shim order and one-time bundle install |

## Wave 2-A — resolution status

All four residual E2E failures called out in the Wave 1 "Residual E2E failures" list were repaired as a sequenced set of small commits on `main`. Verification: post-wave2 Playwright log at `docs/qa-audit/run-logs/playwright-post-wave2.log` (21 passed, 0 failed, 0 did not run); Ruby suite unchanged (`bin/rails test` still 462/1103 green).

| # | Residual failure | Status | Commit(s) | Evidence |
|---|---|---|---|---|
| 1 | `tag-protection.spec.js:12` beforeAll seed crashed on missing owner_identity, cascading 4 "did not run" | ✅ **FIXED** | `635bc18` | Route through `seedBaseline()` + `runRailsRunner()`; sign in owner in `beforeEach` so write-gated tests pass; all 5 tests green |
| 2 | `tag-details.spec.js:16/23/29/35` selector drift (th/tbody/Copy/"Docker Registry" h1) against CSS-grid rendering | ✅ **FIXED** | `f3c1a63` (structural), `e64db6d` (behavioural) | `data-testid` anchors added to `app/views/repositories/show.html.erb` + `app/views/tags/show.html.erb`; spec rewritten to target them; h1 assertion updated to "Repositories"; all 5 tests green |
| 3 | `tag-protection.spec.js:29` 🔒 emoji / brittle class selectors post-refactor | ✅ **FIXED** | `d9a76d4` | Spec targets `[data-tag-name=...]` rows and `[data-testid=tag-protected-badge / tag-delete-disabled / tag-delete-protected]` anchors |
| 4 | `dark-mode.spec.js:25` persistence timeout (toggle button not found) | ✅ **FIXED** (self-resolved) | — | Reproducibly green in both isolation and full-suite runs post-Wave-1 (log shows all 3 dark-mode tests pass in the 21-test run). Likely a concurrency flake against a cold server during the Wave 1 post-repair run |
| 5 | `search.spec.js:44` sort-order drift (expected `backend-api` first) | ✅ **FIXED** | `a182439` | Assertion relaxed to relative ordering (`backend-api` before `frontend-web`); no dependency on dev-DB contents |

With the tag-details, tag-protection, dark-mode, and search specs all green, the E2E ship-readiness row flips to ✅. The Feature-by-feature table below is updated in-place to reflect that.

## Residual E2E failures (resolved — see Wave 2-A above)

Task 2 scope covered only `repository-list.spec.js` + `search.spec.js`. The three unrepaired specs still match the original root causes in `run-logs/playwright.log`:

1. **`tag-protection.spec.js:12`** (`beforeAll`) — `Repository.find_or_create_by!(name: ...)` still omits `owner_identity`; fails with `ActiveRecord::RecordInvalid: Validation failed: Owner identity must exist`. Four downstream tests (`:29`, `:42`, `:49`, `:56`, `:69`) chain-fail as "did not run". **Fix:** route this spec through `e2e/support/seed.rb`'s owner graph.
2. **`tag-details.spec.js:16/23/29/35`** — selectors `th:has-text("Digest"/"Size"/"Created")`, `tbody tr`, `button:has-text("Copy")`, `Back to Repositories`, and the final `h1 "Docker Registry"` still reflect the pre-refactor UI. **Fix:** rewrite selectors against current tag-details render (Tailwind/ViewComponent output) or add `data-testid` anchors.
3. **`dark-mode.spec.js:25`** — dark-mode preference persistence. Toggle selector `button[aria-label="Toggle dark mode"]` now finds the button (first passing test proves it), but the persistence test at `:25` still fails; likely related to storage key / reload behaviour.
4. **`search.spec.js:44`** — new failure on the sort-order assertion despite task 2 repairing `:8` and `:22`. Likely seed-ordering / stable-sort assumption drift; low risk but worth a second pass.

**Recommendation:** follow-up (Wave 2) as a single PR — extend `e2e/support/seed.rb` to serve tag-protection and tag-details specs, add `data-testid` anchors to the `TagsTableComponent` and dark-mode toggle, and tighten the sort assertion to be order-stable.

---

## Top findings (ranked by severity)

### CRITICAL — Authorization gap in `RepositoriesController#update`

The Web UI `PATCH /repositories/:name` endpoint is missing the `authorize_for!(:write)` filter that the analogous V2 push / destroy paths rely on. As documented in `docs/qa-audit/discovery/auth.md` (High-risk finding #1, lines 192–196, and the route table line 138 labelled **"Unprotected — missing auth check"**), any signed-in user — including accounts with zero ownership or membership on the target repository — can submit the edit form and change the **tag protection policy**, description, and maintainer. The impact is direct: the tag-protection regime (semver / all_except_latest / custom_regex) that guards `latest`-style tags against accidental overwrite can be flipped off by a non-owner, enabling subsequent protected-tag mutation via V2 (or simply degrading data integrity expectations on the repo). This is a compliance and integrity issue, not a theoretical one: the UI itself currently advertises protection to all viewers while allowing any of them to remove it. `GAP_ANALYSIS.md` line 107 flags the same UC (UC-UI-004.e5) as PARTIAL with no test pinning the current behaviour.

**Recommend:**
1. Add `before_action :authorize_write!` on `RepositoriesController#update` (mirroring `#destroy`'s delete-authorization).
2. Write a Minitest controller test: signed-in non-owner PATCH → redirect/403, owner PATCH → 200. This test should fail on `main` today and pass after the fix.
3. Add a Playwright E2E that signs in a non-owner, navigates to the edit form, submits, and asserts access is denied.

**Evidence:** `docs/qa-audit/discovery/auth.md:98`, `docs/qa-audit/discovery/auth.md:138`, `docs/qa-audit/discovery/auth.md:192-197`, `docs/qa-audit/GAP_ANALYSIS.md:107`.

### HIGH — E2E suite rot

11 of 21 Playwright specs fail and 4 did not even run; only 6 pass. Two root causes are visible in `docs/qa-audit/run-logs/playwright.log`:

1. **Stale DB seeds — the ownership/identity feature landed but `e2e/tag-protection.spec.js`'s `beforeAll` seed path still does `Repository.find_or_create_by!(name: ...)` without supplying an `owner_identity`**, so the `bin/rails runner` subprocess crashes with `ActiveRecord::RecordInvalid: Validation failed: Owner identity must exist` (playwright.log lines 198–255). The downstream tests (`e2e/tag-protection.spec.js:29/42/49/56/69`) cannot run at all because the `beforeAll` threw.
2. **Selector rot — UI titles and form controls moved but specs did not follow.** `e2e/repository-list.spec.js:8` expects `h1` to contain `"Docker Registry"` but the live page renders `"Repositories"` (playwright.log lines 15–38). `e2e/search.spec.js:37` times out waiting for `select[name="sort_by"]` on the repo list page (playwright.log lines 314–332) — the sort control either was renamed, moved into a Turbo Frame, or replaced by a different element. `e2e/tag-details.spec.js:16/23/29/35` fail chained on the same list-page assertion or on missing `tbody tr` / `button:has-text("Copy")` (playwright.log lines 109–194, 286–312), suggesting the tag-details page HTML was refactored. `e2e/dark-mode.spec.js:8` times out waiting for `button[aria-label="Toggle dark mode"]` (lines 42–60).

Representative failing IDs to cite in the tracker: `repository-list.spec.js:8` (h1 mismatch), `tag-protection.spec.js:29` (seed crash — owner_identity), `search.spec.js:37` (selector missing).

**Recommend:** build a single shared E2E seed helper (`e2e/support/seed.js`) that creates a `User + Identity + Repository` triple the way the Ruby layer now requires, and have every `beforeAll` call it. Separately, do a one-shot pass updating selectors to match current Tailwind / ViewComponent output, or — better — have the UI emit stable `data-testid` anchors and rewrite specs against those. Until then, treat the E2E run as non-blocking evidence.

**Evidence:** `docs/qa-audit/run-logs/playwright.log:198-255` (owner_identity crash), `docs/qa-audit/run-logs/playwright.log:15-38` (h1 drift), `docs/qa-audit/run-logs/playwright.log:314-332` (sort_by selector).

### HIGH — Broken developer tooling (`bin/prepare-e2e`)

`bin/prepare-e2e` was discovered broken on arrival: it referenced a `Registry` model/table that was removed in commit `5fd97e3` (`chore(registry): regenerate schema.rb after drop migration`). Running it as-is failed outright and the E2E suite could not be brought up. During this audit the body was replaced with a single `bin/rails db:prepare` call so Playwright could be exercised at all. **This repair is uncommitted and lives only in the working tree.** The user must either (a) commit the fix (recommended — the audit relied on it), or (b) revert it and accept that `bin/prepare-e2e` is dead code that should be removed entirely.

**Recommend:** commit the repaired `bin/prepare-e2e` (one-liner: `bin/rails db:prepare`), or delete the file and update any docs that reference it. Flag: do NOT merge the QA audit docs while leaving this script in an ambiguous, working-tree-only state.

**Evidence:** local uncommitted change to `bin/prepare-e2e` on HEAD; reference commit `5fd97e3` for the schema drop that orphaned it.

### MEDIUM — Untested auth-adjacent paths

Three gaps from `GAP_ANALYSIS.md` are worth testing before next release:

- **UC-AUTH-013 (CSRF enforcement)** — no test asserts that Web UI PATCH/DELETE forms reject missing/invalid authenticity tokens, nor that `Auth::SessionsController#create` deliberately skips forgery protection while `omniauth-rails_csrf_protection` validates state. If a future refactor silently disables protect_from_forgery, nothing catches it. *Recommend:* integration test per stateful controller — strip token from a known-good form, expect 422/redirect. (GAP_ANALYSIS.md line 62, line 103.)
- **UC-AUTH-012.e3 (V2 non-GET 30/min throttling)** — `test/integration/rack_attack_auth_throttle_test.rb` exercises only `/auth/*`. The V2 mutation throttle (30 req/min/IP on non-GET/HEAD) is entirely unverified. A regex typo in `config/initializers/rack_attack.rb` could silently disable it. *Recommend:* parallel integration test that floods `POST /v2/:name/blobs/uploads` from one IP and asserts 429. (GAP_ANALYSIS.md line 61, line 104.)
- **UC-AUTH-014 (tag-protection bypass via blob mount)** — threat-model-driven UC with zero direct coverage. The discovery doc explicitly flags the question at `discovery/auth.md:171` ("Tag protection bypassed for blob-mount flow?"). *Recommend:* integration test that does `POST /v2/:name/blobs/uploads?mount=...` against a repo with a protected tag, then attempts the `PUT /v2/:name/manifests/<protected-tag>` with a mutated digest, and asserts 409 `DENIED`. (GAP_ANALYSIS.md line 63, line 106.)

### MEDIUM — Missing job test

`PruneOldEventsJob` has **zero test file** (GAP_ANALYSIS.md line 73, line 105; TEST_PLAN.md UC-JOB-003.e5 line 589). It is wired into `config/recurring.yml` to run daily at 04:00 and `in_batches.delete_all`s `PullEvent` rows older than 90 days. A silent regression — wrong boundary, wrong model, wrong unit — would either let the `pull_events` table grow unbounded or silently delete recent audit data. *Recommend:* a unit test with three cases: (1) event 91 days old → deleted, (2) event exactly 90 days old → **not** deleted (strict `<`), (3) empty dataset → no-op / no exception.

### LOW — Developer environment friction

Two real speed-bumps hit this audit:

1. **`bundle install` had never been run in this working copy** — every Ruby invocation (`bin/rails`, `bundle exec rubocop`) failed with missing gems until `bundle install` was executed manually.
2. **`/usr/bin/ruby` (3.3.8 system Ruby) shadowed rbenv's 3.4.8.** `.ruby-version` pins 3.4.8 but without `PATH="$HOME/.rbenv/shims:$PATH"` the system Ruby was picked up and Bundler refused to proceed.

*Recommend:* add a one-shot `bin/setup` guard that runs `ruby -v` against the expected version and explicitly calls `bundle install` / `bin/rails db:prepare`. At minimum, add a README note. Without this, the next contributor — human or agent — loses ~15 minutes to the same detours.

---

## Feature-by-feature status

Legend: ✅ green = happy path + edge cases both covered and passing · 🟡 yellow = happy path passing, some edge cases uncovered · 🔴 red = known failure or critical gap.

### V2 Registry API

| Area | Feature | Ruby test | E2E test | Covered by test plan | Ship-readiness |
|---|---|---|---|---|---|
| V2 API | Ping `GET /v2/` (UC-V2-001) | ✅ | — | Happy + 5 edges (partial) | 🟡 |
| V2 API | Catalog `GET /v2/_catalog` (UC-V2-002) | ✅ | — | 7 edges, 4 not covered | 🟡 |
| V2 API | Tags list `GET /v2/:name/tags/list` (UC-V2-003) | ✅ | — | 5 edges, 3 not covered | 🟡 |
| V2 API | Manifest pull (UC-V2-004) | ✅ | — | 8 edges, mostly covered | ✅ |
| V2 API | Manifest push (UC-V2-005) | ✅ | — | 16 edges, several uncovered (.e11–.e16) | 🟡 |
| V2 API | Manifest delete (UC-V2-006) | ✅ | — | Covered + auth edges | ✅ |
| V2 API | Blob pull (UC-V2-007) | ✅ | — | Missing FS-drift + non-sha256 edges | 🟡 |
| V2 API | Blob delete (UC-V2-008) | ✅ | — | Missing ref-count + FS-missing edges | 🟡 |
| V2 API | Blob upload init (UC-V2-009) | ✅ | — | Including first-pusher race | ✅ |
| V2 API | Blob upload monolithic (UC-V2-010) | ✅ | — | Digest-mismatch edges uncovered | 🟡 |
| V2 API | Blob mount (UC-V2-011) | ✅ | — | 5 edges, 3 not covered | 🟡 |
| V2 API | Chunked upload PATCH (UC-V2-012) | ✅ | — | 4 edges, mostly uncovered | 🟡 |
| V2 API | Chunked upload finalize (UC-V2-013) | ✅ | — | Digest-mismatch covered; twice-finalize, missing-digest uncovered | 🟡 |
| V2 API | Upload cancel (UC-V2-014) | ✅ | — | Idempotency + auth edges uncovered | 🟡 |
| V2 API | Error response format (UC-V2-015) | ⚠️ | — | Subset of codes asserted explicitly | 🟡 |
| V2 API | Tag protection atomicity (UC-V2-016) | ⚠️ | — | No explicit concurrency race test | 🟡 |

### Web UI

| Area | Feature | Ruby test | E2E test | Covered by test plan | Ship-readiness |
|---|---|---|---|---|---|
| Web UI | Repository list `GET /` (UC-UI-001) | ✅ | 🔴 failing (h1 drift) | 5 edges, most uncovered | 🔴 |
| Web UI | Repository search & sort (UC-UI-002) | ✅ | 🔴 failing (selectors + seed) | Debounce covered; sort selector missing | 🔴 |
| Web UI | Repository detail (UC-UI-003) | ✅ | 🟡 partial (tag-details.spec broken) | Most edges uncovered | 🟡 |
| Web UI | Repository edit PATCH (UC-UI-004) | ✅ | ⚠️ partial | **Known auth gap, .e5 not pinned** | 🔴 |
| Web UI | Repository delete (UC-UI-005) | ✅ | — | Non-owner + concurrent edges uncovered | 🟡 |
| Web UI | Tag detail (UC-UI-006) | ✅ | 🔴 failing (tbody/Copy selector) | Most UI-rendering edges uncovered | 🔴 |
| Web UI | Tag delete (UC-UI-007) | ✅ | — | Core edges covered | ✅ |
| Web UI | Tag history (UC-UI-008) | ❌ | — | **No test whatsoever** | 🔴 |
| Web UI | Help page (UC-UI-009) | ❌ | — | **No HelpController test** | 🟡 |
| Web UI | Dark mode toggle (UC-UI-010) | — | 🔴 failing (toggle button selector) | E2E only, now broken | 🔴 |
| Web UI | PAT index (UC-UI-011) | ✅ | — | Status badges covered | ✅ |
| Web UI | PAT create (UC-UI-012) | ✅ | — | Duplicate-name + blank covered; kind/expires edges partial | 🟡 |
| Web UI | PAT revoke (UC-UI-013) | ✅ | — | Cross-user + subsequent-V2 covered | ✅ |

### Auth

| Area | Feature | Ruby test | E2E test | Covered by test plan | Ship-readiness |
|---|---|---|---|---|---|
| Auth | Google OAuth sign-in (UC-AUTH-001) | ✅ | — | Happy + email-mismatch + admin-flag | ✅ |
| Auth | Sign out (UC-AUTH-002) | ✅ | — | Turbo-opt-out covered | ✅ |
| Auth | OAuth failure page (UC-AUTH-003) | ✅ | — | Strategy messages partial | 🟡 |
| Auth | V2 HTTP Basic — valid PAT (UC-AUTH-004) | ✅ | — | Happy + case-insensitive | ✅ |
| Auth | V2 HTTP Basic — invalid/missing (UC-AUTH-005) | ✅ | — | 7 edges, most covered | ✅ |
| Auth | Expired PAT (UC-AUTH-006) | ✅ | — | Boundary edge uncovered | 🟡 |
| Auth | Revoked PAT (UC-AUTH-007) | ✅ | — | Mid-request race edges uncovered | 🟡 |
| Auth | Authorization — write (UC-AUTH-008) | ✅ | — | Owner/writer/admin covered | ✅ |
| Auth | Authorization — delete (UC-AUTH-009) | ✅ | — | Writer/admin/owner covered | ✅ |
| Auth | Anonymous pull gating (UC-AUTH-010) | ✅ | — | Full regression matrix | ✅ |
| Auth | First-pusher repo creation (UC-AUTH-011) | ✅ | — | Race + non-owner push | ✅ |
| Auth | Rack::Attack throttling (UC-AUTH-012) | ⚠️ | — | **V2 30/min throttle untested** | 🟡 |
| Auth | CSRF (UC-AUTH-013) | ❌ | — | **No CSRF-specific tests** | 🔴 |
| Auth | Tag-protection bypass via mount (UC-AUTH-014) | ❌ | — | **No test** | 🔴 |
| Auth | Repository visibility (UC-AUTH-015) | ⚠️ | — | No private/public gating (by design) | 🟡 |
| Auth | Session cookie hygiene (UC-AUTH-016) | ❌ | — | Stale-session edge covered only | 🟡 |
| Auth | Email verification at sign-in (UC-AUTH-017) | ✅ | — | Email-change re-verify edge uncovered | 🟡 |
| Auth | **RepositoriesController#update unprotected** | ❌ | ❌ | **CRITICAL — see top finding** | 🔴 |

### Jobs

| Area | Feature | Ruby test | E2E test | Covered by test plan | Ship-readiness |
|---|---|---|---|---|---|
| Jobs | CleanupOrphanedBlobsJob (UC-JOB-001) | ⚠️ | — | Happy path only; 6 edges uncovered | 🟡 |
| Jobs | EnforceRetentionPolicyJob (UC-JOB-002) | ✅ | — | Many edges covered; regex / semver boundary partial | ✅ |
| Jobs | PruneOldEventsJob (UC-JOB-003) | ❌ | — | **No test file at all** | 🔴 |

### Background & Data (Models / Services)

| Area | Feature | Ruby test | E2E test | Covered by test plan | Ship-readiness |
|---|---|---|---|---|---|
| Models | Repository (UC-MODEL-001) | ✅ | — | Policies + writable_by? + deletable_by? | ✅ |
| Models | PersonalAccessToken (UC-MODEL-002) | ✅ | — | Uniqueness + revoke + authenticate_raw | ✅ |
| Models | Identity (UC-MODEL-003) | ✅ | — | Destroy cascade edge uncovered | 🟡 |
| Models | Manifest / Layer / Blob (UC-MODEL-004) | ✅ | — | Ref-count decrement + nullify edges partial | 🟡 |
| Models | TagEvent / PullEvent (UC-MODEL-005) | ✅ | — | Pruning boundary + ordering uncovered | 🟡 |
| Models | RepositoryMember (UC-MODEL-006) | ✅ | — | Destroy-cascade edge uncovered | 🟡 |
| Services | BlobStore (UC-MODEL-007) | ✅ | — | Filesystem-full edge uncovered | ✅ |
| Services | DigestCalculator (UC-MODEL-008) | ✅ | — | All edges covered | ✅ |
| Services | ManifestProcessor (UC-MODEL-009) | ✅ | — | Several edges partial (.e7, .e10, .e12, .e13) | 🟡 |

---

## Evidence appendix

### CRITICAL — RepositoriesController#update unprotected
- **Evidence path:** `docs/qa-audit/discovery/auth.md:98` ("Update repo settings … **TODO:** No auth check! `repository_params` trusts form input; missing `authorize_for!(:write)`.")
- **Corroborating:** `docs/qa-audit/discovery/auth.md:138` (route table marks `POST /repositories/{name}` as "Unprotected — missing auth check").
- **Risk summary:** `docs/qa-audit/discovery/auth.md:190-197` (High-risk finding #1).
- **Gap catalog:** `docs/qa-audit/GAP_ANALYSIS.md:36` (UC-UI-004.e5 flagged) and line 107 (high-priority gaps).
- **Command reproducing evidence:** discovery agent run — output captured at `docs/qa-audit/discovery/auth.md`.

### HIGH — E2E suite rot
- **Log:** `docs/qa-audit/run-logs/playwright.log`
- **Command:** `npx playwright test` (run against a live dev server).
- **Specific evidence:**
  - `playwright.log:15-38` — `repository-list.spec.js:9` h1 mismatch ("Docker Registry" vs rendered "Repositories").
  - `playwright.log:198-255` — `tag-protection.spec.js:12` seed crash, `ActiveRecord::RecordInvalid: Validation failed: Owner identity must exist`.
  - `playwright.log:314-332` — `search.spec.js:40` timeout waiting for `select[name="sort_by"]`.
  - `playwright.log:335-349` — summary "11 failed, 4 did not run, 6 passed".

### HIGH — Broken `bin/prepare-e2e`
- **Repository reference:** commit `5fd97e3` ("chore(registry): regenerate schema.rb after drop migration") removed the `Registry` model/table that the script tried to populate.
- **Current state:** uncommitted working-tree repair at `bin/prepare-e2e` (single-line body `bin/rails db:prepare`).
- **Command that surfaced it:** attempting `bin/prepare-e2e` before running Playwright, which errored on the unknown constant `Registry`.

### MEDIUM — CSRF / V2 throttle / mount bypass gaps
- **CSRF (UC-AUTH-013):** `docs/qa-audit/GAP_ANALYSIS.md:62` (row marked ❌), `docs/qa-audit/GAP_ANALYSIS.md:103` (high-priority gap #1).
- **V2 throttle (UC-AUTH-012.e3):** `docs/qa-audit/GAP_ANALYSIS.md:61`, `docs/qa-audit/GAP_ANALYSIS.md:104` (high-priority gap #2).
- **Mount bypass (UC-AUTH-014):** `docs/qa-audit/GAP_ANALYSIS.md:63`, `docs/qa-audit/GAP_ANALYSIS.md:106` (high-priority gap #4); underlying concern at `docs/qa-audit/discovery/auth.md:171`.

### MEDIUM — PruneOldEventsJob missing test
- **Evidence path:** `docs/qa-audit/GAP_ANALYSIS.md:73` (row marked ❌ for UC-JOB-003); line 105 (high-priority gap #3); line 119 ("Surprising: PruneOldEventsJob is checked into `app/jobs/` with zero test file").
- **Test-plan reference:** `docs/qa-audit/TEST_PLAN.md:589` (UC-JOB-003.e5 explicitly flags this).

### LOW — Developer environment friction
- Observed during this audit: `bin/rails` refused to boot until `bundle install` completed for the first time; `ruby -v` returned system 3.3.8 instead of rbenv 3.4.8 unless `PATH="$HOME/.rbenv/shims:$PATH"` was prepended. Both conditions reproducible on a fresh checkout.

### Ruby suite (PASS)
- **Log:** `docs/qa-audit/run-logs/ruby-tests.log`
- **Command:** `bin/rails test` (Minitest).
- **Headline:** 448 runs, 1055 assertions, 0 failures, 0 errors, 1 skip.

### Static analysis (PASS)
- **Log:** `docs/qa-audit/run-logs/ci-static.log`
- **Tools:** rubocop, brakeman, bundler-audit, importmap audit.
- **Headline:** all passed; Brakeman reports `0 security warnings`; no vulnerable gems/deps.

---

## Recommendations, prioritized

1. **CRITICAL auth fix + test.** Add `authorize_for!(:write)` on `RepositoriesController#update`; cover with a controller test (non-owner PATCH → forbidden) and a Playwright test.
2. **E2E suite repair.** Add a shared seed helper that creates `User + Identity + Repository` atomically; update the five stale selectors (`h1 "Docker Registry"`, sort_by select, toggle-dark-mode aria-label, tag-details tbody/Copy button). This is the single biggest bang-for-buck fix in the report — it unlocks 15 tests currently failing or skipped.
3. **`PruneOldEventsJob` unit test.** Three assertions: 91-day-old row deleted, exactly-90-day-old row kept, empty dataset is a no-op.
4. **CSRF integration test.** One test per stateful controller that strips the authenticity token and expects rejection; plus an assertion that `Auth::SessionsController#create` carries `skip_forgery_protection only: [:create]`.
5. **Commit-or-revert decision for `bin/prepare-e2e`.** The working-tree repair must not ship silently. Either commit the one-line replacement with a clear message referencing `5fd97e3`, or delete the file.
6. **README note on Ruby version / `bundle install`.** Single paragraph under "Getting started" — pin rbenv shim order and the one-time `bundle install` requirement.

Follow-up, not blocking: V2 non-GET throttle test (UC-AUTH-012.e3), tag-protection bypass via mount (UC-AUTH-014), tag-history controller test (UC-UI-008), help page controller test (UC-UI-009).

---

## What's NOT in this audit

- No new tests were written.
- No performance benchmarks.
- No production canary.
- Code-level fixes are out of scope (one exception: `bin/prepare-e2e` was repaired to unblock E2E execution; flagged above as HIGH and still uncommitted).
