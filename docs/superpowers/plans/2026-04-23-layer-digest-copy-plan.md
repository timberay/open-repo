# FINDING-011 Layer Digest Copy Affordance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a click-to-copy affordance to each layer digest on the tag show page so users can grab the full `sha256:...` digest without manual selection/retyping.

**Architecture:** Introduce a small ViewComponent `DigestComponent` that encapsulates `{short digest text + copy button}`, re-using the existing Stimulus `clipboard_controller`. Replace the two ad-hoc `short_digest(layer.blob.digest)` call-sites in the Layers section of `app/views/tags/show.html.erb` (desktop grid + mobile stack). The copy button swaps its icon to a checkmark on success via the controller's existing `icon` target contract.

**Tech Stack:** Rails 8.1, ViewComponent, TailwindCSS 4, Stimulus (existing `clipboard_controller.js`), `rails_heroicon` gem, RSpec + Capybara matchers.

**Branch policy:** Commit directly onto the current branch `chore/design-review-polish` — do NOT start a new branch/worktree. Bundling with the prior 9 shipped findings in one PR was the explicit decision.

**Scope — explicitly not included:**
- Manifest digest at `tags/show.html.erb:17` (top card) — same smell, different finding, handle separately.
- Previous/new digests on `tags/history.html.erb` — same smell, separate follow-up.
- Adding success-icon swap to the existing "docker pull" box — out of finding scope.
- FINDING-001 typography (needs product decision), 012 (product signal), 013 (minor, low value).

---

## File Structure

- **Create:** `app/components/digest_component.rb` — ViewComponent class. Validates digest presence, exposes `short` (12-char tail) for display and `full` (original) for copying. Frozen string literal header, ASCII-only, matches `BadgeComponent` conventions.
- **Create:** `app/components/digest_component.html.erb` — Renders an inline `<span data-controller="clipboard" data-clipboard-text-value="...">` containing the short-digest text plus a `<button>` with a heroicon clipboard SVG targeted as the clipboard controller's `icon` target.
- **Create:** `spec/components/digest_component_spec.rb` — Component-level spec, mirrors `spec/components/badge_component_spec.rb` style (uses `render_inline` + Capybara `page` matchers).
- **Modify:** `app/views/tags/show.html.erb` — Replace `short_digest(layer.blob.digest)` at line 85 (desktop grid) and line 99 (mobile stack) with `render DigestComponent.new(digest: layer.blob.digest)`. On mobile, drop the now-unneeded `text-slate-400 dark:text-slate-500 tabular-nums truncate` wrapper classes (component owns presentation).
- **Modify:** `spec/requests/tags_spec.rb` — Add a `describe 'GET /repositories/:name/tags/:name'` block with integration assertions that layer rows expose the clipboard data attributes and the full digest value.

Component responsibility is intentionally narrow: render a single copyable digest. If other digest call-sites (manifest top card, history) adopt this later, the component's interface is ready; adopting them is out of scope here.

---

## Task 1: Build DigestComponent (TDD)

**Files:**
- Create: `app/components/digest_component.rb`
- Create: `app/components/digest_component.html.erb`
- Test: `spec/components/digest_component_spec.rb`

### Cycle 1 — Component renders the short (12-char) digest text

- [ ] **Step 1.1: Write the failing test**

Create `spec/components/digest_component_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe DigestComponent, type: :component do
  let(:full) { "sha256:1d1ddb624e47aabbccddeeff00112233445566778899aabbccddeeff00112233" }

  describe "display text" do
    it "renders the first 12 characters of the hex portion of the digest" do
      render_inline(described_class.new(digest: full))

      expect(page).to have_text("1d1ddb624e47")
      expect(page).not_to have_text("sha256:")
    end
  end
end
```

- [ ] **Step 1.2: Run the test to verify it fails**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: FAIL with `NameError: uninitialized constant DigestComponent`.

- [ ] **Step 1.3: Write the minimal implementation**

Create `app/components/digest_component.rb`:

