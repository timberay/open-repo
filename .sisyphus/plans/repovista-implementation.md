# RepoVista 전체 구현 계획

## TL;DR

> **Quick Summary**: Docker Registry V2 Web UI (Rails 8 + Hotwire + TailwindCSS) 전체 구현. Mock 서비스로 개발 시작, Repository 목록/상세 페이지, 실시간 검색, 다크 모드, Copy 버튼 포함.
> 
> **Deliverables**:
> - Docker Registry V2 API 클라이언트 (Faraday 기반)
> - Mock Registry 서비스 (개발/테스트용)
> - Repository 목록 페이지 (검색, 페이지네이션, 정렬)
> - Tag 상세 페이지 (메타데이터, Copy Pull Command)
> - Stimulus 컨트롤러 (검색, 클립보드, 다크 모드)
> - RSpec 테스트 (서비스, 컨트롤러)
> - Playwright E2E 테스트 (핵심 플로우)
> 
> **Estimated Effort**: Large (15-20 tasks)
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Task 1 → Task 5 → Task 8 → Task 13

---

## Context

### Original Request
RepoVista - Docker Registry V2를 위한 읽기 전용 웹 UI를 Rails 8 + Hotwire로 구축. PRD의 모든 요구사항을 100% 충족하는 프로덕션 레디 애플리케이션.

### Interview Summary
**Key Discussions**:
- 테스트 전략: Tests-after (RSpec). 기능 구현 후 테스트 작성.
- E2E: Playwright 포함 (핵심 플로우만)
- HTTP 클라이언트: Faraday (retry, timeout 미들웨어)
- 개발 방식: Mock 우선 개발 (USE_MOCK_REGISTRY 환경변수)
- 병렬 작업: 백엔드/프론트엔드 동시 진행

**Research Findings**:
- Rails 8.1.2 + Ruby 3.4.8 완전 구성됨
- Hotwire (Turbo + Stimulus), TailwindCSS 설치됨
- RSpec 설정됨 (rails_helper, spec_helper)
- Faraday 미설치 → Gemfile에 추가 필요
- Playwright 미설치 → 설정 필요

### Gap Analysis (Self-Review)

**Identified Gaps** (addressed in plan):
1. Faraday gem 미설치 → Task 1에서 추가
2. Playwright 미설치 → Task 2에서 설정
3. TailwindCSS darkMode 설정 필요 → Task 3에서 처리
4. 에러 처리 믹스인 필요 → Task 5에 포함
5. 캐시 TTL 설정 필요 → Task 5에 포함

---

## Work Objectives

### Core Objective
Docker Registry V2 API와 통신하여 리포지토리 목록과 태그 정보를 제공하는 읽기 전용 웹 UI 구축. Mock 서비스로 개발하고 환경변수로 실제 Registry로 전환 가능.

### Concrete Deliverables
- `app/services/docker_registry_service.rb` - 핵심 API 클라이언트
- `app/services/mock_registry_service.rb` - Mock 구현
- `app/controllers/repositories_controller.rb` - index, show 액션
- `app/views/repositories/` - 목록, 상세 뷰
- `app/javascript/controllers/` - search, clipboard, theme 컨트롤러
- `spec/` - RSpec 테스트
- `e2e/` - Playwright E2E 테스트

### Definition of Done
- [ ] `bin/dev` 실행 시 애플리케이션 정상 시작
- [ ] `http://localhost:3000` 접속 시 Repository 목록 표시
- [ ] 검색 입력 시 실시간 필터링
- [ ] Repository 클릭 시 Tag 목록 표시
- [ ] Copy 버튼 클릭 시 클립보드에 docker pull 명령 복사
- [ ] 다크/라이트 모드 토글 동작
- [ ] `bundle exec rspec` 모든 테스트 통과
- [ ] `npx playwright test` E2E 테스트 통과

### Must Have
- Repository 목록 (Grid, 반응형)
- 실시간 검색 (디바운스)
- 페이지네이션
- 정렬 (A-Z, Z-A)
- Tag 상세 (Name, Digest 12자, Size, Created)
- Copy Pull Command 버튼
- 다크 모드
- Skeleton UI (로딩)
- Mock 서비스 (개발용)
- RSpec 테스트
- Playwright E2E

### Must NOT Have (Guardrails)
- DELETE/PUT 기능 (읽기 전용)
- 사용자 인증/관리 기능
- 다중 레지스트리 지원 (단일 Registry만)
- 이미지 푸시 기능
- 복잡한 RBAC/권한 시스템
- WebSocket 실시간 업데이트 (Turbo Streams 브로드캐스트 제외)
- 과도한 추상화 (심플한 서비스 객체)
- AI 슬롭: 불필요한 주석, 과도한 에러 체크, premature abstraction

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (RSpec 설정됨)
- **User wants tests**: Tests-after
- **Framework**: RSpec (서비스/컨트롤러), Playwright (E2E)

### Automated Verification Only (NO User Intervention)

모든 검증은 에이전트가 자동으로 실행 가능해야 함:

