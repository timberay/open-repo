# ADR-0000: Adopt PROJECT_STATE + ADR + Hooks orchestrator

- **Status:** Accepted
- **Date:** 2026-05-23
- **Supersedes:** (none)
- **Superseded by:** (none)

## Context

AI-driven development in projects bootstrapped from this template exhibits three recurring failures:

1. Decision reversal — AI flips previously settled decisions because nothing tells it "this is locked."
2. History blindness — AI answers without reading prior decisions or design docs.
3. State misjudgment — AI reads a stale artifact and infers a current state that is no longer true.

The existing six-phase pipeline (`docs/standards/WORKFLOW.md`) addresses *process*, but Phase 1 and Phase 2 outputs live outside the repo (under `~/.gstack/`), so a fresh AI session cannot see them.

## Decision

Introduce a three-component "Orchestrator" surface that ships in `common/` and is propagated to every bootstrapped project:

1. **`PROJECT_STATE.md`** — a single page (≤100 lines, six fixed sections) that answers "where are we right now". Mutable, always current.
2. **`docs/decisions/`** — append-only ADR directory. Decisions are immutable; reversal requires a new ADR that supersedes the old one via the `Supersedes:` header.
3. **Three hooks + three slash commands** — `SessionStart` injects STATE and the ADR index; `UserPromptSubmit` reminds when the user references prior decisions; `PreToolUse` warns when STATE is stale. `/decide`, `/state-sync`, and `/supersede` are user-triggered, AI-drafted authoring flows.

Enforcement strength: **Medium**. Hooks inject context and warn; they do not block. Immutability of `Accepted` ADRs is enforced by convention (the slash commands won't edit the body), not by pre-commit hard checks.

## Consequences

- Positive: a fresh AI session sees STATE + ADR index before its first response. Decision history survives across sessions. Reversal requires an explicit supersede — silent drift is no longer possible without leaving an audit trail.
- Positive: zero dependency on `gstack`. Works in every bootstrapped project.
- Negative: small ritual overhead — phase transitions and major decisions require `/state-sync` and `/decide`.
- Neutral: this ADR system replaces nothing in the existing six-phase pipeline. It is a layer above it.
- Future: a follow-up ADR may upgrade immutability enforcement from convention to a pre-commit hard block.
