# Project Lifecycle Stages

> One project, one stage. The Lifecycle Stage answers "where is the project right now?" — orthogonal to the per-feature six-phase pipeline in `WORKFLOW.md`. `PROJECT_STATE.md` carries the current value; this file defines what each value means.

## Stages

| Stage | Meaning | Entry signal | Exit signal |
|---|---|---|---|
| **Setup** | Scaffolding, environment, toolchain. No domain logic yet. | `git init` / `install.sh` completion (auto) | First domain-code commit lands |
| **Pilot** | Core scenario runs end-to-end. Internal / early users only. Fragile. | First commit running the main use case — user declaration | Intended external users start to depend on it |
| **Launch** | External / production users. SLA and operational ownership exist. Changes are deliberate. | First deploy exposed externally — user declaration | New-feature work largely stops |
| **Maintenance** | No major new work. Upkeep and incremental improvement. | After Launch, when feature-work cadence drops — user declaration | Project sunset decision |
| **Archive** | No longer actively developed or operated. Code retained, no changes. | Sunset decision ADR | (terminal) |

## Rules

1. **Monotonic forward, skips allowed.** A library may go `Setup → Pilot → Maintenance` (no Launch). A PoC may go `Setup → Pilot → Archive`. Backward transitions are illegal — a Launch→Pilot regression requires a "regression ADR" (see Edge cases).
2. **Transitions are confirmed by user declaration.** Entry signals are guidance; the transition is real only after `/state-sync` updates `PROJECT_STATE.md` (and, where required, a `/decide` ADR lands).
3. **Stage is orthogonal to Feature Phase.** A project at Stage = Pilot can still run any feature through Phases 1–6 of `WORKFLOW.md`.

## Transition obligations

| Transition | Required | Recommended |
|---|---|---|
| Setup → Pilot | `/state-sync` (header update) | Short ADR for first domain feature (optional) |
| Pilot → Launch | `/decide` ADR (**required**) + `/state-sync` + README updated for external audience | Deployment / ops procedure, SLA |
| Launch → Maintenance | `/decide` ADR (**required**) + `/state-sync` | `Out of Scope` section refreshed |
| Maintenance → Archive | `/decide` ADR (**required**) + `/state-sync` + README marked "archived" | Sunset retrospective |
| Forward skip | Destination transition's required artifacts only | — |

Setup → Pilot is frequent and low-stakes (no ADR). Skipped stages mean the stage *never applied* (a library is never in Launch; a PoC is never in Maintenance).

## Stage posture (AI default behavior)

AI sessions that read `PROJECT_STATE.md` MUST adopt the posture matching the current stage. If a user request conflicts with the stage's posture, surface the conflict and offer to either defer the request or transition the stage first.

| Stage | Default posture | Lean into | Push back on |
|---|---|---|---|
| **Setup** | Foundation-first | Build env, linter, CI, scaffolding, repo layout | Domain features before tooling exists |
| **Pilot** | Speed over rigor | Rapid prototyping, end-to-end core scenario, interface churn | Strict coverage / exhaustive edge cases / formal migration plans |
| **Launch** | Stability + backwards compatibility | Tests, migration plans, changelogs, user-impact review on every breaking change | "Just rewrite it" / "let's break the API" without migration + ADR |
| **Maintenance** | Bug fixes and refactors only | Defects, security patches, dependency upkeep, incremental polish | New features (suggest transitioning out of Maintenance first) |
| **Archive** | Read-only | Questions, archaeology, doc updates clarifying the archived state | All code changes (require Reactivation ADR returning the project to Pilot) |

These are defaults — the user can override with explicit instruction. The point is that the default matches the project's operational reality.

## Edge cases

- **Library (npm / gem / pypi):** `Setup → Pilot → Maintenance` (Launch skipped — no external operational burden).
- **PoC / learning project:** `Setup → Pilot → Archive` is normal.
- **Reactivation (Archive → active):** New ADR declaring re-entry to Pilot. `since` resets to the re-entry date; prior entry preserved in the ADR body.
- **Launch → Pilot regression (severe defect found):** Separate "regression to Pilot" ADR (not `/supersede`) — updates the stage slot.
- **Monorepo (N projects in one repo):** Out of scope — repo split recommended. The template assumes 1 repo = 1 project.
- **Bug fixes / refactors only:** No stage change. Stage tracks *operational mode*, not activity volume.

## `PROJECT_STATE.md` shape

```markdown
# PROJECT_STATE

> Lifecycle Stage: Pilot (since 2026-05-23)
> Last Updated: <ISO timestamp> by <name> (session: <slug>)
```

- Value: exactly one of `Setup`, `Pilot`, `Launch`, `Maintenance`, `Archive`.
- `since`: date the project entered the current stage. Updated only on real transitions.
- Cardinality: exactly one stage per project.
- Seed: `install.sh` initializes new projects to `Setup (since <today>)`.

## Initial labeling (projects bootstrapped before this standard)

Add the header line manually, choosing the current stage by self-assessment. A formal ADR is optional — this is *initial labeling*, not a *transition*.