| Type | Verification Tool | Automated Procedure |
|------|------------------|---------------------|
| **Frontend/UI** | Playwright via playwright skill | 네비게이션, 클릭, 스크린샷, DOM 검증 |
| **API/Backend** | RSpec request specs | 요청/응답 검증 |
| **Services** | RSpec unit specs | 서비스 메서드 검증 |
| **Full Flow** | Playwright E2E | 전체 사용자 플로우 검증 |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately - 기반 설정):
├── Task 1: Gemfile 및 의존성 설정 (Faraday 추가)
├── Task 2: Playwright 설정
├── Task 3: TailwindCSS Dark Mode 설정
└── Task 4: 기본 레이아웃 업데이트 (네비게이션, 다크모드 토글)

Wave 2 (After Wave 1 - 핵심 서비스):
├── Task 5: DockerRegistryService 구현 (실제 API 클라이언트)
├── Task 6: MockRegistryService 구현
├── Task 7: Repository/Tag 모델 (Non-ActiveRecord)
└── Task 8: Routes 및 RepositoriesController 기본 구조

Wave 3 (After Wave 2 - 뷰 및 인터랙션):
├── Task 9: Repository 목록 뷰 (index.html.erb + _repository_card.html.erb)
├── Task 10: Tag 상세 뷰 (show.html.erb + _tag_row.html.erb)
├── Task 11: Stimulus 컨트롤러 (search, clipboard, theme)
└── Task 12: Skeleton UI 및 로딩 상태

Wave 4 (After Wave 3 - 테스트 및 완성):
├── Task 13: RSpec 테스트 (서비스, 컨트롤러)
├── Task 14: Playwright E2E 테스트
└── Task 15: 최종 통합 및 문서화
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 5, 6 | 2, 3, 4 |
| 2 | None | 14 | 1, 3, 4 |
| 3 | None | 4, 11 | 1, 2, 4 |
| 4 | 3 | 9, 10 | None (depends on 3) |
| 5 | 1 | 8, 13 | 6, 7 |
| 6 | 1 | 8, 13 | 5, 7 |
| 7 | None | 5, 6, 8 | 5, 6 (can start early) |
| 8 | 5, 6, 7 | 9, 10 | None (integration) |
| 9 | 4, 8 | 13, 14 | 10, 11, 12 |
| 10 | 4, 8 | 13, 14 | 9, 11, 12 |
| 11 | 3 | 14 | 9, 10, 12 |
| 12 | 4 | 14 | 9, 10, 11 |
| 13 | 5, 6, 8, 9, 10 | 15 | 14 |
| 14 | 2, 9, 10, 11, 12 | 15 | 13 |
| 15 | 13, 14 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Approach |
|------|-------|---------------------|
| 1 | 1, 2, 3, 4 | 4개 태스크 병렬 실행. 단, Task 4는 Task 3 완료 후. |
| 2 | 5, 6, 7, 8 | 5, 6, 7 병렬 실행. Task 8은 5, 6, 7 완료 후. |
| 3 | 9, 10, 11, 12 | 모두 병렬 실행 가능 (8 완료 후) |
| 4 | 13, 14, 15 | 13, 14 병렬. 15는 마지막. |

---

## TODOs

### Wave 1: 기반 설정

