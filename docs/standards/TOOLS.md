# Tool Definition

Development tools, commands, and environment configuration.

## Common Commands

### Setup & Server

```bash
bin/setup                    # Full project setup
bin/dev                      # Run dev server (Puma + CSS/JS watchers)
bin/rails console            # Rails console
```

### Database

```bash
bin/rails db:prepare         # Create/migrate DB
bin/rails db:reset           # Reset DB (dev only)
bin/rails db:seed            # Load seed data
bin/rails db:migrate         # Run pending migrations
bin/rails db:rollback        # Rollback last migration
```

### Linting & Code Quality

```bash
bin/rubocop                  # Check style (rubocop-rails-omakase)
bin/rubocop -a               # Auto-fix
```

### Security Audits

```bash
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
```

### Testing

```bash
bin/rails test                              # Run all tests
bin/rails test test/models/foo_test.rb      # Single file
bin/rails test test/models/foo_test.rb:42   # Single test by line
```

### E2E Testing (Playwright)

Requires Node.js as a dev dependency (separate from importmap-rails):

```bash
npm init -y && npm install -D @playwright/test  # Initial setup
npx playwright install                           # Install browsers
npx playwright test                              # Run E2E tests
```

### CI Pipeline

```bash
bin/ci    # Runs: setup, rubocop, security audits, tests, seed check
```

`bin/ci` is included by Rails 8 `rails new`. Customize it to add project-specific checks (e.g., seed validation).

### Assets & Dependencies

```bash
bin/rails assets:precompile  # Build production assets
bin/importmap pin <package>  # Add JS dependency via importmap
```

### Cache & Background Jobs

```bash
bin/rails solid_cache:clear  # Clear Solid Cache
bin/rails solid_queue:start  # Start Solid Queue worker
```

### Deployment

```bash
kamal setup                  # Initial server provisioning
kamal deploy                 # Zero-downtime deployment
kamal app logs               # View application logs
docker-compose up --build    # Local deployment simulation
```

## Environment Configuration

```bash
# .env (development defaults — use credentials for secrets)
RAILS_ENV=development
USE_MOCK=true
```

### Credentials Management

```bash
rails credentials:edit --environment development
```

- Never commit sensitive information to `.env` file
- Use Rails credentials for API keys, secrets, and sensitive configuration

## API Integration Tools

See [STACK.md](STACK.md) — Adapter Pattern section.
