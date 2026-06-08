# Code Review Checklist

Use this checklist before requesting a merge or approving someone else's PR.
The automated gate (test runner, linter, security scanner) is enforced by the
pre-commit hooks in `.claude/settings.json` — see the language overlay's
`TOOLS.md` for the exact commands. This file lists the manual checks a human
(or an AI reviewer) must perform.

## Automated (enforced by pre-commit hooks)

The hooks listed in `.claude/settings.json` MUST pass before any commit lands.
See `TOOLS.md` in the language overlay for the exact command set. Typical
gates:

- [ ] All tests pass
- [ ] No linting errors
- [ ] No security warnings (static analyzer / dependency audit)
- [ ] Database seeds / fixtures load cleanly in a fresh environment

If any of these are missing for the language, document why in `TOOLS.md`
rather than skipping the check.

## Manual Review

- [ ] Structural and behavioral changes are in separate commits (Tidy First)
- [ ] New features have corresponding tests at the right level of the pyramid
- [ ] Public API changes are reflected in the relevant documentation
- [ ] Accessibility requirements (see `QUALITY.md`) are met for UI changes
- [ ] No N+1 queries introduced (or one is explicitly justified)
- [ ] Caching applied where appropriate (hot path + slow + stable data)
- [ ] Background-job work used for any heavy external I/O on a request path
- [ ] Error messages are user-facing where appropriate (no raw stack traces
      reaching end-users)
- [ ] Logs include enough context for post-hoc diagnosis (see `QUALITY.md` ->
      Evidence-Driven Self-Diagnosis)
- [ ] No secrets, tokens, or production URLs committed
- [ ] Feature flags or migrations are reversible (or the irreversibility is
      explicit in the PR description)

## When to block

Block the merge when any of the following is true; otherwise prefer
"approve with comments":

- A correctness bug demonstrable by an existing or trivially-added test
- A security regression (auth bypass, secret leak, injection vector)
- A performance regression on a hot path with no mitigating plan
- An API break with no migration path documented
- A test deleted or weakened without justification
