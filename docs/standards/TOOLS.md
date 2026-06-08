# Tool Definition

Development tools, commands, and environment configuration.

## Common Commands

### Setup & Server

```bash
bin/setup                    # Full project setup
bin/dev                      # Run dev server (Procfile.dev: Puma + tailwindcss:watch)
bin/rails console            # Rails console
```

### Database

```bash
bin/rails db:prepare              # Create + migrate (idempotent — safe default)
bin/rails db:migrate              # Run pending migrations
bin/rails db:rollback             # Rollback last migration
bin/rails db:seed                 # Run db/seeds.rb (idempotent — uses find_or_create_by!)
bin/rails db:seed:replant         # Truncate + reseed (used by bin/ci to verify seed correctness)
bin/rails db:reset                # DROP + recreate + migrate + seed — destroys data; dev only
```

`db:reset` and `db:seed:replant` are destructive — never run them against shared/production environments.

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

### E2E / Browser Automation

The project uses **`playwright-ruby-client`** (in Gemfile) — Playwright driven from inside the Rails process. The court auction scraper (`app/adapters/court_auction/browser_client.rb`) is the canonical user. It shares fixtures, models, and configuration with the rest of the app.

There is no Node.js setup (no `package.json`, no `npm`). Do not introduce a Node-based Playwright runner without first updating [STACK.md](STACK.md) — importmap-rails is the only JS toolchain in this repo.

System tests (`test/system/`) drive Capybara via headless Chrome through `selenium-webdriver`; they are not Playwright. See [QUALITY.md → Testing Strategy](QUALITY.md#testing-strategy) for which tool fits which scenario.

### CI Pipeline

```bash
bin/ci    # Runs the steps defined in config/ci.rb
```

Pipeline steps (see `config/ci.rb`): `bin/setup --skip-server` → `bin/rubocop` → `bin/bundler-audit` → `bin/importmap audit` → `bin/brakeman` → `bin/rails test` → `RAILS_ENV=test bin/rails db:seed:replant`. System tests (`bin/rails test:system`) are commented out — enable when system test suite is stabilized.

### Assets & Dependencies

```bash
bin/rails assets:precompile  # Build production assets
bin/importmap pin <package>  # Add JS dependency via importmap
```

### Cache & Background Jobs

```bash
bin/rails solid_cache:clear  # Clear Solid Cache
bin/jobs                     # Start Solid Queue worker (Rails 8 default)
```

### Deployment

```bash
kamal setup                  # Initial server provisioning
kamal deploy                 # Zero-downtime deployment
kamal app logs               # View application logs
```

There is no `docker-compose.yml`; for local Docker testing, build with `docker build -t auction .` and run the resulting image directly. Do not add `docker-compose.yml` without first updating [STACK.md → Deployment](STACK.md#deployment).

## Environment Configuration

```bash
# .env (development defaults — use credentials for secrets)
RAILS_ENV=development
USE_MOCK=true                # Forces all adapters to return mock responses (no network)
LLM_PROVIDER=anthropic       # anthropic|openai|gemini|ollama|openrouter (when USE_MOCK=false)
```

`dotenv` is loaded in development/test only. Production reads env from Kamal `env:` blocks or Rails credentials.

### Credentials Management

```bash
rails credentials:edit --environment development
rails credentials:edit --environment production
```

- Never commit sensitive information to `.env`
- Use Rails credentials for API keys, OAuth client secrets, and any production credentials
