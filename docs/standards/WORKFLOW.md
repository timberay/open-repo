# Development Workflow

## Pipeline Phases (4-Layer Design Separation)

For new feature work, follow the 4-phase design separation. Do NOT skip phases. A `UserPromptSubmit` hook will remind you when a feature request is detected.

### Phase 1 — Product Decision
- **Skill**: `/office-hours` (gstack)
- **Answers**: WHAT + WHY + WHO
- **Output**: `~/.gstack/projects/<slug>/designs/<feature>.md`
- **Forbidden**: tech stack, architecture, code

### Phase 2 — System Architecture
- **Skill**: `/plan-eng-review` (gstack)
- **Answers**: data flow, failure modes, module boundaries
- **Output**: `~/.gstack/projects/<slug>/designs/<feature>-eng-review.md`
- **Forbidden**: file-level plan, task IDs, code snippets

### Phase 3 — Technical Design
- **Skill**: `/superpowers:brainstorming`
- **Answers**: Rails patterns, concurrency, caching, test strategy
- **Input**: Phase 1 + Phase 2 docs (do not re-debate)
- **Output**: `docs/superpowers/specs/<date>-<feature>-tech-design.md`
- **Forbidden**: product re-debate, system boundary re-debate

### Phase 4 — Task Breakdown
- **Skill**: `/superpowers:writing-plans`
- **Input**: Phase 3 doc (primary), Phase 1/2 (reference)
- **Output**: `docs/superpowers/plans/<date>-<feature>-plan.md`

### Phase 5 — Execute
- **Skill**: `/superpowers:executing-plans` + `test-driven-development`

### Phase 6 — Review / Ship / Deploy
- **Skills**: `/review`, `/ship`, `/land-and-deploy`, `/document-release`

### Phase continuation rules
- If the user explicitly continues an in-progress phase (e.g., "Phase 3 계속", "플랜 수정", 이미 열려있는 design doc 편집), proceed without re-checking earlier phases.
- If the user explicitly overrides ("간단한 버그 수정이니 phase 건너뛰어"), confirm the task truly doesn't need the pipeline, then proceed.
- For bug fixes, refactors, and small tweaks, the pipeline does not apply. Use your judgment.
