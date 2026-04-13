# STANDARDS.md

* This file provides guidance to all AI-agents when working with code in this project.

## **IMPORTANT** 

- **Orchestrator** owns global truth + integration. Add gates, verify end-to-end, and never assume infrastructure exists without proof

## Special order
USE **KOREAN** to explain your answer.
USE **ENGLISH** to make the .md or .yaml file.

## TDD & Engineering Principles (Kent Beck Style)

### 1. Development Cycle
Follow the **Red-Green-Refactor** loop strictly for every task:
- **RED**: Write a failing test first.
- **GREEN**: Write the minimum code required to pass.
- **REFACTOR**: Clean up the code only after the test passes.

### 2. "Tidy First" Rule
- Separate **Structural Changes** (refactoring) from **Behavioral Changes** (new logic).
- NEVER mix them in a single commit.
- If the code is hard to change, tidy it first, then implement the change.
- **Rails Example**: Before adding a new feature to a complex `Controller#update`, refactor long private methods into a dedicated `Service Object` or `Domain Model`.

### 3. Standards
- **DRY**: Ruthlessly eliminate duplication.
- **Explicit Dependencies**: Make all dependencies clear and avoid hidden side effects.

## Technology Stack

### Backend & Frontend (Monolith)

- **Framework**: Ruby on Rails 8.1
- **Language**: Ruby 3.4.8
- **Asset Pipeline**: Propshaft (Rails 8 default, replaces Sprockets)
  - **importmap-rails**: Default JS management without Node.js bundling
  - Use `bin/importmap pin <package>` to add JS dependencies
- **Frontend Strategy**: Hotwire (Turbo + Stimulus)
  - **Turbo**: SPA-like navigation and partial page updates
  - **Stimulus**: Modest JavaScript for client-side interactivity. Stimulus controllers should use pure JavaScript (no TypeScript)
  - **Typescript**: Use only JavaScript instead of TypeScript.
- **Styling**: TailwindCSS (or Vanilla CSS with modern variables)
- **Database & Infrastructure**: SQLite with Solid Trifecta
  - **Solid Cache**: Database-backed cache (replaces Redis/Memcached)
  - **Solid Queue**: Database-backed job backend (replaces Sidekiq/Resque)
  - **Solid Cable**: Database-backed Action Cable adapter (replaces Redis pub/sub for WebSockets)
  - Rails 8 defaults heavily optimized for SQLite in production
- **Authentication**: Skipped in MVP. Post-MVP plan:
  - Rails 8 built-in authentication generator (`bin/rails generate authentication`)
  - OAuth/social login (Google, Kakao, etc.) via OmniAuth
  - Uses `has_secure_password` with encrypted cookies
- **Mock Data**: Recommended to use Mock data in early development stages
  - Set `USE_MOCK=true` in `.env` file
  - Switch to `USE_MOCK=false` when actual API integration is ready

### Testing

