# Development Workflow

> **Scope:** `WORKFLOW.md` governs the lifecycle of **one feature** through the six-phase pipeline. For the **project-level** lifecycle stage (Setup → Pilot → Launch → Maintenance → Archive), see `LIFECYCLE.md`. The two axes are orthogonal — every stage can run features through Phases 1–6; the stage only modifies posture, not mechanics.

## Pipeline Phases

New feature work flows through six phases: four design phases (1–4) that separate product, architecture, technical design, and task breakdown, followed by execution (5) and ship (6). Do NOT skip phases. A `UserPromptSubmit` hook reminds you when a feature request is detected.

> **Skill prerequisites.** Phases 3, 4, and 5 use **superpowers** skills which the template installer auto-installs (`superpowers:brainstorming`, `:writing-plans`, `:executing-plans`, `:test-driven-development`). Phases 1, 2, and 6 use **gstack** skills (`/office-hours`, `/plan-eng-review`, `/review`, `/ship`, `/land-and-deploy`, `/document-release`) which the installer **only verifies** — it expects gstack to be pre-installed at `~/.agents/skills/gstack/` or legacy `~/.claude/skills/gstack/`. If gstack is missing, either install it separately (see your team's gstack onboarding) or substitute the listed skill with manual product/architecture/release notes; the phase boundaries themselves still apply.

### Design phases (1–4)

> **Output directories**: Phase 1 and 2 are gstack skills; their outputs live under `~/.gstack/projects/<slug>/designs/` (per-developer, not committed). Phase 3 and 4 are superpowers skills; their outputs live in-repo under `docs/superpowers/` and ARE committed.

#### Phase 1 — Product Decision
- **Skill**: `/office-hours` (gstack)
- **Answers**: WHAT + WHY + WHO
- **Output**: `~/.gstack/projects/<slug>/designs/<feature>.md`
- **Forbidden**: tech stack, architecture, code

#### Phase 2 — System Architecture
- **Skill**: `/plan-eng-review` (gstack)
- **Answers**: data flow, failure modes, module boundaries
- **Output**: `~/.gstack/projects/<slug>/designs/<feature>-eng-review.md`
- **Forbidden**: file-level plan, task IDs, code snippets

#### Phase 3 — Technical Design
- **Skill**: `/superpowers:brainstorming`
- **Answers**: framework patterns, concurrency, caching, test strategy (see `STACK.md` for the language-specific concerns)
- **Input**: Phase 1 + Phase 2 docs (do not re-debate)
- **Output**: `docs/superpowers/specs/<YYYY-MM-DD>-<feature>-design.md`
- **Forbidden**: product re-debate, system boundary re-debate

#### Phase 4 — Task Breakdown
- **Skill**: `/superpowers:writing-plans`
- **Input**: Phase 3 doc (primary), Phase 1/2 (reference)
- **Output**: `docs/superpowers/plans/<YYYY-MM-DD>-<feature>.md`

### Execution phases (5–6)

#### Phase 5 — Execute
- **Skills**: `/superpowers:executing-plans` (drives the plan) + `/superpowers:test-driven-development` (per task)
- **Input**: Phase 4 plan
- **Forbidden**: implementing tasks not in the plan; if scope changes, return to Phase 4 and update the plan first

#### Phase 6 — Review → Ship → Deploy → Document
Run in this order; each gates the next:

1. `/review` — pre-landing diff review against base branch
2. `/ship` — run tests, bump version, create PR
3. `/land-and-deploy` — merge, deploy, verify production health
4. `/document-release` — sync README / CLAUDE.md / standards with what shipped

**Without gstack.** When `/ship` and `/land-and-deploy` are unavailable
(gstack not installed in the current environment), substitute the bundled
**`/push2gh`** project skill — it covers the commit → push → PR → optional
automerge → cleanup arc. It is language-neutral and is installed at
`.agents/skills/push2gh/SKILL.md` by `install.sh`; Claude Code also sees it
through the `.claude/skills` symlink. `/review` and
`/document-release` still need manual substitutes (a careful diff read and
a manual README/CHANGELOG sync respectively).

**No GitHub CI.** This repo runs its full pipeline locally — there is no
GitHub Actions backstop (see ADR-0001 and `QUALITY.md → Quality Gate
Layering`). Before pushing in step 2 (`/ship` or `/push2gh`), run `bin/ci`
and confirm it passes; `/push2gh` does not run the suite for you.

### Phase continuation rules
- If the user explicitly continues an in-progress phase (e.g., "Phase 3 계속", "플랜 수정", 이미 열려있는 design doc 편집), proceed without re-checking earlier phases.
- If the user explicitly overrides ("간단한 버그 수정이니 phase 건너뛰어"), confirm the task truly doesn't need the pipeline, then proceed.
- For bug fixes, refactors, and small tweaks, the pipeline does not apply. Use your judgment.

## Orchestrator hooks per phase

The Orchestrator mechanism (see `CLAUDE.md → Orchestrator (STATE + ADR)` and
`docs/decisions/ADR-0000-orchestrator-bootstrap.md`) integrates with the
six-phase pipeline at these points:

| Phase | Orchestrator action |
|---|---|
| 1 (Product) | On completion: `/decide` to capture WHAT/WHY as an ADR. The Phase 1 design doc itself stays under `~/.gstack/`, but the decision is preserved in-repo. |
| 2 (Architecture) | On completion: `/decide` for each major architectural choice (data flow, module boundaries, technology selection). |
| 3 (Technical Design) | Record the spec path in PROJECT_STATE.md "Current Phase / Active Spec" via `/state-sync` after writing the spec. |
| 4 (Task Breakdown) | Record the plan path in PROJECT_STATE.md "Current Phase / Active Plan" via `/state-sync`. |
| 5 (Execute) | `/state-sync` at logical checkpoints — not per task (too noisy), but when a substantial block of tasks lands. |
| 6 (Ship) | After merge: `/state-sync` to clear the shipped item from "Active Work". If the shipped work locked any new technical choices, run `/decide` to capture them. |

These are conventions, not blocking gates. Skip them only when the entire
pipeline is being skipped (bug fixes, refactors, tweaks).
