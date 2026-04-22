# Architecture

System architecture, technology stack, and implementation patterns.

## Project Overview

Rails monolith with Hotwire (Turbo + Stimulus), SQLite, and Solid Cache/Queue/Cable.
Exact versions: see `Gemfile.lock` (Rails), `.ruby-version` (Ruby).

## Technology Stack

### Backend

- **Framework**: Ruby on Rails
- **Asset Pipeline**: Propshaft (Rails 8 default, replaces Sprockets)
  - **importmap-rails**: Default JS management without Node.js bundling
  - Use `bin/importmap pin <package>` to add JS dependencies

### Frontend

- **Strategy**: Hotwire (Turbo + Stimulus)
  - **Turbo**: SPA-like navigation and partial page updates
  - **Turbo Frames** for pagination/tabs (no full page reloads)
  - **Turbo Streams** for partial updates
  - **Stimulus**: Pure JavaScript controllers, data-attribute conventions (`data-controller`, `data-action`, `data-*-target`)
  - **No TypeScript** — use only JavaScript
- **Styling**: TailwindCSS
- **Components**: ViewComponent for reusable UI with Lookbook for previews

### Testing

- **Framework**: Minitest (Rails default)
- **System Tests**: Rails built-in system tests with Capybara
- **Fixtures**: Rails fixtures for test data

### Database & Infrastructure

- **SQLite** with Solid Trifecta (no Redis or external services needed):
  - **Solid Cache**: Database-backed cache (replaces Redis/Memcached)
  - **Solid Queue**: Database-backed job backend (replaces Sidekiq/Resque)
  - **Solid Cable**: Database-backed Action Cable adapter (replaces Redis pub/sub)
- **Multi-DB configuration**: Each Solid service uses a separate SQLite file to avoid write lock contention. Configure in `config/database.yml` with `cache:`, `queue:`, and `cable:` entries (Rails 8 default).

### Deployment

- **Proxy**: Thruster (Go-based proxy wrapping Puma on port 80, automatic HTTP/2, compression, X-Sendfile, asset caching)
- **Tool**: Kamal 2 (primary) or Docker Compose (local)
- **Container**: Optimized Dockerfile, mount `/rails/storage` for SQLite/ActiveStorage/Solid services, run as non-root (UID/GID 1000)
- **CI/CD**: GitHub Actions (automated testing, linting, security checks)

### Sub-directory Deployment

When deploying multiple projects on a single server under sub-paths (e.g., `example.com/my-app/`):

#### Environment & Rails Config

```bash
RAILS_RELATIVE_URL_ROOT=/my-app
```

```ruby
# config/environments/production.rb
config.relative_url_root = ENV.fetch("RAILS_RELATIVE_URL_ROOT", "/")
```

```ruby
# config.ru
map ENV.fetch("RAILS_RELATIVE_URL_ROOT", "/") do
  run Rails.application
end
```

#### Asset Pipeline (Propshaft)

- Always use `asset_path` / `asset_url` helpers — they respect `relative_url_root` automatically
- Never hardcode absolute paths like `/assets/...` in CSS or JS

#### Hotwire (Turbo + Stimulus)

- **Turbo Drive**: Set turbo-root meta tag in layout:
  ```erb
  <meta name="turbo-root" content="<%= config.relative_url_root %>">
  ```
- **Action Cable**: Adjust mount path in routes:
  ```ruby
  mount ActionCable.server => "#{config.relative_url_root}/cable"
  ```
- **Stimulus controllers**: Pass paths via `data-*` attributes or `<meta>` tags — never hardcode URL paths in JS

#### Reverse Proxy (nginx → Thruster)

```nginx
location /my-app/ {
    proxy_pass http://thruster-upstream/;  # trailing slash strips prefix
    proxy_set_header X-Forwarded-Prefix /my-app;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_for_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

#### Kamal 2

```yaml
# config/deploy.yml
env:
  clear:
    RAILS_RELATIVE_URL_ROOT: /my-app
