# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Non-Negotiable Rules

- **Korean** for explanations and conversation; **English** for code, markdown, YAML, commit messages
- **TDD**: Red-Green-Refactor for every task. Write a failing test first.
- **Tidy First**: NEVER mix structural changes (refactoring) and behavioral changes (new logic) in a single commit
- **Small Commits**: Commit every time a test passes or a refactoring is done

## Standards Reference

Detailed standards are in `docs/standards/`. **Read the relevant document(s) before starting work.**

| Document | Description |
|----------|-------------|
| [RULES.md](docs/standards/RULES.md) | DRY, Tidy First, documentation rules, AI instruction writing guidelines |
| [STACK.md](docs/standards/STACK.md) | Project overview, tech stack, patterns, Hotwire, deployment, i18n, Rails 8 specifics |
| [TOOLS.md](docs/standards/TOOLS.md) | Dev commands, environment config, API tools |
| [QUALITY.md](docs/standards/QUALITY.md) | Testing, security, accessibility, performance, code review, pre-commit failure recovery |
| [WORKFLOW.md](docs/standards/WORKFLOW.md) | Pipeline Phases (4-Layer Design Separation) for new feature work |

## Pre-commit Failure Recovery

When a pre-commit hook fails, fix it yourself and retry — do not stop and ask the user. **Details**: [QUALITY.md](docs/standards/QUALITY.md#pre-commit-failure-recovery).

## Pipeline Phases (summary)

For new feature work: `/office-hours` → `/plan-eng-review` → `/superpowers:brainstorming` → `/superpowers:writing-plans` → `/superpowers:executing-plans`. Skip only for bug fixes, refactors, small tweaks. A `UserPromptSubmit` hook reminds you when a feature request is detected. **Full rules**: [WORKFLOW.md](docs/standards/WORKFLOW.md).

## Task → Required Reading

Before starting work, read the documents mapped to your task type:

| Task Type | Must Read |
|-----------|-----------|
| Feature implementation | RULES, STACK |
| UI / Frontend / Styling | STACK (UI/Frontend Rules, Hotwire), QUALITY (Accessibility) |
| Bug fix / Debugging | QUALITY |
| Testing | QUALITY (Testing Strategy) |
| API integration | STACK (Adapter Pattern), TOOLS |
| Authentication / OAuth | STACK (Authentication), QUALITY (Security) |
| Database / Migration | STACK (Database & Infrastructure), TOOLS (Database commands) |
| Deployment / DevOps | STACK (Deployment), TOOLS (Deployment commands) |
| Code review / PR | QUALITY (Code Review Checklist) |
