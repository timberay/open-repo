# RepoVista

A modern Docker Registry Web UI service built with Ruby on Rails 8 that provides developers with an intuitive interface to browse and select Docker images for deployment.

## Features

- 🐳 **Docker Registry Integration**: Browse repositories and tags from Docker Registry V2 API
- 🔍 **Smart Search**: Real-time search with debouncing (300ms)
- 🎨 **Modern UI**: Responsive design with TailwindCSS and dark mode support
- ⚡ **Hotwire Navigation**: SPA-like experience with Turbo Frames
- 📋 **Copy to Clipboard**: One-click copy of docker pull commands
- 🎭 **Mock Mode**: Built-in mock registry for development and testing
- 🧪 **Comprehensive Tests**: RSpec for backend, Playwright for E2E

## Technology Stack

### Backend & Frontend
- **Framework**: Ruby on Rails 8
- **Language**: Ruby 3.x
- **Frontend**: Hotwire (Turbo + Stimulus)
- **Styling**: TailwindCSS
- **Database/Cache**: SQLite (Solid Cache)

### Testing
- **Backend/Integration**: RSpec
- **E2E Testing**: Playwright

## Prerequisites

- Ruby 3.x
- Node.js 18+ and npm
- SQLite3

## Installation

```bash
bundle install
npm install
bin/rails db:prepare
```

## Configuration

Set environment variables (or use `.env` file):

```bash
REGISTRY_URL=https://registry.hub.docker.com
REGISTRY_USERNAME=your_username
REGISTRY_PASSWORD=your_password
USE_MOCK_REGISTRY=true  # Set to false for production
```

## Development

```bash
bin/dev
```

This starts:
- Rails server on http://localhost:3000
- TailwindCSS watcher for live CSS updates

### Troubleshooting

**If you see "A server is already running" error:**

```bash
# Option 1: Use the cleanup script
bin/server-cleanup

# Option 2: Manual cleanup
kill -9 $(cat tmp/pids/server.pid) && rm -f tmp/pids/server.pid
```

Then try `bin/dev` again.

## Testing

### RSpec Tests
```bash
bundle exec rspec
```

### Playwright E2E Tests
```bash
npx playwright test
npx playwright test --ui  # Interactive mode
```

### Run All Tests
```bash
bundle exec rspec && npx playwright test
```

## Usage

### Browse Repositories
1. Navigate to http://localhost:3000
2. View all available Docker repositories in a grid layout
3. Use the search box to filter repositories
4. Sort repositories by name (A-Z or Z-A)

### View Tag Details
1. Click on any repository card
2. View all available tags with metadata:
   - Tag name
   - Digest (short SHA)
   - Size (human-readable)
   - Created date
3. Click "Copy" button to copy the docker pull command

### Dark Mode
- Click the moon/sun icon in the navigation bar
- Preference is saved to localStorage

## Project Structure

```
repo-vista/
├── app/
│   ├── controllers/
│   │   ├── repositories_controller.rb
│   │   └── concerns/
│   │       └── registry_error_handler.rb
│   ├── models/
│   │   ├── repository.rb
│   │   └── tag.rb
│   ├── services/
│   │   ├── docker_registry_service.rb
│   │   └── mock_registry_service.rb
│   ├── views/
│   │   ├── layouts/
│   │   │   └── application.html.erb
│   │   └── repositories/
│   │       ├── index.html.erb
│   │       ├── show.html.erb
│   │       ├── _repository_card.html.erb
│   │       ├── _tag_row.html.erb
│   │       ├── _skeleton_card.html.erb
│   │       └── _skeleton_row.html.erb
│   ├── javascript/controllers/
│   │   ├── theme_controller.js
│   │   ├── search_controller.js
│   │   └── clipboard_controller.js
│   └── assets/stylesheets/
│       └── application.tailwind.css
├── config/
│   ├── routes.rb
│   └── initializers/
│       └── docker_registry.rb
├── spec/
│   ├── services/
│   ├── models/
│   └── requests/
└── e2e/
    ├── repository-list.spec.ts
    ├── search.spec.ts
    ├── tag-details.spec.ts
    └── dark-mode.spec.ts
```

## Architecture

### Service Objects
- **DockerRegistryService**: Handles Docker Registry V2 API communication with Faraday
- **MockRegistryService**: Provides mock data for development/testing

### Models (Non-ActiveRecord)
- **Repository**: Represents a Docker repository
- **Tag**: Represents a Docker image tag with metadata

### Stimulus Controllers
- **theme_controller**: Dark/light mode toggle with localStorage persistence
- **search_controller**: Debounced search input (300ms delay)
- **clipboard_controller**: Copy to clipboard with visual feedback

## Code Quality

### Run RuboCop
```bash
bundle exec rubocop
bundle exec rubocop -a  # Auto-correct
```

### Run TypeScript Checks
```bash
npx tsc --noEmit
```

## Deployment

Using Kamal (recommended for Rails 8):

```bash
kamal setup
kamal deploy
```

Or using Docker Compose:

```bash
docker-compose up --build
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License.

## Support

For issues and questions, please open an issue on GitHub.
