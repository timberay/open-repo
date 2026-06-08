---
name: state-sync
description: Refresh PROJECT_STATE.md to reflect current session activity. AI proposes a diff; user approves before save. Supports `--stage <Stage>` for lifecycle transitions.
---

You are syncing `PROJECT_STATE.md` — the project's "where are we right now" page.

## Argument parsing

The command may be invoked in two forms:

- `/state-sync` — default behavior: refresh the section bodies (Current Phase, Active Work, etc.). The lifecycle header is read for soft-validation only.
- `/state-sync --stage <Stage>` — additionally transition the project's Lifecycle Stage. `<Stage>` MUST be exactly one of: `Setup`, `Pilot`, `Launch`, `Maintenance`, `Archive`. If `<Stage>` is missing, misspelled, or otherwise not in that set, refuse and print the canonical list — do not proceed.

When `--stage` is provided, run "Stage transition mode" (below) **after** Step 1 and **before** Step 2. When it is not provided, skip that mode entirely.

## Steps

1. **Read the current state.**
   Read `PROJECT_STATE.md`. If it doesn't exist, create a stub with the lifecycle header and these six sections (all empty bodies except headers and a "Last Updated: never" line):

   ```markdown
   # PROJECT_STATE

   > Lifecycle Stage: Setup (since <today, YYYY-MM-DD>)
   > Last Updated: never

   ## Current Phase
   (none)

   ## Locked Decisions
   See `docs/decisions/README.md`.

   ## Active Work
   (none)

   ## Open Questions
   (none)

   ## Out of Scope
   (none)

   ## Last Updated
   (see header)
   ```

   **Soft-validate the current Lifecycle Stage.** Grep the `> Lifecycle Stage:` line out of the header (e.g., `grep -m1 '^> Lifecycle Stage:' PROJECT_STATE.md`).
   - If the line is missing, emit: `⚠ No Lifecycle Stage header found. /state-sync --stage <Stage> can add one.` Continue.
   - If present but the value is not in `{Setup, Pilot, Launch, Maintenance, Archive}`, emit: `⚠ Stage value '<value>' is not one of Setup/Pilot/Launch/Maintenance/Archive. /state-sync --stage <Stage> can correct this.` Continue.
   - Never auto-correct the stage value. Soft warning only; the user fixes it via `--stage`.

2. **Survey current activity.** Gather facts:
   - `git log --oneline -10` for recent commits
   - `git status` for uncommitted changes
   - Files mentioned/edited in the current conversation
   - Active spec/plan files: `ls docs/superpowers/specs/ docs/superpowers/plans/` if they exist
   - Latest ADR (from `docs/decisions/README.md`)

3. **Propose updates to each section:**
   - **Current Phase:** Which of the 6 pipeline phases is active (see `docs/standards/WORKFLOW.md`). Include the active spec/plan paths if any.
   - **Locked Decisions:** Only update if a new ADR became `Accepted` since the last sync. Otherwise leave alone.
   - **Active Work:** In-progress items, one bullet each, ≤80 chars. If a previously active item shipped, remove it.
   - **Open Questions:** Pending decisions surfaced in the conversation that haven't been resolved.
   - **Out of Scope:** Items the user explicitly said no to.

4. **Show the proposed new PROJECT_STATE.md to the user.** This includes the (possibly rewritten) Lifecycle Stage header line from stage-transition mode, if it ran. Ask:
   > "Proposed PROJECT_STATE.md above. Approve, edit, or cancel?"

5. **On approval:**
   - Update the `Last Updated` header line:
     ```
     > Last Updated: <ISO 8601 timestamp, e.g. 2026-05-23T14:00:00+09:00> by <git config user.name> (session: <brief-tag>)
     ```
     The session tag is a short kebab-case label (e.g. `orchestrator-design`).
   - Write the file. If stage-transition mode ran, the rewritten `> Lifecycle Stage:` line is part of the write.

6. **Stage. Do not commit.**
   Run: `git add PROJECT_STATE.md`. Tell the user.

## Stage transition mode (`--stage <Stage>`)

Run this between Step 1 and Step 2, only when `--stage` was provided.

1. **Compute current stage.** Re-read the `> Lifecycle Stage:` line captured in Step 1. If absent (warning already emitted), treat current stage as "unset" — ask the user to confirm setting the initial label to `<Stage>` before continuing. This is *initial labeling*, not a transition; no obligations apply.

2. **Refuse non-forward transitions.** If `<new>` is not strictly forward of `<current>` in `Setup → Pilot → Launch → Maintenance → Archive`, print:
   `Refusing <current> → <new>. Backward or same-stage transitions require a regression / reactivation ADR; see docs/standards/LIFECYCLE.md "Edge cases".`
   Stop. Do not modify the file.

3. **Surface forward-transition obligations.** Look up the matching row in `docs/standards/LIFECYCLE.md` § Transition obligations and print it back to the user. Ask them to confirm the required artifacts are produced or in flight. If a required `/decide` ADR has not been written yet, **pause and offer to run `/decide` first** — do NOT silently proceed.

4. **Rewrite the header on confirmation.** Replace the `> Lifecycle Stage:` line with:
   ```
   > Lifecycle Stage: <NewStage> (since <today, YYYY-MM-DD>)
   ```
   If the line was missing entirely, INSERT it immediately below the `# PROJECT_STATE` title so it becomes the first blockquote line, pushing the existing `> Last Updated:` line down.

5. **Fall through.** Continue with Step 2 (Survey) of the normal flow. The header rewrite is shown to the user as part of the Step 4 diff and is committed to disk in Step 5 alongside any section updates.

## Rules

- Hard cap: PROJECT_STATE.md must stay under 100 lines. If a section grows too long, that content belongs in an ADR or spec — link to it instead.
- Never write decision reasoning into PROJECT_STATE.md. Reasoning lives in ADRs.
- If `git config user.name` is empty, use `unknown`.
- The `> Lifecycle Stage:` line carries exactly one canonical stage label (`Setup` / `Pilot` / `Launch` / `Maintenance` / `Archive`) and a `since` ISO date. Deviation triggers a soft warning on every `/state-sync`; correction happens only inside `--stage`.