- [ ] 1. Gemfile 및 의존성 설정

  **What to do**:
  - Gemfile에 gem 추가:
    - `faraday` - HTTP 클라이언트
    - `faraday-retry` - retry 미들웨어
    - `webmock` (test group) - HTTP 요청 모킹
  - `bundle install` 실행
  - Docker Registry 초기화 파일 생성 (`config/initializers/docker_registry.rb`)
  - 환경변수 설정 문서화

  **Must NOT do**:
  - 불필요한 gem 추가
  - 복잡한 초기화 로직

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 간단한 파일 수정 및 명령 실행
  - **Skills**: [`git-master`]
    - `git-master`: 변경 후 커밋 필요

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4)
  - **Blocks**: [5, 6]
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `Gemfile:28-31` - 기존 gem 추가 패턴 (solid_cache, solid_queue 참고)
  - `config/initializers/assets.rb` - 초기화 파일 패턴

  **Configuration References**:
  - `config/environments/development.rb:29` - cache_store 설정 위치

  **Documentation References**:
  - `AGENTS.md:Environment Configuration` - 환경변수 설정 가이드
  - `docs/PRD.md:Connection Management` - Registry 연결 요구사항

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  grep -q "faraday" Gemfile && echo "SUCCESS: faraday in Gemfile"
  # Assert: Output contains "SUCCESS"
  
  grep -q "faraday-retry" Gemfile && echo "SUCCESS: faraday-retry in Gemfile"
  # Assert: Output contains "SUCCESS"
  
  grep -q "webmock" Gemfile && echo "SUCCESS: webmock in Gemfile"
  # Assert: Output contains "SUCCESS"
  
  bundle check
  # Assert: Exit code 0, "The Gemfile's dependencies are satisfied"
  
  test -f config/initializers/docker_registry.rb && echo "SUCCESS: initializer exists"
  # Assert: Output contains "SUCCESS"
  ```

  **Commit**: YES
  - Message: `chore: add Faraday, WebMock gems and Docker Registry initializer`
  - Files: `Gemfile`, `Gemfile.lock`, `config/initializers/docker_registry.rb`
  - Pre-commit: `bundle check`

---

- [ ] 2. Playwright 설정

  **What to do**:
  - `npm init -y` (package.json 없으면 생성)
  - `npm init playwright@latest` 또는 수동 설정
  - `playwright.config.ts` 생성 (baseURL: localhost:3000)
  - `e2e/` 디렉토리 구조 생성
  - 예제 테스트 파일 생성 (`e2e/example.spec.ts`)
  - package.json scripts 추가 (test:e2e)

  **Must NOT do**:
  - 복잡한 테스트 유틸리티 추가
  - 불필요한 브라우저 설정

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 설정 파일 생성 및 npm 명령
  - **Skills**: [`playwright`]
    - `playwright`: Playwright 설정 및 사용법

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4)
  - **Blocks**: [14]
  - **Blocked By**: None

  **References**:

  **Configuration References**:
  - `package.json` (없으면 생성) - npm scripts 위치

  **External References**:
  - Playwright 공식 문서: https://playwright.dev/docs/intro

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  test -f playwright.config.ts && echo "SUCCESS: playwright config exists"
  # Assert: Output contains "SUCCESS"
  
  test -d e2e && echo "SUCCESS: e2e directory exists"
  # Assert: Output contains "SUCCESS"
  
  npx playwright --version
  # Assert: Exit code 0, shows version number
  ```

  **Commit**: YES
  - Message: `chore: set up Playwright for E2E testing`
  - Files: `playwright.config.ts`, `e2e/`, `package.json`, `package-lock.json`
  - Pre-commit: `npx playwright --version`

---

