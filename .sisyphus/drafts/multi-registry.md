# Draft: Multi-Registry Server Management Feature

## User Request Summary
Add multi-registry server management to RepoVista with:
- Database-backed registry storage (SQLite)
- Navbar dropdown for registry selection
- CRUD operations for registry management
- Connection testing before save
- Default registry designation
- Local registry auto-detection
- Session-based registry switching

## User Decisions (ALL CONFIRMED)

| Question | User Answer |
|----------|-------------|
| Local Registry Auto-Detection | **앱 시작 시 자동 스캔** (localhost:5000-5010) |
| Connection Test UX | **인라인 상태 표시** (초록/빨강 아이콘 + 메시지) |
| Registry Management UI | **모달 다이얼로그** (Turbo Frame) |
| ENV Config Handling | **둘 다 표시** ([ENV] 레지스트리, 읽기 전용) |
| Dropdown Info Level | **이름 + URL + 연결 상태** (●/○ 아이콘) |
| Test Strategy | **TBD** (사용자 미지정, 기본 TDD 권장) |

## Current Architecture (Confirmed from Explore Agent)

### Registry Implementation
- Single registry config via ENV in `config/initializers/docker_registry.rb`
- `DockerRegistryService` accepts `url`, `username`, `password` in constructor
- `MockRegistryService` for development/testing
- `RepositoriesController#initialize_registry_service` switches based on `config.use_mock_registry`
- **Faraday** HTTP client with retry logic (max: 3, interval: 0.5s)
- **Caching**: 5 minutes TTL via `Rails.cache`

### UI/Frontend
- Navigation bar in `app/views/layouts/application.html.erb`
- Dark mode toggle using `theme_controller.js` (Stimulus)
- Search with debounce using `search_controller.js`
- Clipboard with `clipboard_controller.js`
- TailwindCSS for styling
- **Turbo Frames**: `turbo_frame_tag(:repositories)` for partial updates

### Models
- **Non-ActiveRecord**: `Repository`, `Tag` use ActiveModel::Model + Attributes
- Factory method pattern: `from_catalog`, `from_manifest`
- First ActiveRecord model will be `Registry`

### Database
- No existing migrations (no db/schema.rb yet)
- SQLite with Solid Cache/Queue
- ActiveRecord available via `ApplicationRecord`

### Error Handling
- `RegistryErrorHandler` concern with `rescue_from`
- Custom errors: `RegistryError`, `AuthenticationError`, `NotFoundError`

### Testing
- RSpec configured with WebMock
- Playwright E2E tests in `e2e/` directory
- No FactoryBot (using fixtures path)

## Technical Design (Final)

### 1. Registry Model Schema
```ruby
# Table: registries
- id: bigint (primary key)
- name: string (required, display name)
- url: string (required, registry URL)
- username: string (optional, for auth)
- password: string (encrypted via Rails 8 encrypts)
- is_default: boolean (default: false)
- is_active: boolean (default: true)
- last_connected_at: datetime (null OK)
- created_at/updated_at: datetime
```

### 2. Password Encryption
- Use Rails 8 `encrypts :password` with ActiveRecord Encryption
- Requires encryption keys in credentials or ENV
- Deterministic: false (for security)

### 3. Session Management
- Store `current_registry_id` in session
- Helper method `current_registry` in ApplicationController
- Fall back order:
  1. Session registry_id
  2. Default registry (is_default: true)
  3. ENV-based config (backward compatibility)

### 4. ENV Registry as Virtual Object
```ruby
class EnvRegistry
  # Read-only wrapper for ENV config
  # Appears in dropdown as "[ENV] {name}"
  # Cannot be edited or deleted
end
```

### 5. Local Registry Auto-Detection
- On Rails boot: scan localhost:5000-5010
- Use RegistryDiscoveryService
- Found registries suggested (not auto-added)
- Displayed in modal with "Add" button

## Scope Boundaries

### INCLUDE
- Registry ActiveRecord model with encryption
- RegistriesController with CRUD + switch + test_connection
- Navbar dropdown with Stimulus controller
- Registry management modal (Turbo Frame)
- Session-based registry switching
- Connection tester service
- Local registry auto-discovery service
- EnvRegistry virtual object for backward compatibility
- RSpec model/controller/request specs
- Playwright E2E tests

### EXCLUDE
- User authentication/authorization
- Multiple simultaneous active registries
- Registry health monitoring/alerts
- Import/export registry configs
- Cloud registry auto-detection (AWS ECR, GCR, etc.)

## Research Findings

### From Explore Agent (Codebase Analysis)
- Adapter pattern: `DockerRegistryService` / `MockRegistryService` share interface
- Factory pattern: `from_catalog`, `from_manifest` class methods
- Concern pattern: `RegistryErrorHandler` for reusable error handling
- Before action: `initialize_registry_service` for service DI

### Pending Research
- Rails 8 encrypts best practices
- Stimulus dropdown/modal patterns
- Turbo Frame modal implementation