```ruby
# frozen_string_literal: true

# DigestComponent renders a truncated digest with a click-to-copy button.
#
# Displays the first 12 hex characters of a `sha256:...` digest and exposes
# the full digest value to the Stimulus `clipboard` controller for copying.
#
# Usage:
#   <%= render DigestComponent.new(digest: layer.blob.digest) %>
class DigestComponent < ViewComponent::Base
  SHORT_LENGTH = 12

  def initialize(digest:)
    @digest = digest.to_s
  end

  def full
    @digest
  end

  def short
    @digest.sub(/\Asha256:/, "")[0, SHORT_LENGTH].to_s
  end
end
```

Create `app/components/digest_component.html.erb`:

```erb
<span class="inline-flex items-center gap-1 font-mono text-slate-600 dark:text-slate-400 tabular-nums">
  <span><%= short %></span>
</span>
```

- [ ] **Step 1.4: Run the test to verify it passes**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: PASS (1 example, 0 failures).

- [ ] **Step 1.5: Commit**

```bash
git add app/components/digest_component.rb app/components/digest_component.html.erb spec/components/digest_component_spec.rb
git commit -m "feat(components): add DigestComponent rendering short digest text"
```

### Cycle 2 — Component wires the full digest into Stimulus clipboard controller

- [ ] **Step 2.1: Write the failing test**

Append to `spec/components/digest_component_spec.rb` (inside the outer `describe DigestComponent` block, after the `describe "display text"` block):

```ruby
  describe "clipboard wiring" do
    it "attaches the clipboard Stimulus controller with the full digest as the copy value" do
      render_inline(described_class.new(digest: full))

      expect(page).to have_css(
        "[data-controller='clipboard'][data-clipboard-text-value='#{full}']"
      )
    end
  end
```

- [ ] **Step 2.2: Run the test to verify it fails**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: FAIL — "expected to find css ... [data-controller='clipboard']" (zero matches).

- [ ] **Step 2.3: Update the template to attach the controller**

Edit `app/components/digest_component.html.erb` to read:

```erb
<span class="inline-flex items-center gap-1 font-mono text-slate-600 dark:text-slate-400 tabular-nums"
      data-controller="clipboard"
      data-clipboard-text-value="<%= full %>">
  <span><%= short %></span>
</span>
```

- [ ] **Step 2.4: Run the test to verify it passes**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: PASS (2 examples, 0 failures).

- [ ] **Step 2.5: Commit**

```bash
git add app/components/digest_component.html.erb spec/components/digest_component_spec.rb
git commit -m "feat(components): wire DigestComponent to clipboard controller"
```

### Cycle 3 — Component renders the copy button with accessible label and icon target

- [ ] **Step 3.1: Write the failing test**

Append to `spec/components/digest_component_spec.rb` (inside the outer `describe DigestComponent` block, after the `describe "clipboard wiring"` block):

```ruby
  describe "copy button" do
    before { render_inline(described_class.new(digest: full)) }

    it "renders a button that triggers clipboard#copy" do
      expect(page).to have_css("button[data-action='click->clipboard#copy']")
    end

    it "gives the button an accessible label naming the digest" do
      expect(page).to have_css("button[aria-label='Copy digest 1d1ddb624e47']")
    end

    it "marks the inner svg as the clipboard icon target for success-state swapping" do
      expect(page).to have_css("button svg[data-clipboard-target='icon']")
    end
  end
```

- [ ] **Step 3.2: Run the test to verify it fails**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: FAIL — no `button[data-action=...]` present yet.

- [ ] **Step 3.3: Add the copy button to the template**

Replace `app/components/digest_component.html.erb` with:

```erb
<span class="inline-flex items-center gap-1 font-mono text-slate-600 dark:text-slate-400 tabular-nums"
      data-controller="clipboard"
      data-clipboard-text-value="<%= full %>">
  <span><%= short %></span>
  <button type="button"
          data-action="click->clipboard#copy"
          aria-label="Copy digest <%= short %>"
          class="p-1 -m-1 rounded text-slate-400 hover:text-slate-600 dark:text-slate-500 dark:hover:text-slate-300 hover:bg-slate-200/60 dark:hover:bg-slate-700/60 transition-colors duration-150 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500">
    <svg data-clipboard-target="icon" class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
    </svg>
  </button>
</span>
```

