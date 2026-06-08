# Evaluation Criteria

Testing strategy, security principles, accessibility, and performance guidelines.
This file contains language-neutral principles only — concrete tools, commands,
and framework-specific guardrails live in the language overlay's `TOOLS.md` and
`STACK.md`.

## Testing Strategy

### Test Pyramid (maintain this ratio)

- **Unit** (majority): Pure functions, models, services
- **Integration** (moderate): Cross-component behavior with real I/O at the edge
  (database, in-process HTTP, queue) and stubbed external networks
- **System / E2E** (few): Major user scenarios only

### Test Coverage

- Every new feature must include corresponding tests
- Bug fixes must include a regression test that fails before the fix and passes
  after it
- Tests document the contract — name them after the behavior they assert, not
  after the function they happen to call

> Concrete test framework, runner command, and HTTP stubbing tool are defined
> in `TOOLS.md` (language overlay).

## Security Best Practices

### Universal Principles

- **No secrets in git** — `.env*`, credentials, tokens belong in a secrets manager
  or platform-managed encrypted store. Never commit a `.env` with real values.
- **Validate at boundaries** — every datum entering the system from the outside
  (HTTP body, query string, CLI argument, file upload, external API response)
  must be parsed and validated before any business logic touches it.
- **Least privilege** — DB user, API token, IAM role: each holds only the
  permissions it actually exercises. Production secrets are not reused in dev.
- **Rate-limit anything public** — login, signup, password reset, public APIs.
  Limits live in code, not in a manually-tuned reverse-proxy config.
- **Output encoding** — never concatenate untrusted strings into HTML, SQL, or
  shell commands. Use the framework's escaping/parameterization helper.
- **No raw user content reflected without sanitization** — text rendered into
  HTML or PDF passes through the framework's safe-string mechanism.
- **Constant-time comparison** for tokens, MACs, and passwords.

> Framework-specific guardrails (CSRF tokens, parameter whitelisting, ORM
> placeholder syntax, template auto-escape, regex-DoS limits, rate-limit
> middleware names) live in the language overlay's `STACK.md`.

## Accessibility Standards

### Status Indicators

Always display text labels alongside emoji statuses (e.g. "Red circle Not
recommended" not just "Red circle"). Add ARIA labels for screen readers.

### Keyboard Navigation

Ensure all interactive elements (buttons, form inputs, links) are reachable via
the Tab key. Checklist question answers must be selectable via keyboard.

### Form Inputs

- NUMBER fields use `inputmode="numeric"` for mobile keyboard optimization
- Display unit suffix (%, won, year) adjacent to the input

### Tooltips

Domain-specific terminology (legal, medical, financial, jargon) should have
inline help-text tooltips, accessible via hover (desktop) and tap (mobile).

### Color Independence

Never rely on color alone to convey status. Always pair with text and/or icons.

### Responsive Design

Mobile-first approach. Ensure touch targets are at least 44x44 px.

### Automated Accessibility Checks

Wire an automated accessibility scanner into the system-test suite when one
exists for the framework. Run it on the critical pages on every CI run. The
exact integration is documented in the language overlay's `TOOLS.md`.

## Performance Guidelines

### Universal Principles

- **Measure before caching** — cache only what is both hot and slow (>50 ms
  re-render cost on a request path; underlying data changing less than once
  per request).
- **Prevent N+1** — collection renders issue O(1) queries, not O(n). When in
  doubt, inspect the development log for repeated SELECT patterns.
- **Off-request work for heavy I/O** — long external calls (LLM inference,
  scraping, PDF generation, image processing) move to background jobs. The
  user sees a streamed update or polled state, never a blocked request.
- **Index columns used in WHERE/ORDER BY** on hot queries.
- **Bundle size discipline** — JS/CSS bundles measured per route; growth
  beyond an agreed budget requires justification.

> The cache backend, queue runner, ORM helpers, and bundle analyzer are listed
> in the language overlay's `STACK.md` / `TOOLS.md`.

## Evidence-Driven Self-Diagnosis

You have no eyes or memory beyond what you explicitly capture. Logs and
screenshots are the only evidence you can use to diagnose problems
autonomously — if you did not record it, it does not exist for you.

### Why This Matters

- You cannot re-observe a past UI state or a transient error after it
  disappears.
- Detailed evidence lets you form hypotheses and verify fixes without asking
  humans.
- Vague or missing logs force you to guess, which violates the TDD principle of
  working from facts.

### What to Capture

| Situation              | What to Record                                         |
|------------------------|--------------------------------------------------------|
| Running a command      | Full stdout/stderr output, not a summary               |
| UI change              | Screenshot before AND after                            |
| Test failure           | Complete error message, stack trace, and command used  |
| Unexpected behavior    | Steps to reproduce, expected vs. actual result         |
| External API call      | Request payload, response status, and response body    |

For diagnosis workflow, follow the `systematic-debugging` skill.

## Quality Gate Layering

This project enforces quality at four distinct layers. Each layer answers a different question and has a different owner.

| Layer | When | Owner | Strength |
|---|---|---|---|
| Edit-time format/lint | On file save inside supported agents | Agent hook config | Auto-fix where supported, no block |
| Commit-time fast checks | On `git commit` (any tool) | `.pre-commit-config.yaml` (run via the installed git hook) | Block on violation |
| Full local pipeline | Before push (developer-run) | `bin/ci` (`config/ci.rb`) | Blocks push by convention |
| Orchestrator hooks (unrelated) | Session start, prompt submit, stale state | `.agent-hooks/*.sh` via `.claude/settings.json` / `.codex/hooks.json` | Soft inject / warn |

The single source of truth for fast checks is `.pre-commit-config.yaml`. Run `pre-commit install` (one-time, after `git init`) to register the git hook so every `git commit` runs the same yaml. This repo has **no GitHub CI** (see ADR-0001); the full suite — lint, security audits, brakeman, and tests — runs locally via `bin/ci` (`config/ci.rb`) and must pass before pushing.

This layered design is locked by ADR-0001. See `docs/decisions/ADR-0001-quality-gates-owned-by-precommit.md` for the rationale.

## Pre-commit Failure Recovery

The recovery workflow is universal across layers:

- **Linter/formatter violations**: run the auto-fix command (`ruff check --fix`, `gofmt -w`, `bin/rubocop -a`), manually resolve the rest, re-stage, retry the commit.
- **Test failure (`bin/ci`)**: diagnose the failing test locally, fix the code, verify with the local test command, re-run `bin/ci`, then push.
- **Multiple issues**: fix lint first (cheap, often auto-fixable), then tests, then retry.
- **Never** bypass with `git commit --no-verify`. If a hook is wrong, fix the hook in a separate commit.
- **First-time setup on a fresh clone**: `pre-commit install` registers the git hook. There is no CI backstop in this repo, so without it nothing runs at commit time — run `bin/ci` manually before pushing.

For the code-review checklist that gates merging, see `REVIEW.md`. For the exact linter and test commands, see the language overlay's `TOOLS.md`.
