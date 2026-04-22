# UI/UX Rails-UI Compliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the existing Rails UI (layouts, views, partials, turbo_stream responses) into compliance with the `/rails-ui` skill spec (`~/.claude/skills/rails-ui/DESIGN.md` + `design_tokens.json`). Fix four categories of drift: (1) no ViewComponent extraction — every form/badge/card is inline, (2) concrete rule violations (emoji-as-icon `🔒`, `text-xs` below minimum, `gray-*` palette in `index.turbo_stream.erb`, icon-missing action buttons), (3) minor color/contrast deviations (`bg-amber-100` badge, `text-slate-500` labels), (4) accessibility gap on native `<details>` accordion.

**Architecture:** Introduce `view_component` gem + `app/components/`. Extract six components whose Tailwind class strings come verbatim from DESIGN.md Section 3: `ButtonComponent`, `BadgeComponent`, `InputComponent`, `SelectComponent`, `TextareaComponent`, `CardComponent`. Migrate each view to call these components *with zero visible change* (Phase B, purely structural). Only after migration, apply the rule-violation fixes (Phase C, purely behavioral) so the diff is easy to audit. `index.turbo_stream.erb` is rewritten as part of Phase C because migration alone cannot fix its drift.

**Tech Stack:** Rails 8.1 (Ruby 3.4.8), SQLite, RSpec + Capybara (project's actual framework), Stimulus (pure JS, no TypeScript), TailwindCSS 3 via `tailwindcss-rails`, ViewComponent (to be added), Heroicons v2 via inline SVG (helper adoption optional, see Task 3).

**Source spec:** `/rails-ui` skill at `~/.claude/skills/rails-ui/DESIGN.md` + `design_tokens.json`. Full review and rationale for every fix in the conversation that generated this plan (see `docs/standards/WORKFLOW.md` for pipeline context).

**Non-negotiables from CLAUDE.md:**
- **TDD** — Red-Green-Refactor for every component. Preview + spec before implementation.
- **Tidy First** — Structural commits (gem, components, migrations) NEVER mixed with behavioral commits (rule fixes). This plan enforces strict separation.
- **Small Commits** — One task = one commit, committed as soon as tests pass.
- **Korean for conversation, English for code/markdown/commits.**

---

## Pre-flight

- [ ] **Step 0: Ensure clean working tree**

```bash
git status
```
Expected: clean. If dirty, stash or commit first.

- [ ] **Step 1: Baseline tests green**

```bash
bin/rails db:test:prepare
bundle exec rspec --fail-fast
```
Expected: PASS for all existing specs. Fix pre-existing failures first (not this plan's responsibility, but they must not mask new failures).

- [ ] **Step 2: Baseline visual snapshots**

Before any change, capture screenshots of every page at 375px / 768px / 1280px in both light and dark mode for regression comparison. Pages to snapshot:
- `/repositories` (index) — empty state AND with data
- `/repositories/:name` (show) — details collapsed AND expanded
- `/repositories/:name/tags/:tag` (tag show) — with layers AND docker_config
- `/repositories/:name/tags/:tag/history` — with events AND empty
- `/help`

Store snapshots in `tmp/ui-baseline/` (gitignored).

---

## Phase A — Structural preparation

### Task 1: Add `view_component` gem

**Why this is a separate commit:** Adding a gem is a pure infrastructure change with no behavior. Isolates dependency update from any code using it.

**Files:**
- Modify: `Gemfile`
- Modify: `Gemfile.lock` (auto)
- Modify: `config/application.rb` (add preview path)

**Steps:**

- [ ] Add to `Gemfile` in the main group:

```ruby
gem "view_component"
```

- [ ] Run `bundle install`

- [ ] Add to `config/application.rb` inside `class Application < Rails::Application`:

```ruby
config.view_component.preview_paths << Rails.root.join("test/components/previews").to_s
config.view_component.default_preview_layout = "component_preview"
```

- [ ] Create the preview layout at `app/views/layouts/component_preview.html.erb` with Tailwind stylesheets loaded so previews render correctly.

- [ ] Create directories:

```bash
mkdir -p app/components spec/components test/components/previews
```

- [ ] Verify: `bundle exec rspec` still passes, `bin/rails routes | grep rails/view_components` shows the preview route mounted in dev.

**Commit:** `chore: add view_component gem for UI component extraction`

### Task 2: Remove unused `.container-custom` @apply block

**Why this is a separate commit:** Dead-code removal is a pure structural change independent of component work.

**Files:**
- Modify: `app/assets/stylesheets/application.tailwind.css`

**Steps:**

- [ ] Verify unused: `grep -r "container-custom" app/ config/` → expect 0 results.

- [ ] Delete lines 17–21 (the `@layer components { .container-custom { @apply ... } }` block).

- [ ] Run `bin/rails tailwindcss:build` and reload app. Spot-check any page looks identical.

**Commit:** `refactor: remove unused .container-custom @apply block`

### Task 3: (OPTIONAL) Adopt Heroicon helper

**Why this is a separate commit:** Optional infrastructure. Skip if team prefers inline SVG — but then Phase C must enforce `stroke-width="1.5"` manually.

**Files:**
- Modify: `Gemfile`
- Create: `app/helpers/icon_helper.rb` (if choosing custom helper over gem)

**Option A — gem (`rails_heroicon`):**

- [ ] Add `gem "rails_heroicon"` to `Gemfile`, `bundle install`.
- [ ] Replace ONE inline SVG in `app/views/repositories/index.html.erb` (the empty-state archive box) with `<%= heroicon "archive-box", options: { class: "w-12 h-12 text-slate-300 dark:text-slate-600 mb-4" } %>` as a pilot.

**Option B — custom helper:**

- [ ] Create `app/helpers/icon_helper.rb` with a `heroicon(name, class:)` method that reads SVG files from `app/assets/images/heroicons/outline/`.
- [ ] Vendor needed icons only (archive-box, trash, check, chevron-right, chevron-down, lock-closed, magnifying-glass, clipboard, arrow-left, question-mark-circle, sun, moon).

**Decision point:** Choose Option A unless there's a policy against adding gems. Document the choice in `docs/standards/STACK.md`.

**Commit:** `chore: adopt Heroicon helper for consistent icon rendering` (Option A) or `feat: add icon_helper with vendored Heroicons` (Option B)

---

## Phase B — Component extraction (structural, zero behavior change)

> ⚠ **Tidy First enforcement:** In this phase, the extracted components MUST reproduce the existing Tailwind classes verbatim (copy-paste). Do NOT apply any Phase C fixes yet. Visual diff before/after each task must be empty.

### Task 4: `ButtonComponent` + preview + spec

**Why this is a separate commit:** New component with zero callers — cannot regress anything.

**Files:**
- Create: `app/components/button_component.rb`
- Create: `app/components/button_component.html.erb`
- Create: `test/components/previews/button_component_preview.rb`
- Create: `spec/components/button_component_spec.rb`

**Steps:**

- [ ] **Red:** Write `spec/components/button_component_spec.rb` covering:
  - Variants: primary / secondary / outline / danger / ghost / link (all six)
  - Sizes: sm (`h-8`) / md (`h-10`) / lg (`h-12`)
  - Disabled state: `opacity-50 cursor-not-allowed pointer-events-none`
  - Icon option: renders Heroicon before text with `gap-2`
  - Submit mode: renders as `<button type="submit">`
  - Link mode (`href:`): renders as `<a>` with correct classes

- [ ] **Green:** Implement `ButtonComponent` per DESIGN.md Section 3.1. The `VARIANTS` and `SIZES` hashes copy DESIGN.md strings verbatim. Support three render modes via initializer: default `<button>`, submit (`type: :submit`), link (`href:`).

- [ ] Run `bundle exec rspec spec/components/button_component_spec.rb` — all green.

- [ ] Write `ButtonComponentPreview` with one preview method per variant × size combo.

- [ ] Start `bin/dev`, visit `/rails/view_components`, verify all previews render correctly in both light and dark mode.

**Commit:** `feat(components): add ButtonComponent per DESIGN.md 3.1`

### Task 5: `BadgeComponent` + preview + spec

**Files:** `app/components/badge_component.{rb,html.erb}`, preview, spec.

**Steps:**

- [ ] **Red:** Spec for variants (default / success / warning / danger / info / accent), `icon:` option (renders Heroicon before text with `gap-1.5`), content slot.

- [ ] **Green:** Implement per DESIGN.md Section 3.5. Background floor `*-200` for light mode where DESIGN.md specifies `*-50` — use `*-200 text-*-800` to match the Light Mode Minimum Contrast Rule (this resolves the internal DESIGN.md conflict noted in the review).

- [ ] Preview all six variants × (with icon / without icon) combos.

**Commit:** `feat(components): add BadgeComponent per DESIGN.md 3.5`

### Task 6: `InputComponent` + preview + spec

**Files:** `app/components/input_component.{rb,html.erb}`, preview, spec.

**Steps:**

- [ ] **Red:** Spec for `size:` (sm `h-8` / md `h-10` / lg `h-12`), `type:` (text/email/password/search), `error:` state (red border, aria-describedby), `help_text:`, `label:`, `required:` (red asterisk).

- [ ] **Green:** Implement per DESIGN.md Section 3.3. Label uses `text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5`.

**Commit:** `feat(components): add InputComponent per DESIGN.md 3.3`

### Task 7: `SelectComponent` + preview + spec

**Files:** `app/components/select_component.{rb,html.erb}`, preview, spec.

**Steps:**

- [ ] Spec for `options:` (array of [label, value]), `selected:`, `size:` (same h-* tokens as Input), `label:`, `help_text:`, `error:`.
- [ ] Match Input's height tokens exactly so inline groupings align (DESIGN.md 3.3 Inline Height Consistency Rule).

**Commit:** `feat(components): add SelectComponent per DESIGN.md 3.3`

### Task 8: `TextareaComponent` + preview + spec

**Files:** `app/components/textarea_component.{rb,html.erb}`, preview, spec.

**Steps:**

- [ ] Spec for `rows:`, `label:`, `placeholder:`, `error:`, `help_text:`.
- [ ] Textarea uses `py-2.5 resize-y` — no `h-*` since it's multi-line (explicit exception from Input rule).

**Commit:** `feat(components): add TextareaComponent per DESIGN.md 3.3`

### Task 9: `CardComponent` + preview + spec

**Why this is a separate commit:** Card pattern appears in 7+ places (repositories/index, show; tags/show, history; help section blocks). Extraction has high payoff.

**Files:** `app/components/card_component.{rb,html.erb}`, preview, spec.

**Steps:**

- [ ] **Red:** Spec for optional `header:` slot, required default content (body), optional `footer:` slot, optional `padding: :none` to let callers control inner padding (e.g., table rows).
- [ ] **Green:** Implement per DESIGN.md Section 3.2. Default padding `p-6`, header `px-6 py-4 border-b`, footer `px-6 py-4 border-t bg-slate-50/50`.
- [ ] Preview: basic card, card with header, card with header + footer, card with `padding: :none` + embedded DataList.

**Commit:** `feat(components): add CardComponent per DESIGN.md 3.2`

### Task 10: Migrate `_repository_card.html.erb`

**Why this is a separate commit:** Structural — swap inline classes for component calls. Visual output identical. Smallest view, good starting point to validate the pattern.

**Files:**
- Modify: `app/views/repositories/_repository_card.html.erb`

**Steps:**

- [ ] Replace the outer `link_to` wrapper's Tailwind classes with a `CardComponent` wrapped in `link_to`, passing `class:` to the link.
- [ ] Replace the "Docker Image" inline badge with `<%= render BadgeComponent.new(variant: :info) { "Docker Image" } %>`.
- [ ] Keep the repository-name heading, metadata row, and chevron icon as-is (they're display content, not components).
- [ ] Verify: compare screenshots from Pre-flight Step 2 — pixel-diff should show no change.
- [ ] Run `bundle exec rspec spec/features/repositories_index_spec.rb` (or equivalent system test).

**Commit:** `refactor(views): migrate _repository_card to Card + Badge components`

### Task 11: Migrate `app/views/repositories/index.html.erb`

**Files:** `app/views/repositories/index.html.erb`

**Steps:**

- [ ] Replace search bar's raw `f.text_field` and `f.select` with `InputComponent` and `SelectComponent` (size `:md` for both — already matches current `h-10`).
- [ ] Wrap the search bar in `CardComponent.new(padding: :md)` (outer `div.rounded-lg.bg-white...`).
- [ ] Extract empty-state markup into a new partial or keep inline — either works, but note the structure will be reused in `index.turbo_stream.erb` (Task 18).
- [ ] Verify visual diff is empty.

**Commit:** `refactor(views): migrate repositories/index to components`

### Task 12: Migrate `app/views/repositories/show.html.erb`

**Files:** `app/views/repositories/show.html.erb`

**Steps:**

- [ ] Top info card → `CardComponent`.
- [ ] "Docker pull command" row → keep as inline `<div>` (specialized clipboard component, not a Card).
- [ ] Back nav link → keep as `link_to` with icon (it's navigation, not an action button).
- [ ] `<details>` Edit section:
  - Form textarea → `TextareaComponent`
  - Form text fields → `InputComponent`
  - Select → `SelectComponent`
  - Submit button → `ButtonComponent.new(variant: :primary, type: :submit, icon: "check") { "Save" }` (note: this adds an icon — FLAG: this is technically a Phase C behavioral change sneaking in. **If strict Tidy First required, commit Save without the icon here, then add icon in Task 21.**)
- [ ] Desktop tags grid: keep CSS Grid structure, but Protected badge → `BadgeComponent.new(variant: :warning)` with `"Protected"` content. **NOTE:** Do not fix emoji / text-xs yet — preserve the violation; Task 19 fixes it. In this commit, pass `"🔒 Protected"` literally to preserve identical output.
- [ ] Tags grid: Delete button → `ButtonComponent.new(variant: :link, size: :sm, icon: "trash", href: ...)` or `button_to` wrapper with ButtonComponent-equivalent classes.
- [ ] Mobile card stack: same component swaps. Preserve the missing-icon bug on Delete (Task 20 will fix).
- [ ] Bottom "Delete Repository" button → `ButtonComponent.new(variant: :danger, icon: "trash")`.

**Commit:** `refactor(views): migrate repositories/show to components`

### Task 13: Migrate `app/views/tags/show.html.erb`

**Files:** `app/views/tags/show.html.erb`

**Steps:**

- [ ] Info card → `CardComponent`.
- [ ] Layers card → `CardComponent` with `padding: :none` + header slot for the "Layers (N)" title.
- [ ] Docker Config card → `CardComponent`.
- [ ] Top-level Delete Tag button → `ButtonComponent.new(variant: :danger, icon: "trash")`.
- [ ] Preserve `🔒 Protected` / `text-xs` for now (Task 19 fix).

**Commit:** `refactor(views): migrate tags/show to components`

### Task 14: Migrate `app/views/tags/history.html.erb`

**Files:** `app/views/tags/history.html.erb`

**Steps:**

- [ ] Each event wrapper → `CardComponent`.
- [ ] Action badge (create/update/delete) → `BadgeComponent.new(variant: mapping)` where mapping is `create: :success, update: :warning, delete: :danger`.
- [ ] Empty state — keep inline (same pattern as index).

**Commit:** `refactor(views): migrate tags/history to components`

### Task 15: Migrate `app/views/help/show.html.erb`

**Files:** `app/views/help/show.html.erb`

**Steps:**

- [ ] Each section wrapper → `CardComponent`.
- [ ] Final "Supported Image Formats" alert block: keep as custom warning panel (amber-100 bg + border) — this is a specialized callout, not a Card variant. Alternatively, add a `CardComponent` variant `:warning` in a follow-up. **For this task: leave inline.**

**Commit:** `refactor(views): migrate help/show to components`

### Task 16: Phase B checkpoint — full regression

- [ ] Run the full test suite: `bundle exec rspec && bundle exec rspec spec/system`.
- [ ] Re-capture screenshots for all pages at all viewports and compare to baselines (Pre-flight Step 2). Any visual diff is a bug — fix before proceeding to Phase C.
- [ ] Verify `/rails/view_components` previews all render.

**No commit** — checkpoint gate only.

---

## Phase C — Rule-violation fixes (behavioral)

> ⚠ From here on, diffs are intentionally visible. Each commit should be reviewable in under 2 minutes.

### Task 17: Fix Protected badge — emoji, font size, contrast

**Why this is a separate commit:** Single bug fix covering three rule violations that must all be addressed atomically (partial fix would leave the badge inconsistent with peer badges).

**Files:**
- Modify: `app/views/tags/show.html.erb` (desktop grid + mobile card, both instances)

**Steps:**

- [ ] **Red:** Add a system spec that visits a tag page where the tag is protected and asserts:
  - No `🔒` emoji character in the rendered HTML (`expect(page.body).not_to include("🔒")`)
  - An SVG with `data-icon="lock-closed"` or the heroicon's path signature is present
  - The badge has class `text-sm` (not `text-xs`)

- [ ] **Green:** Replace:

```erb
<span class="... text-xs ... bg-amber-100 ...">
  🔒 Protected
</span>
```

with:

```erb
<%= render BadgeComponent.new(variant: :warning, icon: "lock-closed") do %>
  Protected
<% end %>
```

The `BadgeComponent` already enforces `text-sm`, `bg-*-200` floor (via Task 5), and Heroicon rendering (via Task 5's `icon:` option) — so this one-line swap resolves all three violations.

- [ ] Verify: run the spec, inspect the rendered page at `/repositories/:name` with a protected tag.

**Commit:** `fix(ui): protected badge — replace emoji with Heroicon, fix font size and contrast`

### Task 18: Rewrite `index.turbo_stream.erb`

**Why this is a separate commit:** The entire file is drift — rewrite is clearer than a piecemeal fix.

**Files:**
- Modify: `app/views/repositories/index.turbo_stream.erb`

**Steps:**

- [ ] **Red:** Add a request spec at `spec/requests/repositories_search_spec.rb`:

```ruby
it "returns turbo_stream matching index.html.erb structure" do
  get repositories_path(q: "nonexistent"), as: :turbo_stream
  expect(response.body).not_to include("gray-")       # no gray palette
  expect(response.body).not_to include('stroke-width="2"') # 1.5 only
  expect(response.body).to include("slate-")          # uses slate
end
```

- [ ] **Green:** Rewrite the file to mirror `index.html.erb`'s card grid + empty state exactly. All `gray-*` → `slate-*`. SVG `stroke-width` → `1.5` (or use heroicon helper from Task 3). Empty state uses the `flex flex-col items-center justify-center py-16 px-4` structure from DESIGN.md Section 3.10. `Load More` link → `ButtonComponent.new(variant: :outline, icon: "chevron-down") { "Load More" }`.

- [ ] Verify: spec passes, manually trigger search at `/repositories?q=...` and inspect the DOM diff against initial page load — should be identical card markup.

**Commit:** `fix(ui): align index.turbo_stream with main index view — resolve palette and structure drift`

### Task 19: Add Heroicon to Save submit button

**Files:**
- Modify: `app/views/repositories/show.html.erb`

**Steps:**

- [ ] **Red:** System spec asserting the Save button has an SVG child (icon).
- [ ] **Green:** Update the `ButtonComponent` call from Task 12 to pass `icon: "check"`.
- [ ] If Task 12 already added the icon (non-strict path), skip this task.

**Commit:** `fix(ui): add Heroicon to repository save button`

### Task 20: Restore mobile Delete button icon

**Files:**
- Modify: `app/views/tags/show.html.erb` (mobile card stack, around line 215)

**Steps:**

- [ ] **Red:** System spec at mobile viewport (375px) — `resize_window_to(375, 800)` — asserting the Delete button on the tag list has a trash SVG.
- [ ] **Green:** In the mobile card Delete button (`button_to` in the `md:hidden` block), change the `ButtonComponent.new(variant: :link, size: :sm)` call to include `icon: "trash"`. Match the desktop version.

**Commit:** `fix(ui): mobile tag delete button — restore trash icon`

### Task 21: Normalize label colors

**Files:**
- Modify: `app/views/repositories/show.html.erb` (lines ~31, ~42)

**Steps:**

- [ ] **Red:** Visual regression — manually verify before/after: labels "Description" and "Maintainer" should use `text-slate-700 dark:text-slate-300` (label role) per DESIGN.md Visual Hierarchy table.
- [ ] **Green:** Change `text-slate-500 dark:text-slate-400` → `text-slate-700 dark:text-slate-300` on the two label `<p>` elements.

**Commit:** `fix(ui): use spec-compliant label color (slate-700)`

---

## Phase D — Accessibility & policy (optional)

### Task 22 (OPTIONAL): Add focus-visible ring to `<details>` summary

**Why this is a separate commit:** Accessibility fix, independent from component work.

**Files:**
- Modify: `app/views/repositories/show.html.erb` (line ~53 `<summary>`)

**Steps:**

- [ ] Add to summary classes:

```
focus-visible:ring-2 focus-visible:ring-blue-500/50 focus-visible:ring-offset-2
dark:focus-visible:ring-blue-400/50 dark:focus-visible:ring-offset-slate-900
rounded-md outline-none
```

- [ ] Verify via keyboard: Tab to the summary, confirm visible focus ring in both light and dark mode.

**Commit:** `fix(a11y): add focus ring to edit-details summary`

### Task 23 (OPTIONAL): `container mx-auto` policy decision

**Why this is a separate commit:** Team decision, not a mechanical fix.

**Files:** `app/views/layouts/application.html.erb`, possibly `docs/standards/STACK.md`.

**Steps:**

- [ ] Discuss with team: wide-monitor readability (current) vs data density (DESIGN.md-preferred full width).
- [ ] If removing `container mx-auto`: update both `<nav>` wrapper and `<main>` wrapper consistently so edges still align.
- [ ] Document the chosen direction in `docs/standards/STACK.md`.

**Commit (if changing):** `refactor(layout): remove container max-width for full-bleed content density`
**Commit (if keeping):** `docs: document container max-width decision in STACK.md`

---

## Phase E — Integration verification

- [ ] **Step V1: Full test suite green**

```bash
bundle exec rspec
bundle exec rspec spec/system
```

- [ ] **Step V2: Lint clean**

```bash
bin/rubocop
bin/brakeman --quiet
```

- [ ] **Step V3: Visual regression**

Re-capture screenshots for all pages at 375 / 768 / 1280 in light + dark. Compare against Pre-flight Step 2 baselines. Phase B diffs should be empty. Phase C diffs should match the documented intentional changes (new Heroicon, updated colors, rewritten turbo_stream).

- [ ] **Step V4: Turbo Stream response**

Manually trigger search/sort at `/repositories?q=...&sort=name`. Inspect the returned turbo-stream HTML — should be structurally identical to initial page render.

- [ ] **Step V5: Dark mode toggle**

Toggle on every page. No flashes, no low-contrast text, no broken rings.

- [ ] **Step V6: Keyboard navigation**

Tab through each page. Every interactive element must show a focus ring. `<details>` summary must be reachable and toggleable via Enter/Space.

- [ ] **Step V7: Mobile responsive**

At 375px, verify every page: mobile card stacks render, forms stack vertically, no horizontal scroll, touch targets ≥ 44px.

---

## Commit order reference

```
[structural]
 1. chore: add view_component gem
 2. refactor: remove unused .container-custom @apply block
 3. chore: adopt Heroicon helper                            (OPTIONAL)
 4. feat(components): add ButtonComponent
 5. feat(components): add BadgeComponent
 6. feat(components): add InputComponent
 7. feat(components): add SelectComponent
 8. feat(components): add TextareaComponent
 9. feat(components): add CardComponent
10. refactor(views): migrate _repository_card
11. refactor(views): migrate repositories/index
12. refactor(views): migrate repositories/show
13. refactor(views): migrate tags/show
14. refactor(views): migrate tags/history
15. refactor(views): migrate help/show
16. (checkpoint — no commit)

[behavioral]
17. fix(ui): protected badge — emoji, font, contrast
18. fix(ui): align index.turbo_stream with main index view
19. fix(ui): add Heroicon to repository save button
20. fix(ui): mobile tag delete button — restore trash icon
21. fix(ui): use spec-compliant label color

[optional]
22. fix(a11y): focus ring on edit-details summary
23. refactor(layout) OR docs: container max-width decision
```

---

## PR packaging recommendation

- **PR 1 — "UI: introduce ViewComponent infrastructure"** — Tasks 1–16 (structural only, zero visible change)
- **PR 2 — "UI: fix rails-ui skill rule violations"** — Tasks 17–21 (behavioral)
- **PR 3 (optional) — "UI: accessibility and policy"** — Tasks 22–23

Each PR independently shippable. PR 1 can merge without blocking PR 2. If bandwidth is limited, PR 2 can be hot-fixed before PR 1 by applying Tasks 17–21 directly to the inline-styled views — but this duplicates work when PR 1 lands. Prefer strict order.

---

## Risks & mitigations

| Risk | Mitigation |
|------|-----------|
| Phase B migration introduces visual regression | Baseline screenshots (Pre-flight Step 2) + Task 16 checkpoint before any Phase C work |
| `text-*` / `*-` class strings change behavior when compiled by Tailwind JIT (unlikely but possible via purging) | `content:` glob in `tailwind.config.js` already covers `app/components/**/*.{rb,erb}` since it matches `app/**/*.erb` and `app/helpers/**/*.rb` — verify after Task 1 by building CSS and grep-checking the output |
| ViewComponent learning curve | Task 4 (ButtonComponent) is the reference — all subsequent components follow identical pattern. Review ViewComponent docs: https://viewcomponent.org/guide/ |
| 21+ commits feels excessive | Tidy First non-negotiable per CLAUDE.md. Group into PRs (above) but keep commits atomic for bisect safety |
| Heroicon helper decision (Task 3) delays Phase C | Task 3 is OPTIONAL. Skip if uncertain; Phase C enforces stroke-width=1.5 manually via code review |
| Protected badge fix (Task 17) depends on BadgeComponent icon support (Task 5) | Task ordering enforces this — Task 5's spec explicitly tests `icon:` option, so BadgeComponent is ready by the time Task 17 runs |
