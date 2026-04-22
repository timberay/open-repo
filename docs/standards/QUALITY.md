# Evaluation Criteria

Testing strategy, security standards, code quality, accessibility, and performance guidelines.

## Testing Strategy

### Framework

- **Unit/Integration**: Minitest (Rails 8 default)
- **E2E**: Playwright (or System Tests with Capybara/Cuprite)
- **Performance**: K6

### Test Pyramid (maintain this ratio)

- **Unit** (majority): Service Objects, Models, Helpers
- **Integration** (moderate): Controller + View integration
- **System/E2E** (few): Major user scenarios only

### Test Coverage

- Target minimum **80%** coverage with SimpleCov
- Every new feature must include corresponding tests
- Bug fixes must include a regression test

## Code Style

- **Ruby**: Standard (rubocop-rails-omakase)
- **JavaScript**: Prettier / StandardJS
- **CSS**: Tailwind utility classes or BEM if custom CSS

## Security Best Practices

### CSRF Protection

Maintain Rails default settings. Never disable CSRF.

### Parameter Handling

```ruby
# Rails 8 recommended — raises if key is missing
params.expect(article: [:title, :body, :published])

# For optional parameters, use permit or fetch with default
params.permit(:sort_by, :page)
params.fetch(:page, 1)
```

### ReDoS Prevention

`Regexp.timeout = 1` is set by default in Rails 8.

### XSS Prevention

- Use `sanitize` helper for user-generated content
- Configure `content_security_policy.rb`
- Never use `raw` or `html_safe` on untrusted input

### Rate Limiting

Limit API requests with `Rack::Attack` (`config/initializers/rack_attack.rb`). `/auth/*` POST endpoints throttled at 10/min/IP.

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

## Performance Guidelines

### Fragment Caching

Cache HTML fragments for frequently used UI components.

### Eager Loading

Use parallel requests or background loading for heavy external data.

### Prevent N+1 Queries

- Use `includes`, `preload`, `eager_load` appropriately
- Monitor with Bullet gem

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

### Manual Review

- [ ] Structural and behavioral changes are in separate commits
- [ ] New features have corresponding tests
- [ ] Accessibility requirements are met for UI changes
- [ ] No N+1 queries introduced
- [ ] Fragment caching applied where appropriate

## Pre-commit Failure Recovery

When a pre-commit hook (rubocop, test, etc.) fails, fix it yourself and retry — do not stop and ask the user.

- **Rubocop violation**: Run `bin/rubocop -a` to auto-fix, then re-stage and re-commit
- **Test failure**: Diagnose the failing test, fix the code, verify with `bin/rails test`, then re-commit
- **Multiple issues**: Fix rubocop first, then tests, then re-commit