- [ ] **Step 3.4: Run the test to verify it passes**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: PASS (5 examples, 0 failures).

- [ ] **Step 3.5: Commit**

```bash
git add app/components/digest_component.html.erb spec/components/digest_component_spec.rb
git commit -m "feat(components): render copy button with aria-label and icon target"
```

### Cycle 4 — Blank/nil digest renders nothing unsafe

- [ ] **Step 4.1: Write the failing test**

Append to `spec/components/digest_component_spec.rb` (inside the outer `describe DigestComponent` block):

```ruby
  describe "edge cases" do
    it "renders an empty short and no copy button when digest is blank" do
      render_inline(described_class.new(digest: ""))

      expect(page).not_to have_css("button[data-action='click->clipboard#copy']")
    end

    it "renders an empty short and no copy button when digest is nil" do
      render_inline(described_class.new(digest: nil))

      expect(page).not_to have_css("button[data-action='click->clipboard#copy']")
    end
  end
```

- [ ] **Step 4.2: Run the test to verify it fails**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: FAIL — button is always rendered today.

- [ ] **Step 4.3: Guard the template on presence**

Replace `app/components/digest_component.html.erb` with:

```erb
<% if full.present? %>
  <span class="inline-flex items-center gap-1 font-mono text-slate-600 dark:text-slate-400 tabular-nums"
        data-controller="clipboard"
        data-clipboard-text-value="<%= full %>">
    <span><%= short %></span>
    <button type="button"
            data-action="click->clipboard#copy"
            aria-label="Copy digest <%= short %>"
            class="p-1 -m-1 rounded text-slate-400 hover:text-slate-600 dark:text-slate-500 dark:hover:text-slate-300 hover:bg-slate-200/60 dark:hover:bg-slate-700/60 transition-colors duration-150 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500">
      <svg data-clipboard-target="icon" class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
      </svg>
    </button>
  </span>
<% end %>
```

- [ ] **Step 4.4: Run the test to verify it passes**

Run: `bundle exec rspec spec/components/digest_component_spec.rb --fail-fast`
Expected: PASS (7 examples, 0 failures).

- [ ] **Step 4.5: Commit**

```bash
git add app/components/digest_component.html.erb spec/components/digest_component_spec.rb
git commit -m "feat(components): guard DigestComponent against blank/nil digest"
```

---

## Task 2: Use DigestComponent in the desktop layers grid

**Files:**
- Modify: `app/views/tags/show.html.erb:85` (the desktop grid Digest cell)
- Test: `spec/requests/tags_spec.rb` (new integration block)

- [ ] **Step 2.1: Write the failing integration test**

Append to `spec/requests/tags_spec.rb` before the final `end`:

```ruby
  describe 'GET /repositories/:name/tags/:name' do
    let!(:blob) { Blob.create!(digest: 'sha256:1d1ddb624e47aabbccddeeff0011223344556677', size: 4096) }
    let!(:layer) { Layer.create!(manifest: manifest, blob: blob, position: 0) }

    it 'renders each layer digest with a click-to-copy affordance carrying the full digest' do
      get "/repositories/#{repo.name}/tags/#{tag.name}"

      expect(response).to be_successful
      expect(response.body).to include("data-clipboard-text-value=\"#{blob.digest}\"")
      expect(response.body).to match(%r{aria-label="Copy digest 1d1ddb624e47"})
      expect(response.body).to include("1d1ddb624e47")
    end
  end
```

- [ ] **Step 2.2: Run the test to verify it fails**