- [ ] 3. TailwindCSS Dark Mode 설정

  **What to do**:
  - `tailwind.config.js` 생성 (darkMode: 'class')
  - `app/assets/tailwind/application.css` 업데이트 (다크 모드 기본 스타일)
  - CSS 변수 정의 (--bg-primary, --text-primary 등)

  **Must NOT do**:
  - 과도하게 복잡한 테마 시스템
  - 불필요한 CSS 커스터마이징

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: 스타일 관련 작업
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: TailwindCSS 및 다크 모드 설정

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: [4, 11]
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `app/assets/tailwind/application.css:1` - 현재 TailwindCSS 엔트리포인트

  **External References**:
  - TailwindCSS Dark Mode: https://tailwindcss.com/docs/dark-mode

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  test -f tailwind.config.js && echo "SUCCESS: tailwind config exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "darkMode" tailwind.config.js && echo "SUCCESS: darkMode configured"
  # Assert: Output contains "SUCCESS"
  ```

  **Commit**: YES
  - Message: `feat: configure TailwindCSS dark mode`
  - Files: `tailwind.config.js`, `app/assets/tailwind/application.css`
  - Pre-commit: `bin/rails tailwindcss:build`

---

- [ ] 4. 기본 레이아웃 업데이트

  **What to do**:
  - `app/views/layouts/application.html.erb` 업데이트
    - `<html>` 태그에 다크 모드 클래스 바인딩
    - 네비게이션 바 추가 (로고, 다크 모드 토글)
    - 반응형 컨테이너 구조
    - Stimulus data-controller 연결
  - 기본 CSS 클래스 정의 (bg-gray-100 dark:bg-gray-900 등)

  **Must NOT do**:
  - 복잡한 네비게이션 메뉴
  - 불필요한 UI 요소

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI 레이아웃 작업
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: 레이아웃 및 반응형 디자인

  **Parallelization**:
  - **Can Run In Parallel**: NO (Task 3 완료 필요)
  - **Parallel Group**: Wave 1 (after Task 3)
  - **Blocks**: [9, 10]
  - **Blocked By**: [3]

  **References**:

  **Pattern References**:
  - `app/views/layouts/application.html.erb:1-32` - 현재 레이아웃 구조

  **External References**:
  - TailwindCSS Layout: https://tailwindcss.com/docs/container

  **Acceptance Criteria**:

  **Playwright로 검증:**
  ```
  # Agent executes via playwright browser automation:
  1. Navigate to: http://localhost:3000
  2. Assert: <html> tag has data-theme attribute or class binding
  3. Assert: Navigation bar is visible
  4. Assert: Dark mode toggle button exists
  5. Screenshot: .sisyphus/evidence/task-4-layout.png
  ```

  **Commit**: YES
  - Message: `feat: update layout with navigation and dark mode support`
  - Files: `app/views/layouts/application.html.erb`
  - Pre-commit: `bin/rails tailwindcss:build`

---

### Wave 2: 핵심 서비스

- [ ] 5. DockerRegistryService 구현

  **What to do**:
  - `app/services/docker_registry_service.rb` 생성
  - Faraday 클라이언트 설정 (retry, timeout 미들웨어)
  - API 메서드 구현:
    - `#catalog` - `/v2/_catalog` 호출
    - `#tags(repository)` - `/v2/<name>/tags/list` 호출
    - `#manifest(repository, tag)` - `/v2/<name>/manifests/<tag>` 호출
  - Basic Auth 지원
  - 에러 처리 (401, 403, 404, 500, timeout)
  - 캐싱 (Rails.cache, TTL 5분)
  - Link 헤더 파싱 (페이지네이션)

  **Must NOT do**:
  - DELETE/PUT 메서드
  - Bearer Token 인증 (Basic Auth만)
  - 과도한 추상화

  **Recommended Agent Profile**:
  - **Category**: `ultrabrain`
    - Reason: API 클라이언트 구현, 에러 처리, 캐싱 로직
  - **Skills**: []
    - 스킬 불필요 (순수 Ruby 코드)

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 7)
  - **Blocks**: [8, 13]
  - **Blocked By**: [1]

  **References**:

  **API/Type References**:
  - Docker Registry V2 API: https://docs.docker.com/registry/spec/api/

  **Pattern References**:
  - `config/initializers/docker_registry.rb` (Task 1에서 생성) - 설정 로드

  **Documentation References**:
  - `docs/PRD.md:Technical Specifications` - API 요구사항
  - `AGENTS.md:Docker Registry Integration` - 구현 가이드

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  test -f app/services/docker_registry_service.rb && echo "SUCCESS: service exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "def catalog" app/services/docker_registry_service.rb && echo "SUCCESS: catalog method exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "def tags" app/services/docker_registry_service.rb && echo "SUCCESS: tags method exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "Rails.cache" app/services/docker_registry_service.rb && echo "SUCCESS: caching implemented"
  # Assert: Output contains "SUCCESS"
  ```

  **Commit**: YES
  - Message: `feat: implement DockerRegistryService with Faraday client`
  - Files: `app/services/docker_registry_service.rb`
  - Pre-commit: `bundle exec rubocop app/services/docker_registry_service.rb --autocorrect`

---

- [ ] 6. MockRegistryService 구현

  **What to do**:
  - `app/services/mock_registry_service.rb` 생성
  - DockerRegistryService와 동일한 인터페이스
  - 하드코딩된 샘플 데이터:
    - 10-15개 리포지토리 (다양한 이름)
    - 각 리포지토리에 3-5개 태그
    - 현실적인 메타데이터 (digest, size, created_at)
  - 페이지네이션 시뮬레이션
  - 지연 시뮬레이션 (선택적, 0.1-0.5초)

  **Must NOT do**:
  - 외부 API 호출
  - 복잡한 데이터 생성 로직

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 간단한 Mock 데이터 서비스
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 7)
  - **Blocks**: [8, 13]
  - **Blocked By**: [1]

  **References**:

  **Pattern References**:
  - `app/services/docker_registry_service.rb` (Task 5) - 인터페이스 참고

  **Documentation References**:
  - `AGENTS.md:Mock Data` - Mock 어댑터 가이드

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  test -f app/services/mock_registry_service.rb && echo "SUCCESS: mock service exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "def catalog" app/services/mock_registry_service.rb && echo "SUCCESS: catalog method exists"
  # Assert: Output contains "SUCCESS"
  
  # Verify mock data exists
  grep -q "repositories" app/services/mock_registry_service.rb && echo "SUCCESS: mock data defined"
  # Assert: Output contains "SUCCESS"
  ```

  **Commit**: YES
  - Message: `feat: implement MockRegistryService for development`
  - Files: `app/services/mock_registry_service.rb`
  - Pre-commit: `bundle exec rubocop app/services/mock_registry_service.rb --autocorrect`

---

