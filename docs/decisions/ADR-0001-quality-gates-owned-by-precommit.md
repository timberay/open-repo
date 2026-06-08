# ADR-0001: Quality gates owned by pre-commit + local `bin/ci`; no GitHub CI

- **Status:** Accepted
- **Date:** 2026-06-08
- **Supersedes:** (none)
- **Superseded by:** (none)

## Context

Quality enforcement in this repo originally lived in two places:

1. A Claude Code `PreToolUse` hook on `Bash(git commit*)` in
   `.claude/settings.json` that ran `bin/rails test` + `bin/rubocop` and denied
   the commit on failure.
2. A GitHub Actions workflow (`.github/workflows/ci.yml`) that re-ran the checks
   on push/PR.

Both had problems. The settings.json gate was Claude-Code-specific — Codex,
opencode, and a plain `git commit` from the shell bypassed it entirely, so the
"single source of truth" was really "whatever each agent's hook config happens
to run." GitHub Actions is **disabled for this repo** (billing-blocked; the
account cannot run Actions minutes), so the CI layer never actually executes —
yet the standards docs were written as if CI were a reliable backstop.

This left a gap: with the per-agent commit hook removed in favor of a portable
gate, and CI not running, nothing enforced quality unless a developer
remembered to run the checks by hand.

## Decision

Make `.pre-commit-config.yaml` the single, tool-agnostic source of truth for
fast commit-time checks, and `bin/ci` (`config/ci.rb`) the source of truth for
the full pipeline. Specifically:

1. **Commit-time fast checks** — `.pre-commit-config.yaml`, registered once per
   clone with `pre-commit install`. Runs file-hygiene hooks, secret detection,
   and rubocop (bundle-gated, see ADR-0002). Blocks the commit on violation,
   regardless of which agent or shell issued it.
2. **Full pipeline** — `bin/ci` runs lint + `bundler-audit` + `importmap audit`
   + `brakeman` + the test suite + seed verification. It is **developer-run
   before every push** and gates the push by convention.
3. **No GitHub CI.** `.github/workflows/ci.yml` is removed. The repo does not
   rely on any remote CI; `bin/ci` is the only full-suite gate. If Actions
   billing is restored later, re-introducing CI requires a superseding ADR so
   the docs and the reality stay aligned.

The per-commit `bin/rails test` / `bin/rubocop` deny-hooks in
`.claude/settings.json` are removed; tests are not run at commit time (too slow
for every commit) and instead run in `bin/ci` before push.

## Consequences

- Positive: one gate definition (`.pre-commit-config.yaml`) applies to every
  tool — Claude Code, Codex, opencode, bare git — not just the agent whose hook
  config happens to run it.
- Positive: the docs now match reality. No standard claims a CI backstop that
  does not run.
- Negative: the commit-time gate is **opt-in per clone** — `pre-commit install`
  must be run once, and there is no remote net if a developer skips it. The
  mitigation is the documented "run `bin/ci` before push" rule.
- Negative: tests no longer run automatically at commit time. Catching a broken
  test now depends on `bin/ci` being run before push. Accepted as the cost of
  fast commits.
- Neutral: TDD discipline (`CLAUDE.md`) is unchanged; it is now enforced by
  convention + `bin/ci` rather than by a blocking commit hook.