- **TDD Principle**: Strictly follow the [Red-Green-Refactor cycle](#1-development-cycle) defined in Section 1.
- **Framework**: Minitest (Rails 8 default)
- **Test Pyramid** (maintain this ratio):
  - **Unit** (majority): Service Objects, Models, Helpers
  - **Integration** (moderate): Controller + View integration
  - **System/E2E** (few): Major user scenarios only
- **Test Coverage**: Aim for minimum 80% coverage with SimpleCov
- **E2E Testing**: Playwright (or System Tests with Capybara/Cuprite)
- **Performance**: K6

### Deployment

- **Proxy**: Thruster (Rails 8 default)
  - Go-based proxy wrapping Puma on port 80
  - Automatic HTTP/2, compression, X-Sendfile, asset caching
- **Tool**: Kamal 2 (primary) or Docker Compose (local/simple)
  - `kamal setup` — initial server provisioning
  - `kamal deploy` — zero-downtime deployment
  - Kamal Proxy handles SSL certificates automatically
- **Containerization**: Optimized Dockerfile for Rails 8
  - Mount named Docker volume at `/rails/storage` (SQLite, ActiveStorage, Solid services)
  - Run as non-root user (UID/GID 1000)
- **CI/CD**: GitHub Actions (Rails 8 provides default CI template)
  - Automated testing, linting (RuboCop), and security vulnerability checks

### Background Jobs

- **Backend**: Solid Queue (database-backed, no Redis required)
- **Worker**: `bin/rails solid_queue:start`
- **Use Cases**: Heavy API calls, email delivery, data processing
- **Kamal**: Deploy as separate `job` role for resource isolation
  ```yaml
  # config/deploy.yml
  servers:
    web: ...
    job:
      cmd: bin/rails solid_queue:start
  ```

## Development Commands

```bash
# Setup
bundle install
bin/rails db:prepare

# Development (Run server + CSS/JS watchers)
bin/dev

# Console
bin/rails console

# Authentication (Rails 8 built-in)
bin/rails generate authentication

# Database
bin/rails db:reset          # DB reset (development environment)
bin/rails db:seed           # Load seed data
bin/rails db:migrate        # Run pending migrations
bin/rails db:rollback       # Rollback last migration

# Code Quality
bin/rubocop                  # Check Ruby code style
bin/rubocop -a               # Auto-fix

# Assets (Propshaft)
bin/rails assets:precompile # Build production assets
bin/importmap pin <package> # Add JS dependency via importmap

# Cache
bin/rails solid_cache:clear # Clear Solid Cache

# Background Jobs
bin/rails solid_queue:start # Start Solid Queue worker

# Testing
bin/rails test

# E2E Testing
npx playwright test

# Deploy
kamal setup                 # Initial server setup
kamal deploy                # Deploy to production
kamal app logs              # View application logs

# Deploy (Local simulation)
docker-compose up --build
```

## Key Implementation Notes

### Architecture Patterns
- **Service Objects**: `app/services/*_service.rb`
  - Follow single responsibility principle
  - Provide unified interface via `call` method
- **Adapter Pattern**: API communication abstraction
  ```ruby
  # app/adapters/base_adapter.rb
  class BaseAdapter
    def self.for(provider)
      ENV['USE_MOCK'] == 'true' ? MockAdapter.new : RealAdapter.new
    end
  end
  ```
- **TDD Synergy**: The `MockAdapter` is essential for rapid TDD feedback loops, allowing tests to run without network or external dependencies.
- **Caching Strategy**:
  - Fragment caching: UI components that don't change frequently
  - API response caching: External API call results (TTL setting required)
- **Error Handling**:
  - Define custom errors in `app/errors/custom_error.rb`
  - Consistent error handling with `rescue_from` in controllers

### API Integration

- Use `Faraday` or `HTTP` gem for API communication.
- Implement a generic Adapter pattern to switch between Real API and Mock API easily based on configuration.

### UI/UX Requirements

- **ViewComponent**: Reusable, testable UI components in `app/components/`
  - Each component = Ruby class + template (ERB/HTML)
  - Use Lookbook (`/lookbook` in development) for component previews and documentation
- **Hotwire Navigation**: Ensure `<turbo-frame>` is used for navigation scenarios like pagination and tab switching to avoid full page reloads.
- **Stimulus Controllers**:
  - `clipboard_controller.js`: For copy-to-clipboard functionality.
  - `theme_controller.js`: For Dark/Light mode toggling.
  - `search_controller.js`: Debounced search input submission.
  - `session_storage_controller.js`: Store session IDs in localStorage for recovery (no auth).
  - `navigation_controller.js`: Browser back button handling in sequential flows.
  - Additional controllers as needed for specific UI interactions.

### Internationalization (i18n)
- **Built-in Standard**: Use the built-in Rails `I18n` API (`config/locales/*.yml`) as the primary translation engine.
- **Resource IDs**: Do not hardcode UI strings. Use structured translation keys (e.g., `t('login.button.submit')`). Maintain a hierarchical naming convention: `[page_or_component].[element].[action]`.
- **Recommended Gems**:
  - `rails-i18n`: For default translations of framework messages (dates, currencies, Active Record errors).
  - `i18n-tasks`: To detect missing translations and clean up unused translation keys.
  - `mobility`: Use this instead of `globalize` if database record translations are required.

### Hotwire Best Practices
- **Turbo Frame Usage**:
```erb
  <%= turbo_frame_tag "items" do %>
    <%= render @items %>
  <% end %>
```
- **Turbo Stream Response**:
```ruby
  # controller
  respond_to do |format|
    format.turbo_stream
    format.html
  end
```
- **Stimulus Controller Naming**:
  - `data-controller="search"`
  - `data-action="input->search#submit"`
  - `data-search-target="input"`
- **Browser Back Button Handling**:
  - Intercept browser back button in sequential flows (e.g., checklist questions) to navigate to previous question instead of browser history
  - Use Stimulus `navigation_controller.js` with `popstate` event handling
  - Ensure Turbo Drive does not create conflicting history entries for single-question-at-a-time flows

## Core Features to Implement

1. **Item Listing** (`*Controller#index`)
    - Grid/list layout of items.
    - Server-side filtering and pagination.

2. **Item Details** (`*Controller#show`)
    - Expandable view or separate page showing details.
    - Item metadata (size, digest, created_at, etc.).

3. **Search & Filter**
    - Turbo Streams to update the item list in real-time as the user types (or debounced).

## Development Guidelines

### Code Style

- **Ruby**: Standard (rubocop).
- **JS**: Prettier / StandardJS.
- **CSS**: Tailwind classes or BEM if custom CSS.

### Security Best Practices
- **Credentials Management**:
  - `rails credentials:edit --environment development`
  - Never commit sensitive information to `.env` file
- **CSRF Protection**: Maintain Rails default settings
- **Parameter Handling**: Use `params.expect` (Rails 8 preferred) over `params.require().permit()`
  ```ruby
  # Rails 8 recommended
  params.expect(article: [:title, :body, :published])
  
  # Legacy (still works but less safe)
  params.require(:article).permit(:title, :body, :published)
  ```
- **ReDoS Prevention**: `Regexp.timeout = 1` is set by default in Rails 8
- **XSS Prevention**:
  - Use `sanitize` helper
  - Configure `content_security_policy.rb`
- **Rate Limiting**: Limit API requests with Rack::Attack

### Accessibility (UX Simulation Findings)

- **Status Indicators**: Always display text labels alongside emoji statuses (e.g., "🔴 입찰 비추천", not just "🔴"). Add ARIA labels for screen readers.
- **Keyboard Navigation**: Ensure all interactive elements (buttons, form inputs, links) are reachable via Tab key. Checklist question answers must be selectable via keyboard.
- **Form Inputs**: NUMBER fields must use `inputmode="numeric"` for mobile keyboard optimization. Display unit suffix (%, 원, 년) adjacent to input.
- **Tooltips**: Legal/auction terminology should have inline `help_text` tooltips, accessible via hover (desktop) and tap (mobile).
- **Color Independence**: Never rely on color alone to convey status. Always pair with text and/or icons.
- **Responsive Design**: Mobile-first approach using TailwindCSS breakpoints. Ensure touch targets are at least 44x44px.

### Performance

- **Fragment Caching**: Cache HTML fragments for frequently used UI components.
- **Eager Loading**: Not applicable for API calls, but ensure parallel requests if possible or background loading for heavy data.
- **Prevent N+1 Queries**:
  - Use `includes`, `preload`, `eager_load` appropriately
  - Monitor with Bullet gem
- **Database Indexing**:
  - Add indexes to columns frequently used for search/filtering

## Rails 8 — Do NOT Use (Removed/Deprecated)

- **Classic Autoloader**: Completely removed. Use Zeitwerk only.
- **Rails UJS**: Removed from codebase. Use Turbo instead.
- **Sprockets**: Replaced by Propshaft. Do not add `sprockets` gem.
- **Webpack/Webpacker**: Use importmap-rails or jsbundling-rails instead.
- **`params.require().permit()` for new code**: Prefer `params.expect()`.

## Environment Configuration

```bash
# .env (development defaults — use credentials for secrets)
RAILS_ENV=development
USE_MOCK=true
```

## Git & Commit Standards

- **Small Commits**: Commit every time a test passes or a refactoring is done.
- **English Only**: Always write commit messages in English.
- **Tidy First Commits**: NEVER mix Structural Changes (refactoring) and Behavioral Changes (new logic) in a single commit. If you tidy code to prepare for a change, commit the tidying separately.
