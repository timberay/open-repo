# Evaluation Criteria

Testing strategy, security standards, code quality, accessibility, and performance guidelines.

## Testing Strategy

### Framework

- **Unit/Integration**: Minitest (Rails 8 default)
- **System tests**: Capybara + `selenium-webdriver` (headless Chrome via `ApplicationSystemTestCase`)
- **HTTP stubbing**: `webmock` — registered in `test/test_helper.rb`; disable real HTTP in adapter tests
- **Controller test helpers**: `rails-controller-testing` re-enables `assigns(...)` / `assert_template` for legacy-style assertions
- **External-app E2E**: `playwright-ruby-client` for scraper/black-box flows (see [TOOLS.md → E2E / Browser Automation](TOOLS.md#e2e--browser-automation))
- **Performance**: No load-testing tool currently in the stack — add one (and document here) before publishing performance budgets

### Test Pyramid (maintain this ratio)

- **Unit** (majority): Service Objects, Models, Helpers
- **Integration** (moderate): Controller + View integration
- **System/E2E** (few): Major user scenarios only

### Test Coverage

- Every new feature must include corresponding tests
- Bug fixes must include a regression test that fails before the fix and passes after

## Code Style

- **Ruby**: `rubocop-rails-omakase` (run `bin/rubocop`, auto-fix with `bin/rubocop -a`)
- **JavaScript**: No formatter is currently wired into `bin/ci`. Match existing Stimulus controller style.
- **CSS**: TailwindCSS utility classes only — avoid introducing custom CSS

## Security Best Practices

### CSRF Protection

Maintain Rails default settings. Never disable CSRF.

### Parameter Handling

Use `params.expect` for required structured params (Rails 8). It raises when the key is missing, so missing-key bugs surface during request parsing instead of inside actions.

```ruby
# Required nested params
params.expect(article: [ :title, :body, :published ])

# Optional top-level params
params.permit(:sort_by, :page)
params.fetch(:page, 1)
```

Do not introduce new `params.require(...).permit(...)` chains — see [STACK.md → Rails 8 — Do NOT Use](STACK.md#rails-8--do-not-use-removeddeprecated).

### ReDoS Prevention

`Regexp.timeout = 1` is set by default in Rails 8.

### XSS Prevention

- Use `sanitize` helper for user-generated content
- Configure `content_security_policy.rb`
- Never use `raw` or `html_safe` on untrusted input

### Rate Limiting

Use `Rack::Attack` (`config/initializers/rack_attack.rb`) for any new rate-limited endpoint. The auth throttle is documented in [STACK.md → Authentication](STACK.md#authentication); do not redocument it here.

### Credentials

- Use `rails credentials:edit` for secrets
- Never commit `.env` files with real credentials

## Accessibility Standards

### Status Indicators

Always display text labels alongside emoji statuses (e.g., "Red circle Not recommended" not just "Red circle"). Add ARIA labels for screen readers.

### Keyboard Navigation

Ensure all interactive elements (buttons, form inputs, links) are reachable via Tab key. Checklist question answers must be selectable via keyboard.

### Form Inputs

- NUMBER fields must use `inputmode="numeric"` for mobile keyboard optimization
- Display unit suffix (%, won, year) adjacent to input

### Tooltips

Legal/auction terminology should have inline `help_text` tooltips, accessible via hover (desktop) and tap (mobile).

### Color Independence

Never rely on color alone to convey status. Always pair with text and/or icons.

### Responsive Design

Mobile-first approach using TailwindCSS breakpoints. Ensure touch targets are at least 44x44px.

### Automated Accessibility Checks

`axe-core-capybara` is wired into system tests via `ApplicationSystemTestCase`; the baseline suite at `test/system/a11y_baseline_test.rb` runs axe on critical pages. Add new pages to that test (or write a focused axe assertion) when introducing UI that materially changes structure.

## Performance Guidelines

### Fragment Caching

Cache a fragment when **all three** are true: it renders on a hot path (search results, property list, manual page), its underlying data changes less often than once per request, and re-rendering measurably costs >50ms in dev. Use Solid Cache as the backend (configured in `config/cache.yml`). Add a Rails fragment cache key tied to the model's `updated_at` so invalidation is automatic.

### Prevent N+1 Queries

- Use `includes`, `preload`, `eager_load` appropriately
- Inspect `log/development.log` for repeated `SELECT` patterns when in doubt; add the `bullet` gem to the development group if continuous monitoring becomes necessary

### Off-request Work for Heavy External Calls

Move slow third-party calls (LLM analysis, court-auction scraping, PDF processing) off the request path via Solid Queue jobs. The user should see a Turbo-Stream/poll update when the job finishes — never block the request.

### Database Indexing

Add indexes to columns frequently used for search/filtering.

## Evidence-Driven Self-Diagnosis

You have no eyes or memory beyond what you explicitly capture. Logs and screenshots
are the only evidence you can use to diagnose problems autonomously — if you didn't
record it, it doesn't exist for you.

### Why This Matters

- You cannot re-observe a past UI state or a transient error after it disappears.
- Detailed evidence lets you form hypotheses and verify fixes without asking humans.
- Vague or missing logs force you to guess, which violates the TDD principle of
  working from facts.

### What to Capture

| Situation | What to Record |
|-----------|---------------|
| Running a command | Full stdout/stderr output, not a summary |
| UI change | Screenshot before AND after |
| Test failure | Complete error message, stack trace, and the test command used |
| Unexpected behavior | Steps to reproduce, expected vs. actual result |
| External API call | Request payload, response status, and response body |

For diagnosis workflow, follow the `systematic-debugging` skill.

## Code Review Checklist

### Automated (by `bin/ci`)

- [ ] All tests pass (`bin/rails test`)
- [ ] No linting errors (`bin/rubocop`)
- [ ] No security warnings (`bin/brakeman`)
- [ ] No dependency vulnerabilities (`bin/bundler-audit`)
- [ ] No vulnerable importmap pins (`bin/importmap audit`)
- [ ] Seeds replant cleanly (`RAILS_ENV=test bin/rails db:seed:replant`)

### Manual Review

- [ ] Structural and behavioral changes are in separate commits
- [ ] New features have corresponding tests
- [ ] Accessibility requirements are met for UI changes
- [ ] No N+1 queries introduced
- [ ] Fragment caching applied where appropriate

## Pre-commit Failure Recovery

This project enforces commit gates via Claude Code `PreToolUse` hooks (`.claude/settings.json`). Every `git commit*` invocation runs, in order:

1. `bin/rails test` — full Minitest suite (timeout 120s)
2. `bin/rubocop --format quiet` — style check (timeout 60s)

If either fails, the hook denies the commit and surfaces the output. **Fix it yourself and retry — do not stop and ask the user.**

- **Rubocop violation**: `bin/rubocop -a` to auto-fix, manually resolve any remainder, re-stage, re-commit.
- **Test failure**: Diagnose the failing test, fix the code, verify locally with `bin/rails test`, re-commit.
- **Multiple issues**: Fix rubocop first (cheap), then tests, then re-commit.

There is also a `PostToolUse` hook on `Write|Edit` that runs `bin/rubocop` on the touched `.rb` file — surface fixes immediately rather than batching them at commit time.
