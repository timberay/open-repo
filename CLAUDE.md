# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Non-Negotiable Rules

- **Korean** for explanations and conversation; **English** for code, markdown,
  YAML, commit messages
- **TDD**: Red-Green-Refactor for every task. Write a failing test first.
- **Tidy First**: NEVER mix structural changes (refactoring) and behavioral
  changes (new logic) in a single commit
- **Small Commits**: Commit every time a test passes or a refactoring is done

## Orchestrator (STATE + ADR)

Two files are required reading at the start of every session — the SessionStart
hook (`.agent-hooks/sessionstart-inject-state.sh`) already injects them, but
verify you have read them:

- **`PROJECT_STATE.md`** — "where the project is right now". Current phase,
  active spec/plan, locked decisions (as pointers), open questions, out-of-scope.
  Hard cap: 100 lines. **Mutable** — refresh with `/state-sync` at phase
  transitions and logical checkpoints.
- **`docs/decisions/README.md` + `ADR-NNNN-*.md`** — append-only decision log.
  `Accepted` ADRs are **immutable**. To reverse one, run `/supersede ADR-NNNN`
  — never edit the body of an Accepted ADR.

When the user references prior decisions ("이전에", "왜 X 했더라", "previously"),
consult `docs/decisions/` before answering. The UserPromptSubmit hook will
remind you. Decisions live in ADRs, not in git log.

When code edits trigger the PreToolUse stale warning (PROJECT_STATE.md older
than 7 days), run `/state-sync` to refresh before proceeding.

Slash commands:
- `/decide` — draft a new ADR from conversation context
- `/state-sync` — refresh PROJECT_STATE.md
- `/supersede ADR-NNNN` — reverse a previously accepted ADR

See `docs/decisions/ADR-0000-orchestrator-bootstrap.md` for the rationale.

## Standards Reference

Detailed standards are in `docs/standards/`. **Read the relevant document(s)
before starting work.**

| Document      | Description                                                                       |
|---------------|-----------------------------------------------------------------------------------|
| `RULES.md`    | DRY, Tidy First, documentation rules, AI instruction writing guidelines           |
| `WORKFLOW.md` | Six-phase pipeline (product → architecture → design → tasks → execute → ship)     |
| `QUALITY.md`  | Testing strategy, security principles, accessibility, performance                 |
| `REVIEW.md`   | Code review checklist                                                             |
| `LIFECYCLE.md`| Project lifecycle stages (Setup → Pilot → Launch → Maintenance → Archive), transition rules |
| `STACK.md`    | **Language overlay** — tech stack, framework patterns                             |
| `TOOLS.md`    | **Language overlay** — dev commands, linter, test runner, security scanner        |

> `STACK.md` and `TOOLS.md` were installed from the language overlay at
> bootstrap time. To switch language later, re-run `install.sh --lang <other>`
> from the project root.

## Pre-commit Failure Recovery

When a pre-commit hook fails, fix it yourself and retry — do not stop and ask
the user. **Details:** see `QUALITY.md → Pre-commit Failure Recovery` and the
language-specific commands in `TOOLS.md`.

## Pipeline Phases

For new feature work, follow the six-phase pipeline (`WORKFLOW.md`). Skip only
for bug fixes, refactors, or small tweaks. A `UserPromptSubmit` hook in
`.claude/settings.json` injects the phase reminder when a feature-request
keyword is detected.

## Task → Required Reading

Before starting work, read the documents mapped to your task type:

| Task Type                  | Must Read                                                |
|----------------------------|----------------------------------------------------------|
| Feature implementation     | RULES, STACK                                             |
| UI / Frontend / Styling    | STACK, QUALITY (Accessibility)                           |
| Bug fix / Debugging        | QUALITY                                                  |
| Testing                    | QUALITY (Testing Strategy)                               |
| API integration            | STACK (Adapter / Integration Pattern), TOOLS             |
| Authentication / OAuth     | STACK (Authentication), QUALITY (Security)               |
| Database / Migration       | STACK (Database & Infrastructure), TOOLS (DB commands)   |
| Deployment / DevOps        | STACK (Deployment), TOOLS (Deployment commands)          |
| Code review / PR           | REVIEW                                                   |
| Lifecycle stage transition / archive decision | LIFECYCLE                                                |

## Behavioral Guidelines

These guidelines reduce common LLM coding mistakes. They bias toward caution
over speed; use judgment for trivial tasks.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes,
simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it
work") require constant clarification.

### 5. Ask Selectively

**Ask only when the answer changes direction. Decide and proceed otherwise.**

Before asking the user, check whether the answer actually changes what you
would do.

Ask when:
- The choice changes architecture, scope, or implementation direction.
- The action is hard to reverse — destructive, or affects shared/external
  systems.
- You need information only the user has (credentials, business context,
  external constraints).

Do **not** ask when:
- You are merely confirming a recommendation you are already confident in.
  Pick it and state the choice in your response so the user can redirect.
- One option is clearly better given the project's conventions or the rules
  in this document.
- The decision is a trivial detail — naming, formatting, minor implementation
  choices. Apply existing conventions and move on.

User time is the scarcest resource. When confident, act and document the
choice; if the choice turns out wrong, reverse it then.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer
rewrites due to overcomplication, and clarifying questions come before
implementation rather than after mistakes.

## graphify

This project may have a graphify knowledge graph at `graphify-out/`.

Rules:
- Before answering architecture or codebase questions, read
  `graphify-out/GRAPH_REPORT.md` for god nodes and community structure
- If `graphify-out/wiki/index.md` exists, navigate it instead of reading raw
  files
- For cross-module "how does X relate to Y" questions, prefer
  `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or
  `graphify explain "<concept>"` over grep — these traverse the graph's
  EXTRACTED + INFERRED edges instead of scanning files
- After modifying code files in this session, run `graphify update .` to keep
  the graph current (AST-only, no API cost)

## Recommended Claude Code Plugins

These are auto-installed by `install.sh` (skip with `--skip-skills`):

| Plugin                       | Marketplace                | Purpose                                      |
|------------------------------|----------------------------|----------------------------------------------|
| `superpowers`                | `claude-plugins-official`  | Brainstorming, plans, TDD, debugging, review |
| `code-review`                | `claude-plugins-official`  | Branch / PR review                           |
| `andrej-karpathy-skills`     | `karpathy-skills`          | Karpathy's coding-mistake guardrails         |

`graphify` and `gstack` are **verified, not installed** by the installer (it
checks `~/.agents/skills/<name>/` first, then legacy `~/.claude/skills/<name>/`,
and warns if absent). `gstack` is required for
`WORKFLOW.md` phases 1, 2, and 6 (`/office-hours`, `/plan-eng-review`,
`/review`, `/ship`, `/land-and-deploy`, `/document-release`). Install them
manually if missing.

### Bundled project skills

The installer also copies the following skill straight into
`.agents/skills/<name>/` and links `.claude/skills` to that directory, so it
lives inside the project's git history:

| Skill      | Purpose                                                                   |
|------------|---------------------------------------------------------------------------|
| `push2gh`  | Adaptive commit → push → PR → optional automerge → cleanup. Use as a `gstack`-free substitute for `/ship` + `/land-and-deploy` in `WORKFLOW.md` phase 6. |

The bundled copy is a snapshot of the global `~/.agents/skills/push2gh/`
taken at template build time. To upgrade, copy the latest file back into
the template (`cp ~/.agents/skills/push2gh/SKILL.md
~/projects/00.base-files/common/.agents/skills/push2gh/SKILL.md`) and
commit.
