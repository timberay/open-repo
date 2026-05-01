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

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)

# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