- [ ] 7. Repository/Tag 모델 구현

  **What to do**:
  - `app/models/repository.rb` - Non-ActiveRecord 모델
    - Attributes: name, tag_count, last_updated
    - Class method: `from_catalog_response(data)`
  - `app/models/tag.rb` - Non-ActiveRecord 모델
    - Attributes: name, digest, size, created_at
    - Instance method: `pull_command(registry_host)`
    - Class method: `from_manifest_response(data)`
  - ActiveModel::Model 또는 Struct 활용

  **Must NOT do**:
  - ActiveRecord 상속
  - 데이터베이스 마이그레이션
  - 복잡한 관계 설정

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 간단한 PORO/Struct 모델
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: [5, 6, 8]
  - **Blocked By**: None (can start early)

  **References**:

  **Pattern References**:
  - `app/models/application_record.rb` - 모델 디렉토리 위치

  **Documentation References**:
  - `docs/PRD.md:Tag Metadata` - 태그 속성 정의

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  test -f app/models/repository.rb && echo "SUCCESS: repository model exists"
  # Assert: Output contains "SUCCESS"
  
  test -f app/models/tag.rb && echo "SUCCESS: tag model exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "pull_command" app/models/tag.rb && echo "SUCCESS: pull_command method exists"
  # Assert: Output contains "SUCCESS"
  ```

  **Commit**: YES
  - Message: `feat: implement Repository and Tag models (Non-ActiveRecord)`
  - Files: `app/models/repository.rb`, `app/models/tag.rb`
  - Pre-commit: `bundle exec rubocop app/models/ --autocorrect`

---

- [ ] 8. Routes 및 RepositoriesController

  **What to do**:
  - `config/routes.rb` 업데이트:
    - `root "repositories#index"`
    - `resources :repositories, only: [:index, :show]`
  - `app/controllers/repositories_controller.rb` 생성:
    - `#index`: 리포지토리 목록, 검색, 정렬, 페이지네이션
    - `#show`: 태그 상세
    - Turbo Frame/Stream 지원
  - `app/controllers/concerns/registry_error_handler.rb` 생성:
    - rescue_from로 에러 처리

  **Must NOT do**:
  - create, update, destroy 액션
  - 복잡한 필터 체인
  - N+1 쿼리 (API 호출이므로 해당 없음)

  **Recommended Agent Profile**:
  - **Category**: `ultrabrain`
    - Reason: 컨트롤러 로직, Turbo 통합
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (Task 5, 6, 7 완료 필요)
  - **Parallel Group**: Wave 2 (after 5, 6, 7)
  - **Blocks**: [9, 10]
  - **Blocked By**: [5, 6, 7]

  **References**:

  **Pattern References**:
  - `config/routes.rb:1-15` - 현재 라우트 구조
  - `app/controllers/application_controller.rb` - 베이스 컨트롤러

  **Documentation References**:
  - `docs/PRD.md:Workflows` - 사용자 시나리오

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  grep -q 'resources :repositories' config/routes.rb && echo "SUCCESS: routes defined"
  # Assert: Output contains "SUCCESS"
  
  test -f app/controllers/repositories_controller.rb && echo "SUCCESS: controller exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "def index" app/controllers/repositories_controller.rb && echo "SUCCESS: index action exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "def show" app/controllers/repositories_controller.rb && echo "SUCCESS: show action exists"
  # Assert: Output contains "SUCCESS"
  
  bin/rails routes | grep repositories
  # Assert: Shows repositories routes (index, show)
  ```

  **Commit**: YES
  - Message: `feat: add routes and RepositoriesController`
  - Files: `config/routes.rb`, `app/controllers/repositories_controller.rb`, `app/controllers/concerns/registry_error_handler.rb`
  - Pre-commit: `bin/rails routes`

---

### Wave 3: 뷰 및 인터랙션

- [ ] 9. Repository 목록 뷰

  **What to do**:
  - `app/views/repositories/index.html.erb` 생성:
    - 검색 입력 필드 (Stimulus data-controller)
    - 정렬 드롭다운
    - Turbo Frame으로 감싼 리포지토리 그리드
  - `app/views/repositories/_repository_card.html.erb` 생성:
    - 리포지토리 이름
    - 태그 수
    - 마지막 업데이트
    - 클릭 시 상세로 이동
  - `app/views/repositories/index.turbo_stream.erb` (검색용)
  - 반응형: 모바일 1열, 태블릿 2열, 데스크탑 3열
  - Skeleton UI 포함

  **Must NOT do**:
  - 인라인 스타일
  - 복잡한 JavaScript 로직 (Stimulus로 분리)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI 뷰 구현
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: TailwindCSS 레이아웃, 반응형 디자인

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 10, 11, 12)
  - **Blocks**: [13, 14]
  - **Blocked By**: [4, 8]

  **References**:

  **Pattern References**:
  - `app/views/layouts/application.html.erb` (Task 4) - 레이아웃 구조

  **Documentation References**:
  - `docs/PRD.md:Repository Listing` - UI 요구사항
  - `AGENTS.md:UI/UX Requirements` - Turbo Frame 사용

  **Acceptance Criteria**:

  **Playwright로 검증:**
  ```
  # Agent executes via playwright browser automation:
  1. Navigate to: http://localhost:3000
  2. Assert: Repository cards are visible (at least 3)
  3. Assert: Search input field exists
  4. Assert: Sort dropdown exists
  5. Resize viewport to mobile (375px) → Assert: Single column layout
  6. Resize viewport to desktop (1280px) → Assert: Three column layout
  7. Screenshot: .sisyphus/evidence/task-9-repository-list.png
  ```

  **Commit**: YES
  - Message: `feat: implement Repository listing view with responsive grid`
  - Files: `app/views/repositories/index.html.erb`, `app/views/repositories/_repository_card.html.erb`, `app/views/repositories/index.turbo_stream.erb`
  - Pre-commit: `bin/rails tailwindcss:build`

---

- [ ] 10. Tag 상세 뷰

  **What to do**:
  - `app/views/repositories/show.html.erb` 생성:
    - 리포지토리 헤더 (이름, back 버튼)
    - 태그 테이블/리스트
  - `app/views/repositories/_tag_row.html.erb` 생성:
    - 태그 이름
    - Digest (처음 12자)
    - Size (human readable)
    - Created date (relative time)
    - Copy Pull Command 버튼 (Stimulus)
  - Turbo Frame으로 페이지 업데이트

  **Must NOT do**:
  - 태그 수정/삭제 UI
  - 복잡한 테이블 기능 (정렬, 필터 - MVP 제외)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI 뷰 구현
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: TailwindCSS 테이블, 카드 디자인

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 11, 12)
  - **Blocks**: [13, 14]
  - **Blocked By**: [4, 8]

  **References**:

  **Pattern References**:
  - `app/views/repositories/_repository_card.html.erb` (Task 9) - partial 패턴

  **Documentation References**:
  - `docs/PRD.md:Tag Details` - 태그 메타데이터 요구사항

  **Acceptance Criteria**:

  **Playwright로 검증:**
  ```
  # Agent executes via playwright browser automation:
  1. Navigate to: http://localhost:3000
  2. Click: First repository card
  3. Assert: URL changed to /repositories/:name
  4. Assert: Tag table/list is visible
  5. Assert: Each tag row shows: name, digest, size, date
  6. Assert: Copy button exists for each tag
  7. Screenshot: .sisyphus/evidence/task-10-tag-details.png
  ```

  **Commit**: YES
  - Message: `feat: implement Tag details view with metadata`
  - Files: `app/views/repositories/show.html.erb`, `app/views/repositories/_tag_row.html.erb`
  - Pre-commit: `bin/rails tailwindcss:build`

---

- [ ] 11. Stimulus 컨트롤러 구현

  **What to do**:
  - `app/javascript/controllers/search_controller.js`:
    - 디바운스 입력 (300ms)
    - Turbo Frame 업데이트 트리거
  - `app/javascript/controllers/clipboard_controller.js`:
    - 클릭 시 텍스트 복사
    - 복사 완료 피드백 (아이콘/텍스트 변경)
  - `app/javascript/controllers/theme_controller.js`:
    - 다크/라이트 모드 토글
    - localStorage 저장
    - 시스템 설정 감지

  **Must NOT do**:
  - 복잡한 상태 관리
  - 외부 라이브러리 의존

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: 프론트엔드 인터랙션
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: Stimulus 패턴

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 12)
  - **Blocks**: [14]
  - **Blocked By**: [3]

  **References**:

  **Pattern References**:
  - `app/javascript/controllers/hello_controller.js` - Stimulus 컨트롤러 패턴
  - `app/javascript/controllers/application.js` - Stimulus 초기화
  - `config/importmap.rb:7` - 컨트롤러 자동 로드

  **Documentation References**:
  - `AGENTS.md:Stimulus Controllers` - 컨트롤러 목록

  **External References**:
  - Stimulus Handbook: https://stimulus.hotwired.dev/handbook/introduction

  **Acceptance Criteria**:

  **Playwright로 검증:**
  ```
  # Agent executes via playwright browser automation:
  
  # Search Controller
  1. Navigate to: http://localhost:3000
  2. Type in search input: "test"
  3. Wait 500ms (debounce)
  4. Assert: Repository list updated/filtered
  
  # Clipboard Controller
  5. Navigate to: http://localhost:3000/repositories/test-repo
  6. Click: Copy button on first tag
  7. Assert: Button shows "Copied!" or icon change
  
  # Theme Controller
  8. Click: Dark mode toggle
  9. Assert: <html> has "dark" class
  10. Refresh page
  11. Assert: Dark mode persists (localStorage)
  12. Screenshot: .sisyphus/evidence/task-11-stimulus.png
  ```

  **Commit**: YES
  - Message: `feat: implement Stimulus controllers (search, clipboard, theme)`
  - Files: `app/javascript/controllers/search_controller.js`, `app/javascript/controllers/clipboard_controller.js`, `app/javascript/controllers/theme_controller.js`
  - Pre-commit: None (JS files)

---

- [ ] 12. Skeleton UI 및 로딩 상태

  **What to do**:
  - `app/views/repositories/_skeleton_card.html.erb` 생성:
    - 애니메이션 플레이스홀더
    - TailwindCSS animate-pulse
  - `app/views/repositories/_skeleton_row.html.erb` 생성
  - Turbo Frame `loading="lazy"` 활용
  - 에러 상태 UI (Registry 연결 실패)

  **Must NOT do**:
  - 복잡한 애니메이션
  - JavaScript 기반 로딩 상태 (Turbo 활용)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI 컴포넌트
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: Skeleton UI 패턴

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 11)
  - **Blocks**: [14]
  - **Blocked By**: [4]

  **References**:

  **Pattern References**:
  - `app/views/repositories/_repository_card.html.erb` (Task 9) - 카드 구조 참고

  **External References**:
  - TailwindCSS Animation: https://tailwindcss.com/docs/animation

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  test -f app/views/repositories/_skeleton_card.html.erb && echo "SUCCESS: skeleton card exists"
  # Assert: Output contains "SUCCESS"
  
  grep -q "animate-pulse" app/views/repositories/_skeleton_card.html.erb && echo "SUCCESS: animation class used"
  # Assert: Output contains "SUCCESS"
  ```

  **Playwright로 검증:**
  ```
  # Agent executes via playwright browser automation:
  1. Navigate to: http://localhost:3000 (with slow network simulation)
  2. Assert: Skeleton cards visible during loading
  3. Screenshot: .sisyphus/evidence/task-12-skeleton.png
  ```

  **Commit**: YES
  - Message: `feat: implement Skeleton UI for loading states`
  - Files: `app/views/repositories/_skeleton_card.html.erb`, `app/views/repositories/_skeleton_row.html.erb`
  - Pre-commit: `bin/rails tailwindcss:build`

