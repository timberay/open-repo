---
name: decide
description: Draft a new ADR from the current conversation. AI fills the template; user approves before save.
---

You are creating a new Architecture Decision Record (ADR).

## Steps

1. **Find the next ADR number.**
   Read `docs/decisions/README.md`. The next number is `max(existing) + 1`, or `0001` if only `0000-bootstrap` exists, or `0000` if the directory is empty. Format as 4 digits (`0007`).

2. **Identify the decision.**
   Look at the current conversation. State the decision in one sentence. If unclear, ask the user.

3. **Draft the ADR with all fields filled.**
   No placeholders. All fields below must have real content:

   ```markdown
   # ADR-NNNN: <Title — ≤80 chars, describing the decision>

   - **Status:** Proposed   <!-- or Accepted, if user says it's locked -->
   - **Date:** <today, YYYY-MM-DD>
   - **Supersedes:** (none)
   - **Superseded by:** (none)

   ## Context
   <2–4 sentences: what forces require this decision, what's at stake.>

   ## Decision
   <What was decided. 1–3 sentences, declarative.>

   ## Consequences
   - Positive: <one outcome>
   - Negative: <one tradeoff>
   - Neutral: <one observation, optional>
   ```

4. **Show the draft to the user.** Ask explicitly:
   > "ADR-NNNN draft above. Approve as-is, edit, or cancel?"

5. **On approval:**
   - Write the file to `docs/decisions/ADR-NNNN-<kebab-slug>.md`. The slug is a lowercase, dash-separated version of the title, ≤40 chars.
   - Add a row to the table in `docs/decisions/README.md`:
     `| NNNN | <Title> | <Status> | <Date> |`
   - If status is `Accepted`, also append one line to `PROJECT_STATE.md` "Locked Decisions" section:
     `- ADR-NNNN — <Title> (Accepted, <Date>)`

6. **Stage the new and modified files. Do not commit.**
   Run: `git add docs/decisions/ADR-NNNN-*.md docs/decisions/README.md PROJECT_STATE.md`
   Tell the user the files are staged and let them commit with their own message.

## Rules

- Never silently flip an existing `Accepted` ADR. If the user describes a decision that contradicts one, stop and tell them to use `/supersede ADR-XXXX` instead.
- If `docs/decisions/` doesn't exist, create it. The README is the table; nothing else.
- Slug examples: "Use SQLite for development, Postgres in production" → `sqlite-dev-postgres-prod`.
