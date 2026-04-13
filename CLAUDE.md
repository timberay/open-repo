# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## READ FIRST!!

- **STANDARDS.md** : ALWAYS READ IT FIRST.

## Language Rules

- Use **Korean** for explanations and conversation
- Use **English** for code, markdown files, YAML, and commit messages

## Project Overview

Real estate auction application built on Rails 8.1 (Ruby 3.4.8) monolith with Hotwire (Turbo + Stimulus), SQLite, and Solid Cache/Queue/Cable.

## Common Commands

```bash
# Setup
bin/setup

# Run dev server (Puma + CSS/JS watchers)
bin/dev

# Console
bin/rails console

# Database
bin/rails db:prepare         # Create/migrate DB
bin/rails db:reset           # Reset DB (dev only)
bin/rails db:seed            # Load seed data

# Linting
bin/rubocop                  # Check style (rubocop-rails-omakase)
bin/rubocop -a               # Auto-fix

# Security
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit

# Testing (Minitest — default Rails test framework)
bin/rails test                              # Run all tests
bin/rails test test/models/foo_test.rb      # Single file
bin/rails test test/models/foo_test.rb:42   # Single test by line

# CI (runs full pipeline: setup, rubocop, security audits, tests, seed check)
bin/ci
```

## Architecture

**Stack:** Rails 8.1 monolith, Hotwire (Turbo + Stimulus with pure JS, no TypeScript), TailwindCSS, SQLite, Propshaft (asset pipeline), ImportMap (no Node/npm for JS deps).

**Database:** SQLite with separate databases for cache (Solid Cache), queue (Solid Queue), and WebSockets (Solid Cable). No Redis or external services needed.

**Frontend:**
- Turbo Frames for pagination/tabs (no full page reloads)
- Turbo Streams for partial updates
- Stimulus controllers: pure JavaScript, data-attribute conventions (`data-controller`, `data-action`, `data-*-target`)
- ViewComponent for reusable UI components with Lookbook for component previews
- Add JS dependencies via `bin/importmap pin <package>`

**Deployment:** Docker + Kamal + Thruster (Go proxy on port 80). Config in `config/deploy.yml`.

**Planned patterns (from STANDARDS.md — create these directories as needed):**
- **Service Objects** in `app/services/*_service.rb` with unified `call` method
- **Adapter Pattern** for API communication: `BaseAdapter.for(provider)` returns MockAdapter or RealAdapter based on `USE_MOCK` env var
- **Custom Errors** in `app/errors/custom_error.rb` with `rescue_from` in controllers
- **Caching**: Fragment caching for UI, API response caching with TTL via Solid Cache

**Rails 8 specifics:**
- Use `params.expect()` over `params.require().permit()`
- No Sprockets, Webpacker, or Rails UJS — use Propshaft + ImportMap + Turbo
- Authentication: **skipped in MVP**. Post-MVP: Rails 8 built-in auth + OAuth/social login (e.g., Google, Kakao)

## Documentation Rules

### File Structure
- **Root**: Only `README.md`, `CLAUDE.md`, `STANDARDS.md` — no other MD files
- **`docs/`**: All project documentation lives under `docs/superpowers/` (managed by superpowers plugin)
  - `specs/` — Design specs from brainstorming sessions (requirements, decisions, etc.)
  - `plans/` — Implementation plans for feature work
- **`db/seeds/`**: Seed data files (e.g., `master_checklist.json`)

### Writing Principles
1. **Single Source of Truth** — Never duplicate information across files. If it exists in one place, reference it, don't copy it.
2. **Reference direction** — Specs reference other specs as peers. Plans reference specs, never the reverse. No "update X when Y changes" obligations.
3. **Record decisions, not process** — Intermediate analysis (agent reports, working copies) should not be committed. Only final decisions belong in docs.
4. **Dead docs are worse than no docs** — Review and update or remove documentation that is outdated. Once code is implemented, the code is the SSOT, not the plan.

### Before Creating a New MD File
- Can this be added to an existing doc? → Add it there
- Will this be referenced after implementation? → If no, don't create it
- Does this require syncing with another doc? → If yes, redesign the structure

## TDD & Commit Discipline

Follow strict **Red-Green-Refactor** (Kent Beck style):
1. RED: Write a failing test first
2. GREEN: Minimum code to pass
3. REFACTOR: Clean up only after tests pass

**"Tidy First" rule:** NEVER mix structural changes (refactoring) with behavioral changes (new logic) in a single commit. Tidy first, commit, then implement.

**Testing:** Minitest (Rails default) for unit/integration. Playwright for E2E. Target 80%+ coverage.

## Git Conventions

- Small commits: commit every time a test passes or a refactoring is done
- English-only commit messages
- Separate structural (refactor) and behavioral (feature/fix) commits

## UI/Frontend Rules

The `/rails-ui` skill activates automatically for UI-related work.
It references the following files to generate consistent UI:

- `~/.claude/skills/rails-ui/design_tokens.json` — SSOT for design values
- `~/.claude/skills/rails-ui/DESIGN.md` — Tailwind class mappings per component

When creating new components:
- If DESIGN.md has a spec for the component, follow it exactly
- If not, follow patterns from existing components for consistency
- After creation, self-verify using the quality checklist in SKILL.md

**Planning UI/UX work:**
- Implementation plans involving UI/UX changes MUST invoke `/rails-ui` for design token compliance and `/e2e-testing` for verification criteria
- `/rails-ui` determines HOW to build the UI (design tokens, component patterns)
- `/e2e-testing` determines HOW to verify it (browser testing, screenshot evidence)