Run: `bundle exec rspec spec/requests/tags_spec.rb:<line> --fail-fast`
(Use the `GET /repositories/:name/tags/:name` describe block's first example line; if unsure, run `bundle exec rspec spec/requests/tags_spec.rb --fail-fast` and confirm the new example fails.)
Expected: FAIL — the view still uses `short_digest(...)` without the clipboard data attributes.

- [ ] **Step 2.3: Replace the desktop grid digest cell with the component**

In `app/views/tags/show.html.erb`, locate the desktop grid row (currently lines 82–88):

```erb
    <% @layers.each do |layer| %>
      <div class="grid border-t border-slate-100 dark:border-slate-700/50 hover:bg-slate-50/50 dark:hover:bg-slate-700/50 transition-colors" style="grid-template-columns: 60px 1fr 120px">
        <div class="px-4 py-3 text-sm text-slate-600 dark:text-slate-400 tabular-nums"><%= layer.position %></div>
        <div class="px-4 py-3 text-sm font-mono text-slate-600 dark:text-slate-400 tabular-nums"><%= short_digest(layer.blob.digest) %></div>
        <div class="px-4 py-3 text-sm text-slate-600 dark:text-slate-400 tabular-nums text-right"><%= human_size(layer.blob.size) %></div>
      </div>
    <% end %>
```

Replace the Digest cell so it reads:

```erb
    <% @layers.each do |layer| %>
      <div class="grid border-t border-slate-100 dark:border-slate-700/50 hover:bg-slate-50/50 dark:hover:bg-slate-700/50 transition-colors" style="grid-template-columns: 60px 1fr 120px">
        <div class="px-4 py-3 text-sm text-slate-600 dark:text-slate-400 tabular-nums"><%= layer.position %></div>
        <div class="px-4 py-3 text-sm"><%= render DigestComponent.new(digest: layer.blob.digest) %></div>
        <div class="px-4 py-3 text-sm text-slate-600 dark:text-slate-400 tabular-nums text-right"><%= human_size(layer.blob.size) %></div>
      </div>
    <% end %>
```

The component owns font, color, and alignment. Outer `text-sm` sets row-level size to stay consistent with the other cells.

- [ ] **Step 2.4: Run the test to verify it passes**

Run: `bundle exec rspec spec/requests/tags_spec.rb --fail-fast`
Expected: PASS — both the new example and all previously-passing DELETE examples still green.

- [ ] **Step 2.5: Commit**

```bash
git add app/views/tags/show.html.erb spec/requests/tags_spec.rb
git commit -m "feat(ui): use DigestComponent for layer digests on desktop grid"
```

---

## Task 3: Use DigestComponent in the mobile layer stack

**Files:**
- Modify: `app/views/tags/show.html.erb:99` (the mobile card digest paragraph)
- Test: `spec/requests/tags_spec.rb` (extend integration expectation)

- [ ] **Step 3.1: Tighten the failing test**

Edit the integration example added in Task 2. Replace its body with:

```ruby
    it 'renders each layer digest with a click-to-copy affordance carrying the full digest' do
      get "/repositories/#{repo.name}/tags/#{tag.name}"

      expect(response).to be_successful
      # Both the desktop grid cell and the mobile card render the component,
      # so the clipboard wiring should appear twice for a single layer.
      expect(response.body.scan("data-clipboard-text-value=\"#{blob.digest}\"").size).to eq(2)
      expect(response.body.scan(%r{aria-label="Copy digest 1d1ddb624e47"}).size).to eq(2)
    end
```

- [ ] **Step 3.2: Run the test to verify it fails**

Run: `bundle exec rspec spec/requests/tags_spec.rb --fail-fast`
Expected: FAIL — currently only the desktop grid uses the component (count == 1, expected 2).

- [ ] **Step 3.3: Replace the mobile card digest line with the component**

In `app/views/tags/show.html.erb`, locate the mobile card block (currently lines 92–102):

```erb
  <div class="md:hidden divide-y divide-slate-100 dark:divide-slate-700/50">
    <% @layers.each do |layer| %>
      <div class="px-4 py-3">
        <div class="flex items-center justify-between mb-1">
          <span class="text-sm font-medium text-slate-700 dark:text-slate-300">Layer #<%= layer.position %></span>
          <span class="text-sm text-slate-600 dark:text-slate-400 tabular-nums"><%= human_size(layer.blob.size) %></span>
        </div>
        <p class="text-sm font-mono text-slate-400 dark:text-slate-500 tabular-nums truncate"><%= short_digest(layer.blob.digest) %></p>
      </div>
    <% end %>
  </div>
```

Replace the `<p>` line with a component render. The outer wrapper keeps `text-sm`; the component owns font family and color:

```erb
  <div class="md:hidden divide-y divide-slate-100 dark:divide-slate-700/50">
    <% @layers.each do |layer| %>
      <div class="px-4 py-3">
        <div class="flex items-center justify-between mb-1">
          <span class="text-sm font-medium text-slate-700 dark:text-slate-300">Layer #<%= layer.position %></span>
          <span class="text-sm text-slate-600 dark:text-slate-400 tabular-nums"><%= human_size(layer.blob.size) %></span>
        </div>
        <div class="text-sm"><%= render DigestComponent.new(digest: layer.blob.digest) %></div>
      </div>
    <% end %>
  </div>
```

Note: the mobile paragraph previously used `text-slate-400 dark:text-slate-500` — the component uses `text-slate-600 dark:text-slate-400` instead, which both raises contrast and matches the desktop row. This unification is intentional; it removes a subtle FINDING-006-style contrast drift on mobile while consolidating styling. Also drops the now-redundant `truncate` (12 chars always fits).

- [ ] **Step 3.4: Run the test to verify it passes**

Run: `bundle exec rspec spec/requests/tags_spec.rb --fail-fast`
Expected: PASS — both responsive views now render the component.

- [ ] **Step 3.5: Commit**

```bash
git add app/views/tags/show.html.erb spec/requests/tags_spec.rb
git commit -m "feat(ui): use DigestComponent for layer digests on mobile stack"
```

---

## Task 4: Full-suite regression check

**Files:** none modified; verification only.

- [ ] **Step 4.1: Run the full spec suite**

Run: `bundle exec rspec`
Expected: 281 + 7 (new DigestComponent) + 1 (new tag show integration) = 289 examples, 0 failures (pending count unchanged).

- [ ] **Step 4.2: If anything fails, stop and investigate**

Do not amend prior commits. Create a new commit with the fix on top.

- [ ] **Step 4.3: Run RuboCop against new/changed files**

Run: `bundle exec rubocop app/components/digest_component.rb app/components/digest_component.html.erb app/views/tags/show.html.erb spec/components/digest_component_spec.rb spec/requests/tags_spec.rb`
Expected: no offenses. (If erb_lint is wired via rubocop, it will catch template issues; if not, inspect manually for trailing whitespace.)

- [ ] **Step 4.4: Manual browser verification (one-time, not committed)**

1. Start the dev server: `bin/dev`
2. Navigate to `http://localhost:3000/repositories/whoami/tags/<any-tag>` (adjust for a real tag).
3. Confirm the Layers table shows the 12-char digest with a small clipboard icon next to each row.
4. Click a copy button — the icon should swap to a checkmark for ~2s, and pasting elsewhere should yield the full `sha256:...` string.
5. Resize to 375px wide — confirm the mobile card stack shows the same affordance and contrast is readable in both light and dark mode.
6. Keyboard focus test: Tab through the page — the copy button should show a visible blue focus ring.

No code changes from this step; if problems surface, loop back and add a failing test first.

---

## Self-Review Checklist (run after writing — already done)

1. **Spec coverage:** Every finding requirement (copy affordance + reuses existing controller) is covered by Tasks 1–3. ✓
2. **Placeholder scan:** No TBD/TODO/"similar to" text; every code step contains the actual code. ✓
3. **Type consistency:** `DigestComponent.new(digest:)` signature used identically in Tasks 1/2/3 and in all test examples. `short` and `full` methods referenced consistently in both spec assertions and template. ✓

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-23-layer-digest-copy-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
