# Rules

Foundational rules for how to work in this project. These are language-neutral
and apply to every project bootstrapped from this template.

## DRY (Don't Repeat Yourself)

Every piece of knowledge should have a single, unambiguous representation in the
system.

- If the same value, behavior, or rule appears in three places, extract it.
- Two occurrences may still be coincidence; three is a pattern that will drift.
- DRY applies to documentation as well as code. Do not restate the same fact in
  two documents — link from one to the other.

**Counter-rule:** Do not abstract prematurely. A single use is too early. Two
uses may still be coincidence. Wait until the third before extracting a shared
abstraction; otherwise you risk inventing a contract that doesn't match reality.

## Tidy First

Separate **structural changes** from **behavioral changes**. Never mix them in
the same commit.

- **Structural change**: renames, moves, extract-method, inline-variable, reorder
  imports, reformat whitespace — anything that does not change observable
  behavior.
- **Behavioral change**: new feature, bug fix, new branch in logic, changed
  return value, changed side-effect.

When you find yourself about to mix the two, commit the structural change first
with a `refactor:` prefix, then make the behavioral change in a separate commit.
This makes review and rollback dramatically easier.

## Small Commits

- Commit every time a test passes.
- Commit every time a refactoring is done.
- Each commit should leave the system in a working state.

The commit boundary is the smallest unit of "I am done with this." If you cannot
describe the commit in one sentence, it is too big.

### Commit message format

Use [Conventional Commits](https://www.conventionalcommits.org/) style:

```
<type>(<scope>): <subject>

[optional body]
```

Common types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`,
`perf`. Scope is optional but helpful for monorepos.

The subject line is imperative present tense ("add X", not "added X"), under 70
characters, no trailing period.

## Documentation Rules

- Every public API has a one-line description of what it does, not how.
- If a function's name and signature do not tell you what it returns or when it
  fails, that is a naming problem — fix the name before adding a docstring.
- Comments explain **why**, not **what**. The code shows the what; the comment
  shows the reason a reader cannot infer.
- README is the entry point. It must explain: what the project does, how to run
  it locally, how to run the tests, and where to find the rest of the docs.
- All other documentation links back to README. Documentation that is not linked
  from somewhere will rot.

## AI Instruction Writing Guidelines

When writing instructions for an AI assistant (`CLAUDE.md`, agent prompts,
skill descriptions):

1. **Be specific about boundaries.** "Don't touch unrelated code" is weaker than
   "Edit only the files I list and do not modify imports unless necessary for
   the change to compile."
2. **State the goal, not just the steps.** The AI will improvise around blockers
   if it knows what success looks like. It will get stuck on the script if it
   only sees steps.
3. **Anchor with examples.** A single concrete input/output pair eliminates more
   ambiguity than a paragraph of prose.
4. **Show counter-examples for the easy mistakes.** "Do not write `params.foo`
   without checking it exists" beats "validate inputs."
5. **Name the verification.** Tell the AI which command demonstrates success
   ("run `make test FILTER=new_case` and confirm it passes"). Without
   a verification anchor, the AI will declare victory prematurely.
6. **Prefer "always" and "never" over "should" and "try to."** AI assistants
   read modal verbs as suggestions. Use absolutes for the rules you actually
   want enforced.
7. **Avoid second-person plural.** Write "you write a failing test first" not
   "we write a failing test first." The AI is the actor; the user is the
   reviewer.

## When These Rules Bend

These rules optimize for long-lived code under multiple maintainers. They are
overkill for:

- Throwaway prototypes that will be deleted within a week
- One-off data-cleanup scripts
- Hot-fix commits on a production incident (do whatever stops the bleeding,
  then come back and Tidy First the result)

Use judgment. When you bend a rule, say so in the commit message: "skip Tidy
First — production hotfix" is better than a silent shortcut.
