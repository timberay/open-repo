---
name: supersede
description: Create a new ADR that supersedes an existing one. The old ADR's status header is updated (only post-acceptance edit allowed).
---

You are creating a new ADR that supersedes an existing one.

**Usage:** `/supersede ADR-NNNN`

## Steps

1. **Parse the target.**
   The argument is `ADR-NNNN` (4-digit, padded). Locate the file: `docs/decisions/ADR-NNNN-*.md`. If not found, stop and tell the user.

2. **Verify status.**
   Read the file. Check the `Status:` line:
   - If `Proposed`: stop. Tell the user to edit it directly instead — `Proposed` is not locked yet.
   - If `Superseded by ADR-XXXX`: stop. Tell the user to supersede ADR-XXXX (the current head) instead.
   - If `Rejected`: stop. Tell the user this is historical and was never adopted.
   - If `Accepted`: proceed.

3. **Ask the user for the new decision.**
   > "What changed? State the new decision in one sentence, and why it replaces ADR-NNNN."

4. **Find the next ADR number.**
   Same logic as `/decide`: `max(existing) + 1`, 4-digit padded.

5. **Draft the new ADR.**
   Same template as `/decide`, but:
   - `Supersedes: ADR-NNNN` (filled in)
   - `Status: Accepted` (supersession is by definition an accepted action)
   - Add a `## Context` paragraph that explicitly references what ADR-NNNN said and why it no longer holds.

6. **Plan the edit to ADR-NNNN.**
   The ONLY change permitted is the `Status:` line:
   - From: `- **Status:** Accepted`
   - To:   `- **Status:** Superseded by ADR-MMMM`
   The body of ADR-NNNN must not change. (If the user wants to "correct" the old body, refuse — that is history rewriting.)

7. **Show both changes to the user:**
   - The new ADR-MMMM file contents
   - The single-line diff to ADR-NNNN's Status header
   Ask: "Approve both?"

8. **On approval:**
   - Write `docs/decisions/ADR-MMMM-<kebab-slug>.md`.
   - Edit ADR-NNNN: change only the Status header line.
   - Update `docs/decisions/README.md`:
     - Add a row for ADR-MMMM (Accepted)
     - Update ADR-NNNN's row: status → `Superseded by ADR-MMMM`
   - Append to `PROJECT_STATE.md` "Locked Decisions" section (since the new one is Accepted).

9. **Stage. Do not commit.**
   Run: `git add docs/decisions/ PROJECT_STATE.md`.

## Rules

- Never edit the body of an `Accepted` ADR. Only the status header may change, and only when superseding.
- The new ADR must explicitly reference what was superseded — both in the `Supersedes:` header AND in the `## Context` body.
- If the user can't articulate what changed since ADR-NNNN, push back: maybe the decision still holds and they just need a fresh read.
