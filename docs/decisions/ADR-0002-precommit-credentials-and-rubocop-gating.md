# ADR-0002: Pre-commit excludes encrypted credentials and gates rubocop on the bundle

- **Status:** Accepted
- **Date:** 2026-06-08
- **Supersedes:** (none)
- **Superseded by:** (none)

## Context

Two pre-commit details (ADR-0001) need a recorded rationale so a future
maintainer does not "fix" them into breakage:

1. **Rails encrypted credentials.** `config/credentials*.yml.enc` are binary
   blobs produced by Rails' encryption. The file-hygiene hooks
   (`trailing-whitespace`, `end-of-file-fixer`, `mixed-line-ending`) would
   rewrite bytes inside the ciphertext, corrupting it — and they have no
   meaningful work to do on an opaque blob anyway.
2. **Rubocop availability.** This template installs the same
   `.pre-commit-config.yaml` into projects that may or may not carry rubocop in
   their bundle. An ungated `bundle exec rubocop` would hard-fail the commit in
   a project without rubocop.

## Decision

1. Set a top-level `exclude: '\.enc$'` in `.pre-commit-config.yaml` so no hook
   touches encrypted files.
2. Wrap the local rubocop hook in a `bundle list rubocop` guard so it becomes a
   silent no-op when rubocop is not in the project's bundle:
   `bash -c 'bundle list rubocop >/dev/null 2>&1 && bundle exec rubocop "$@" || exit 0'`.

## Consequences

- Positive: encrypted credentials survive commits intact; rubocop runs where it
  exists and is invisible where it does not.
- Negative: a genuinely malformed `.enc` file is not caught by pre-commit — but
  pre-commit was never the right layer for that; Rails fails loudly at decrypt
  time.
- Neutral: secret-detection hooks (`detect-private-key`, `detect-aws-credentials`)
  still run on everything except `.enc`. Plaintext key files are additionally
  blocked from the repo by `.gitignore` (`/config/*.key`,
  `/config/credentials/*.key`).
