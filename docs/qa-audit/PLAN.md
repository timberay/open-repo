# QA Audit Plan

**Goal:** Produce a user-facing feature manual, write use-cases (happy path + edge cases) for every feature, map coverage to existing tests, execute all suites (Ruby + Playwright E2E), and report pass/fail per feature.

**Scope:** Entire application (V2 Registry API, Web UI, Auth, Background jobs, Admin).
**Depth:** Edge cases included.
**Mode:** Autonomous — no further user prompts.

## Constraints
- Main thread keeps context lean: heavy exploration goes to sub-agents with strict output caps.
- Docs live under `docs/qa-audit/`. No other filesystem changes unless a test needs to be added in `test/` or `e2e/`.
- Results are evidence-based. Every pass/fail claim must cite the command that was run.

## Phases

### Phase 1 — Discovery (4 parallel agents)
Each agent scans one slice, writes a structured summary to `docs/qa-audit/discovery/<slice>.md`, and returns a short status message.

| Agent | Slice | Focus |
|---|---|---|
| A | V2 Registry API | `config/routes.rb` `v2/` block + `app/controllers/v2/` + docker client flows |
| B | Web UI | non-`v2/` routes + `app/controllers/*_controller.rb` + `app/views/` + `app/components/` + Stimulus controllers |
| C | Auth & Security | OAuth, PAT, bearer tokens, middleware, tag protection, authorization checks |
| D | Background + Data | `app/jobs/`, `app/services/`, `app/models/`, `config/recurring.yml`, plus map of existing `test/` and `e2e/` |

### Phase 2 — Consolidation (main thread)
- Merge discovery outputs into one authoritative `docs/qa-audit/USER_MANUAL.md`.
- Write `docs/qa-audit/TEST_PLAN.md` with use-cases per feature: happy path + edge cases + preconditions + expected observables.

### Phase 3 — Gap Analysis (1 agent)
- Cross-reference TEST_PLAN against existing `test/` and `e2e/` files.
- Output `docs/qa-audit/GAP_ANALYSIS.md`: for each use-case, which existing test covers it, or missing.

### Phase 4 — Execution
- Run the Ruby test suite (`bin/rails test` — or `rspec` if present).
- Run the Playwright E2E suite (`npx playwright test` against a running dev server).
- Capture outputs into `docs/qa-audit/run-logs/`.
- Do NOT add new tests in this pass — gap analysis flags them as "not covered" in the report; test authoring is a follow-up task (out of scope for this audit).

### Phase 5 — Report
- `docs/qa-audit/QA_REPORT.md`:
  - Summary table: feature → covered? → last-run result → gap notes
  - Per-feature detail with evidence links (test file path + line / Playwright spec name)
  - Top issues ranked by severity
  - Recommended follow-ups

## Non-goals
- Writing new tests to fill gaps (flagged but not filled).
- Refactoring source code.
- Performance benchmarks.
- Production canary verification.