---

### Wave 4: 테스트 및 완성

- [ ] 13. RSpec 테스트 작성

  **What to do**:
  - `spec/services/docker_registry_service_spec.rb`:
    - API 호출 테스트 (WebMock/VCR)
    - 에러 처리 테스트
    - 캐싱 테스트
  - `spec/services/mock_registry_service_spec.rb`:
    - 인터페이스 호환성 테스트
  - `spec/models/repository_spec.rb`:
    - 모델 속성 테스트
  - `spec/models/tag_spec.rb`:
    - pull_command 테스트
  - `spec/requests/repositories_spec.rb`:
    - GET /repositories (index)
    - GET /repositories/:id (show)
    - 검색 파라미터
    - Turbo Stream 응답

  **Must NOT do**:
  - 실제 Registry 연결 테스트 (Mock 사용)
  - 과도한 테스트 커버리지 (핵심만)

  **Recommended Agent Profile**:
  - **Category**: `ultrabrain`
    - Reason: 테스트 로직 구현
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 14)
  - **Blocks**: [15]
  - **Blocked By**: [5, 6, 8, 9, 10]

  **References**:

  **Pattern References**:
  - `spec/rails_helper.rb` - RSpec 설정
  - `spec/spec_helper.rb` - 기본 설정

  **Test References**:
  - `spec/services/` (현재 비어있음) - 서비스 테스트 위치

  **External References**:
  - RSpec Rails: https://rspec.info/features/6-0/rspec-rails/

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  bundle exec rspec --dry-run
  # Assert: Exit code 0, shows test count
  
  bundle exec rspec spec/services/
  # Assert: Exit code 0, all tests pass
  
  bundle exec rspec spec/requests/
  # Assert: Exit code 0, all tests pass
  
  bundle exec rspec spec/models/
  # Assert: Exit code 0, all tests pass
  ```

  **Commit**: YES
  - Message: `test: add RSpec tests for services, models, and requests`
  - Files: `spec/services/*.rb`, `spec/models/*.rb`, `spec/requests/*.rb`
  - Pre-commit: `bundle exec rspec`

---

- [ ] 14. Playwright E2E 테스트 작성

  **What to do**:
  - `e2e/repository-list.spec.ts`:
    - 홈페이지 로드
    - 리포지토리 목록 표시
    - 반응형 레이아웃
  - `e2e/search.spec.ts`:
    - 검색 입력
    - 결과 필터링
    - 디바운스 동작
  - `e2e/tag-details.spec.ts`:
    - 리포지토리 클릭
    - 태그 목록 표시
    - Copy 버튼 동작
  - `e2e/dark-mode.spec.ts`:
    - 토글 동작
    - 저장/복원

  **Must NOT do**:
  - 모든 엣지 케이스 테스트
  - 실제 Registry 연결

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: E2E 테스트, 브라우저 자동화
  - **Skills**: [`playwright`]
    - `playwright`: Playwright 테스트 작성

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 13)
  - **Blocks**: [15]
  - **Blocked By**: [2, 9, 10, 11, 12]

  **References**:

  **Configuration References**:
  - `playwright.config.ts` (Task 2) - Playwright 설정

  **Documentation References**:
  - `docs/PRD.md:Workflows` - 사용자 시나리오

  **External References**:
  - Playwright Test: https://playwright.dev/docs/writing-tests

  **Acceptance Criteria**:

  ```bash
  # Agent runs (with dev server running):
  npx playwright test --reporter=list
  # Assert: Exit code 0, all tests pass
  
  npx playwright test e2e/repository-list.spec.ts
  # Assert: Exit code 0
  
  npx playwright test e2e/search.spec.ts
  # Assert: Exit code 0
  
  npx playwright test e2e/tag-details.spec.ts
  # Assert: Exit code 0
  ```

  **Commit**: YES
  - Message: `test: add Playwright E2E tests for core user flows`
  - Files: `e2e/*.spec.ts`
  - Pre-commit: `npx playwright test --reporter=list`

---

- [ ] 15. 최종 통합 및 문서화

  **What to do**:
  - README.md 업데이트:
    - 프로젝트 설명
    - 설치 방법
    - 환경변수 설정
    - 개발 서버 실행
    - 테스트 실행
  - 최종 검증:
    - `bin/dev` 실행 확인
    - 전체 사용자 플로우 검증
    - 모든 테스트 통과 확인
  - 코드 정리:
    - RuboCop 실행
    - 불필요한 파일 정리

  **Must NOT do**:
  - 추가 기능 구현
  - 과도한 문서화

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 문서화 및 정리
  - **Skills**: [`git-master`]
    - `git-master`: 최종 커밋

  **Parallelization**:
  - **Can Run In Parallel**: NO (마지막 태스크)
  - **Parallel Group**: Wave 4 (final)
  - **Blocks**: None
  - **Blocked By**: [13, 14]

  **References**:

  **Documentation References**:
  - `README.md` - 현재 README (기본만 존재)
  - `AGENTS.md:Development Commands` - 개발 명령어

  **Acceptance Criteria**:

  ```bash
  # Agent runs:
  
  # Full application test
  bin/rails server -d
  sleep 5
  curl -s http://localhost:3000 | grep -q "RepoVista" && echo "SUCCESS: App running"
  # Assert: Output contains "SUCCESS"
  
  # All tests pass
  bundle exec rspec
  # Assert: Exit code 0
  
  npx playwright test
  # Assert: Exit code 0
  
  # Code quality
  bundle exec rubocop --format simple
  # Assert: No offenses (or acceptable warnings only)
  
  # Cleanup
  kill $(cat tmp/pids/server.pid)
  ```

  **Commit**: YES
  - Message: `docs: update README and finalize project`
  - Files: `README.md`
  - Pre-commit: `bundle exec rspec && npx playwright test`

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `chore: add Faraday, WebMock gems and Docker Registry initializer` | Gemfile, Gemfile.lock, config/initializers/docker_registry.rb | `bundle check` |
| 2 | `chore: set up Playwright for E2E testing` | playwright.config.ts, e2e/, package.json | `npx playwright --version` |
| 3 | `feat: configure TailwindCSS dark mode` | tailwind.config.js, application.css | `bin/rails tailwindcss:build` |
| 4 | `feat: update layout with navigation and dark mode support` | application.html.erb | `bin/rails tailwindcss:build` |
| 5 | `feat: implement DockerRegistryService with Faraday client` | docker_registry_service.rb | `rubocop` |
| 6 | `feat: implement MockRegistryService for development` | mock_registry_service.rb | `rubocop` |
| 7 | `feat: implement Repository and Tag models` | repository.rb, tag.rb | `rubocop` |
| 8 | `feat: add routes and RepositoriesController` | routes.rb, repositories_controller.rb | `bin/rails routes` |
| 9 | `feat: implement Repository listing view` | index.html.erb, _repository_card.html.erb | `tailwindcss:build` |
| 10 | `feat: implement Tag details view` | show.html.erb, _tag_row.html.erb | `tailwindcss:build` |
| 11 | `feat: implement Stimulus controllers` | search_controller.js, clipboard_controller.js, theme_controller.js | None |
| 12 | `feat: implement Skeleton UI` | _skeleton_card.html.erb, _skeleton_row.html.erb | `tailwindcss:build` |
| 13 | `test: add RSpec tests` | spec/**/*.rb | `bundle exec rspec` |
| 14 | `test: add Playwright E2E tests` | e2e/*.spec.ts | `npx playwright test` |
| 15 | `docs: update README and finalize project` | README.md | `rspec && playwright` |

---

## Success Criteria

### Verification Commands

```bash
# 1. Development server starts
bin/dev &
sleep 10
curl -s http://localhost:3000 | grep -q "RepoVista"
# Expected: HTML containing "RepoVista"

# 2. Repository listing works
curl -s http://localhost:3000 | grep -q "repository"
# Expected: Repository cards in HTML

# 3. Search works (Turbo Stream)
curl -s "http://localhost:3000?query=test" -H "Accept: text/vnd.turbo-stream.html"
# Expected: Turbo Stream response

# 4. Tag details work
curl -s http://localhost:3000/repositories/test-repo | grep -q "tag"
# Expected: Tag rows in HTML

# 5. RSpec tests pass
bundle exec rspec
# Expected: All tests green, exit code 0

# 6. Playwright tests pass
npx playwright test
# Expected: All tests pass, exit code 0

# 7. No critical RuboCop offenses
bundle exec rubocop --format simple
# Expected: No errors (warnings acceptable)
```

### Final Checklist
- [ ] All "Must Have" features present
- [ ] All "Must NOT Have" guardrails respected
- [ ] All RSpec tests pass
- [ ] All Playwright E2E tests pass
- [ ] Dark mode works (toggle + persistence)
- [ ] Search works (debounced, real-time)
- [ ] Copy button works
- [ ] Responsive layout (1/2/3 columns)
- [ ] Skeleton UI during loading
- [ ] Mock service works in development
- [ ] README updated with setup instructions
