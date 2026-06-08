# AGENTS.md

This file provides project guidance for Codex, opencode, and other agents that
read AGENTS.md. Claude Code reads CLAUDE.md; keep both files aligned when
changing durable policy.

## Non-Negotiable Rules

- Korean for explanations and conversation; English for code, markdown, YAML,
  and commit messages
- Use TDD for behavioral changes: write or update a failing test first, then
  make it pass
- Keep refactoring and behavior changes in separate commits
- Touch only files required by the user's request
- Run the relevant checks from `docs/standards/TOOLS.md` before declaring work
  complete

## Required Context

- Read `PROJECT_STATE.md` at session start for current phase, active work, and
  open questions
- Read `docs/decisions/README.md` before answering questions about prior
  decisions; accepted ADRs are immutable and must be superseded rather than
  edited
- Read the relevant files in `docs/standards/` before implementation:
  `RULES.md`, `QUALITY.md`, `WORKFLOW.md`, `REVIEW.md`, `LIFECYCLE.md`,
  `STACK.md`, and `TOOLS.md`

## Tool Roles

- Claude Code is preferred for system design, ADRs, complex refactors, IaC
  structure, and runbooks
- Codex is preferred for implementation, Terraform/Helm/GitHub Actions changes,
  focused tests, and repetitive code edits
- opencode is useful as an alternate implementation or review agent, with
  project permissions defined in `opencode.json`

## Guardrails

- Agent hooks are advisory guardrails, not the final security boundary
- Pre-commit and CI are the enforcement layer; fix failures yourself and rerun
  checks
- Use separate git worktrees when running multiple coding agents in parallel
