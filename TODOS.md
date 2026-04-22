# TODOS

Deferred work captured during reviews. Keep entries self-contained: the reader
should understand motivation, current state, and starting point without
re-reading the original review.

## Format

```
### [PRIORITY] Title
**What:** One-line summary of the work.
**Why:** The concrete problem it solves or value it unlocks.
**Pros:** What you gain by doing this.
**Cons:** Cost, complexity, or risk.
**Context:** Background the future reader needs.
**Depends on / blocked by:** Prerequisites.
**Source:** Review date + section that raised this.
```

---

## [P2] Tag protection policy change audit

**What:** Add `action='policy_change'` event type to `TagEvent` (with
`previous_policy` / `new_policy` columns) so repository tag protection policy
transitions are recorded the same way tag mutations are.

**Why:** Scenario — a user temporarily sets `tag_protection_policy` to `none`,
deletes a protected release tag, then restores the policy. Today the tag
deletion is recorded but the policy flip is not, so the "who/when/why this
was possible" trail is broken.

**Pros:** Reuses existing `TagEvent` infrastructure. Trivial implementation
(one migration + one hook in `RepositoriesController#update`). Completes the
audit story for the tag protection feature.

**Cons:** Current MVP threat model explicitly excludes actor tracking and
authentication. Without identity, `actor='anonymous'` limits forensic value.
Minor schema-pattern drift: `TagEvent` becomes "tag-or-policy event."

**Context:** Raised in 2026-04-22 eng review (issue 1-E). Explicitly deferred
because the spec's threat model is accident prevention in an internal trusted
network. Revisit when authentication is introduced post-MVP.

**Depends on / blocked by:** None. Could ship independently.

**Source:** `/plan-eng-review` on `docs/superpowers/specs/2026-04-22-tag-immutability-design.md`.

---

## [P2] Policy transition impact preview in Repository edit form

**What:** Before the user submits the repository edit form with a new
`tag_protection_policy`, show a Turbo Stream preview such as
"Saving will protect 7 existing tags (v1.0.0, v1.0.1, ...) and unprotect 0."

**Why:** A user switching `semver` → `none` to delete one tag can silently
remove protection from every other semver tag in the repo. An explicit
preview + confirm prevents unintentional safety-net removal.

**Pros:** UX safety net. Implementation is bounded — policy apply across
`repo.tags.map(&:name)` and render a partial via Turbo Stream on `change`.

**Cons:** Extra UI surface and Stimulus wiring. Current MVP is fine without
it since every tag operation is audited.

**Context:** Raised in 2026-04-22 eng review outside-voice step (subagent
finding #3). Complementary to the policy-change audit TODO above — audit is
reactive, preview is preventive.

**Depends on / blocked by:** None. Pairs well with the audit TODO if both
ship together.

**Source:** `/plan-eng-review` on `docs/superpowers/specs/2026-04-22-tag-immutability-design.md`.