```

#### Checklist

| Item | Verify |
|------|--------|
| `*_path` / `*_url` helpers | Include prefix (no hardcoded absolute paths) |
| JS fetch/XHR paths | Receive base path from `data-*` or `<meta>` |
| Action Cable connection | WebSocket path includes prefix |
| `redirect_to` | Automatically includes prefix |
| Health check path | Adjust Kamal/load balancer health check URL |
| Solid Queue Web UI | Adjust mount path if exposed |

### Background Jobs

- **Backend**: Solid Queue (database-backed, no Redis)
- **Worker**: `bin/rails solid_queue:start`
- **Use Cases**: Heavy API calls, email delivery, data processing
- **Kamal**: Deploy as separate `job` role for resource isolation

## Architecture Patterns

### Service Objects

`app/services/*_service.rb` — Follow single responsibility principle, provide unified interface via `call` method.

### Adapter Pattern

API communication abstraction with mock support:

```ruby
# app/adapters/base_adapter.rb
class BaseAdapter
  def self.for(provider)
    ENV['USE_MOCK'] == 'true' ? MockAdapter.new : RealAdapter.new
  end
end
```

- **Dev server**: `USE_MOCK=true` in `.env` for rapid feedback without network calls.
- **Tests**: Use constructor injection for test isolation instead of environment variables:
  ```ruby
  class SomeService
    def initialize(adapter: BaseAdapter.for(:provider))
      @adapter = adapter
    end
  end
  # In tests: SomeService.new(adapter: MockAdapter.new)
  ```

### Custom Errors

Define in `app/errors/custom_error.rb` with `rescue_from` in controllers.

### Authentication

OAuth-only via OmniAuth 2.x (no password). Providers: Google (`omniauth-google-oauth2`), Naver (`omniauth-naver`), Kakao (`omniauth-kakao-oauth2` — plain `omniauth-kakao` is pinned to omniauth 1.x and incompatible).

Session model: every visitor gets a `User` row. Guests (`guest: true`) are per-session, identified by a `guest_token`; account users (`guest: false`) have at least one row in `identities` (`provider`, `uid`, unique scope). `ApplicationController#ensure_current_user` restores the session from `session[:user_id]`, then from a signed `remember_token` cookie (account users only), otherwise creates a new guest.

OAuth callback pipeline:

1. `Auth::{Google,Kakao,Naver}Adapter#to_profile` — normalize omniauth `auth_hash` into `Auth::ProviderProfile` (`provider`, `uid`, `email`, `email_verified`, `name`, `avatar_url`). `email_verified` is tri-state: `true`, `false`, or `nil` (provider did not report).
2. `SessionCreator` — three cases:
   - **Case A** — existing `Identity(provider, uid)` → attach, merge current guest in.
   - **Case B** — `email` matches existing account user → attach new identity, merge.
   - **Case C** — new user → promote current guest in place (preserves all guest-owned data).
3. `GuestMerger` — dispatches per-association via `User.mergeable_reflections` (associations annotated with `merge_policy:` + `natural_key:`). Policies: `:prefer_guest` (guest wins on natural-key collisions), `:keep_target` (target wins; used for `api_credentials`).

Defense: `reset_session` after every successful callback, `rack-attack` throttles `/auth/*` POST at 10/min/IP, `Auth::Error` hierarchy is `rescue_from`-caught in `ApplicationController`.

Ops: `GuestCleanupJob` (scheduled daily 3am in `config/recurring.yml`) destroys guests inactive for 30 days; `last_seen_at` is throttled to one write per minute via `Rails.cache`.

Test helpers: `mock_omniauth` in `test_helper.rb`, `/testing/sign_in` and `/testing/set_remember_cookie` routes (test env only) for integration tests that need to seed session or cookie state.

### Caching Strategy

- **Fragment caching**: UI components that don't change frequently
- **API response caching**: External API call results (TTL setting required)
- Use Solid Cache as the backend

## Hotwire Best Practices

### Turbo Frame Usage

```erb
<%= turbo_frame_tag "items" do %>
  <%= render @items %>
<% end %>
```

### Turbo Stream Response

```ruby
# controller
respond_to do |format|
  format.turbo_stream
  format.html
end
```

### Stimulus Controller Naming

- `data-controller="search"`
- `data-action="input->search#submit"`
- `data-search-target="input"`

## UI/Frontend Rules

UI components follow the project's design tokens and specs. When creating new components, follow patterns from existing components for consistency.

### Icons

Icons are sourced from Heroicons v2 via the `rails_heroicon` gem. The default variant is `outline` (`stroke-width="1.5"` per DESIGN.md). Use the `heroicon` helper to render icons:

```erb
<%= heroicon "archive-box", class: "w-12 h-12 text-slate-300" %>
```

All new icons should use this helper; inline SVGs will be migrated progressively.

## Internationalization (i18n)

- Use Rails `I18n` API (`config/locales/*.yml`) as primary translation engine
- Use structured translation keys: `t('login.button.submit')`, convention: `[page_or_component].[element].[action]`
- Recommended gems: `rails-i18n`, `i18n-tasks`, `mobility` (for DB record translations)

## Rails 8 — Do NOT Use (Removed/Deprecated)

- **Classic Autoloader**: Completely removed. Use Zeitwerk only.
- **Rails UJS**: Removed. Use Turbo instead.
- **Sprockets**: Replaced by Propshaft. Do not add `sprockets` gem.
- **Webpack/Webpacker**: Use importmap-rails instead.
- **`params.require().permit()` for new code**: Prefer `params.expect()`.
