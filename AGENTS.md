# AGENTS.md

This file provides guidance to OpenCode w/ oh-my-opencode when working with code in this repository.

## Special order
USE KOREAN to explan your answer.

## Project Overview

**RepoVista** - A Docker Registry Web UI service that provides developers with an intuitive interface to browse and select Docker images for deployment.

## Technology Stack

### Backend & Frontend (Monolith)

- **Framework**: Ruby on Rails 8
- **Language**: Ruby 3.x
- **Frontend Strategy**: Hotwire (Turbo + Stimulus) 
  - **Turbo**: SPA-like navigation and partial page updates
  - **Stimulus**: Modest JavaScript for client-side interactivity
  - **Typescript**: Use only JavaScript instead of TypeScript. 
- **Styling**: TailwindCSS (or Vanilla CSS with modern variables)
- **Database/Caching**: SQLite (Solid Cache / Solid Queue)
  - Rails 8 defaults heavily optimized for SQLite in production
- **Mock Data**: Built-in mock registry adapters

### Testing

- **Backend/Integration**: RSpec
- **E2E Testing**: Playwright (or System Tests with Capybara/Cuprite)
- **Performance**: K6

### Deployment

- **Tool**: Kamal (formerly MRSK) or Docker Compose
- **Containerization**: optimized Dockerfile for Rails 8

## Development Commands

```bash
# Setup
bundle install
bin/rails db:prepare

# Development (Run server + CSS/JS watchers)
bin/dev

# Console
bin/rails console

# Testing
bundle exec rspec

# E2E Testing
npx playwright test

# Deploy (Simulated locally)
docker-compose up --build
```

## Project Structure

```ini
repovista/
├── app/
│   ├── assets/              # Images, stylesheets, builds
│   ├── controllers/         # Request handling logic
│   │   ├── api/             # Optional API namespace if needed
│   │   └── concern/
│   ├── javascript/          # JS entrypoints & Stimulus controllers
│   │   └── controllers/
│   │       ├── application.js
│   │       └── repository_controller.js
│   ├── models/              # Business logic & data access
│   │   ├── registry_client.rb
│   │   └── repository.rb    # Non-ActiveRecord model if using API only
│   ├── views/               # HTML Templates (ERB)
│   │   ├── layouts/
│   │   ├── repositories/
│   │   └── tags/
│   └── jobs/                # Background jobs
├── config/                  # Routes, database, environment config
│   └── routes.rb
├── db/                      # Database schema & migrations
├── spec/                    # RSpec Tests
│   ├── models/
│   ├── requests/
│   └── system/
├── Dockerfile               # Production image config
├── Gemfile                  # Ruby dependencies
└── package.json             # Node dependencies (if using heavy JS tooling)
```

## Key Implementation Notes

### Architecture

- **Service Objects**: Encapsulate Docker Registry V2 API logic in `app/services/docker_registry_service.rb`.
- **Caching**: Use Rails.cache (Solid Cache) to store registry responses and prevent rate limiting.
- **ViewComponents** (Optional): Consider using ViewComponent for complex UI elements like Repository Cards to keep views clean.

### Docker Registry Integration

- Use `Faraday` or `HTTP` gem for API communication.
- Implement a generic Adapter pattern to switch between Real Registry and Mock Registry easily based on `Example::Application.config.use_mock_registry`.

### UI/UX Requirements

- **Hotwire Navigation**: Ensure `<turbo-frame>` is used for things like pagination and tab switching (e.g., viewing Tags of a Repository) to avoid full page reloads.
- **Stimulus Controllers**:
  - `clipboard_controller.js`: For "Copy Pull Command" buttons.
  - `theme_controller.js`: For Dark/Light mode toggling.
  - `search_controller.js`: Debounced search input submission.

## Core Features to Implement

1. **Repository Listing** (`RepositoriesController#index`)
   - Grid layout of repositories.
   - Server-side filtering and pagination.

2. **Tag Details** (`RepositoriesController#show`)
   - Expandable view or separate page showing tags.
   - Tag metadata (size, digest, created_at).

3. **Search & Filter**
   - Turbo Streams to update the repository list in real-time as the user types (or debounced).

## Development Guidelines

### Code Style

- **Ruby**: Standard (rubocop).
- **JS**: Prettier / StandardJS.
- **CSS**: Tailwind classes or BEM if custom CSS.

### Security Considerations

- Use Rails encapsulated credentials (`rails credentials:edit`) for storing Registry passwords if not using ENV variables.
- Content Security Policy (CSP) configuration.

### Performance

- **Fragment Caching**: Cache HTML fragments for Repository Cards.
- **Eager Loading**: Not applicable for API calls, but ensure parallel requests if possible or background loading for heavy data.

## Environment Configuration

```bash
# .env (or credentials)
REGISTRY_URL=https://registry.example.com
REGISTRY_USERNAME=readonly_user
REGISTRY_PASSWORD=secure_password
RAILS_ENV=development
```

## Using git

- Use English to write a git commit message

## IMPORTANT
- **Orchestrator** owns global truth + integration. Add gates, verify end-to-end, and never assume infrastructure exists without proof

