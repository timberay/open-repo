# Open Repo

A self-hosted Docker Registry V2 server with web UI, built with Ruby on Rails 8. Push and pull Docker images directly, manage repositories and tags through an intuitive browser interface.

## Features

- **Self-Hosted Docker Registry V2**: Full `docker push`/`docker pull` support
- **Web UI Management**: Browse, search, delete repositories and tags
- **Image Import/Export**: Upload/download Docker images as tar files via web UI
- **Pull Tracking**: Usage analytics with pull counts and history
- **Tag Audit Log**: Track tag changes over time
- **Dark Mode**: Responsive design with TailwindCSS and dark mode support
- **Hotwire Navigation**: SPA-like experience with Turbo Frames

## Technology Stack

### Backend & Frontend
- **Framework**: Ruby on Rails 8
- **Language**: Ruby 3.x
- **Frontend**: Hotwire (Turbo + Stimulus)
- **Styling**: TailwindCSS
- **Database/Cache**: SQLite (Solid Cache)
- **Background Jobs**: Solid Queue

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
STORAGE_PATH=/var/data/registry          # Blob storage path (default: storage/registry)
REGISTRY_HOST=registry.mycompany.com:5000  # Host shown in docker pull commands
SENDFILE_HEADER=                         # Production: 'X-Accel-Redirect' (Nginx)
```

## Development

```bash
bin/dev
```

This starts:
- Rails server on http://localhost:3000
- TailwindCSS watcher for live CSS updates

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

### Docker CLI Integration Test
```bash
test/integration/docker_cli_test.sh
```

## Usage

### Push Images
```bash
docker build -t localhost:3000/myimage:v1.0.0 .
docker push localhost:3000/myimage:v1.0.0
```

### Pull Images
```bash
docker pull localhost:3000/myimage:v1.0.0
```

### Browse via Web UI
1. Navigate to http://localhost:3000
2. View all repositories with tag counts and sizes
3. Click a repository to see tags, manifests, and image config
4. Edit repository description and maintainer

### Dark Mode
- Click the moon/sun icon in the navigation bar
- Preference is saved to localStorage

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

## License

This project is licensed under the MIT License.
