# Product Requirements Document (PRD)

## 1. Introduction

**RepoVista** is a lightweight, read-only web interface for Docker Registry (V2 compatible). It allows developers and operators to browse, search, and inspect Docker images stored in a private or public registry without needing command-line tools.

### 1.1 Goals
- Provide a user-friendly UI for viewing Docker images.
- Support any Docker Registry V2 API compliant registry.
- Ensure zero-risk operation (Read-Only access).
- Performance optimized for large registries.

## 2. Functional Requirements

### 2.1 Connection Management
- **Configuration**: Connect via Environment Variables (`REGISTRY_URL`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`).
- **Validation**: System must fail gracefully if the registry is unreachable or credentials are invalid.

### 2.2 Repository Listing (Home Page)
- **Catalog View**: Display a grid or list of all available repositories (`v2/_catalog`).
- **Search**: Real-time or debounced search by repository name.
- **Pagination**: Handle large catalogs (Registry API limit defaults to 100).
- **Sorting**: Alphabetical sort (A-Z, Z-A).

### 2.3 Tag Details (Repository Page)
- **Tag List**: Show all tags for a selected repository (`v2/<name>/tags/list`).
- **Tag Metadata**:
  - **Name**: (e.g., `latest`, `v1.0.0`)
  - **Digest**: First 12 chars of SHA256 hash.
  - **Size**: Compressed size (sum of layers) *if available via efficient manifest check*.
  - **Created Date**: Timestamp from config/manifest.
- **Pull Command**: One-click copy button for `docker pull <host>/<repo>:<tag>`.

### 2.4 Navigation & UX
- **Responsive Design**: Mobile-friendly layout.
- **Dark Mode**: Support system preference or manual toggle.
- **Loading States**: Visual feedback (skeletons/spinners) while fetching data from remote registry.

## 3. Technical Specifications

### 3.1 Architecture
- **Backend**: Ruby on Rails 8 (Monolith).
- **Communication**: Server-side proxy to Registry API (protects credentials).
- **Frontend**: Hotwire (Turbo Drive + Turbo Frames) for SPA-feel.
- **Database/Cache**: SQLite + Solid Cache. *Strictly for caching API responses, not permanent storage of repo data.*

### 3.2 Security
- **Read-Only**: No `DELETE` or `PUT` capabilities exposed in the UI.
- **Credentials**: Stored in ENV or Rails Encrypted Credentials; never leaked to client.
- **Network**: Backend acts as a gateway; Browser never talks to Registry directly.

### 3.3 Performance requirements
- **Caching Strategy**: 
  - Catalog list cached for ~5 minutes.
  - Tag lists cached for ~5 minutes.
  - Manifests (immutable by digest) cached for longer durations (e.g., 24h).
- **Lazy Loading**: Fetch tags only when the user expands a repo or visits the detail page.

## 4. Workflows

### User Scenario: Finding an Image
1. User visits Homepage.
2. Sees a list of Repositories.
3. Types "backend" in search bar -> List filters instantly.
4. Clicks "my-project/backend".
5. Redirected to Repository Detail page.
6. Sees list of tags (`v2.1`, `v2.0`, `latest`).
7. Clicks "Copy" icon next to `v2.1`.
8. Pastes `docker pull registry.com/my-project/backend:v2.1` in terminal.

## 5. Development Constraints
- **Start Command**: `bin/dev`.
- **Testing**: RSpec for backend services, Playwright for E2E.
- **Deployment**: Docker container (via Kamal or Docker Compose).
