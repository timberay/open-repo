# RepoVista 구현 진행 상황

**마지막 업데이트**: 2026-02-02 21:40 KST  
**진행률**: 8/15 태스크 완료 (53%)

---

## ✅ 완료된 작업 (Wave 1 & Wave 2)

### Wave 1: 기반 설정 (완료)
- [x] **Task 1**: Gemfile 및 의존성 설정
  - Faraday, faraday-retry, webmock 추가
  - bundle install 완료
  - config/initializers/docker_registry.rb 생성
  - Commit: `4eb423d - chore: add Faraday, WebMock gems and Docker Registry initializer`

- [x] **Task 2**: Playwright 설정
  - Playwright 1.58.1 설치
  - playwright.config.ts 생성
  - e2e/ 디렉토리 구조 생성
  - Commit: (package.json 변경 포함)

- [x] **Task 3**: TailwindCSS Dark Mode 설정
  - config/tailwind.config.js 생성 (darkMode: 'class')
  - app/assets/stylesheets/application.tailwind.css 생성
  - Commit: `feat: configure TailwindCSS dark mode`

- [x] **Task 4**: 기본 레이아웃 업데이트
  - app/views/layouts/application.html.erb 업데이트
  - 네비게이션 바, 다크 모드 토글 추가
  - app/javascript/controllers/theme_controller.js 생성
  - Commit: `c5ea664 - feat: update layout with navigation and dark mode support`

### Wave 2: 핵심 서비스 (완료)
- [x] **Task 5**: DockerRegistryService 구현
  - app/services/docker_registry_service.rb 생성
  - Faraday 기반 HTTP 클라이언트
  - catalog, tags, manifest 메서드 구현
  - 캐싱, 에러 처리, retry 로직 포함

- [x] **Task 6**: MockRegistryService 구현
  - app/services/mock_registry_service.rb 생성
  - 12개 Mock 리포지토리 데이터
  - 동일한 인터페이스 구현

- [x] **Task 7**: Repository/Tag 모델 구현
  - app/models/repository.rb (Non-ActiveRecord)
  - app/models/tag.rb (Non-ActiveRecord)
  - pull_command, short_digest, human_size 메서드

- [x] **Task 8**: Routes 및 RepositoriesController
  - config/routes.rb 업데이트 (root, resources :repositories)
  - app/controllers/repositories_controller.rb 생성
  - app/controllers/concerns/registry_error_handler.rb 생성
  - Commit: `c3f13fc - feat: add RepositoriesController and routes`
  - Commit: `b522b36 - feat: implement DockerRegistryService, MockRegistryService, and models`

---

## 🚧 현재 작업 중

### Task 9: Repository 목록 뷰 (in_progress)
**상태**: 시작 안 함 (컨트롤러까지만 완료)

**해야 할 일**:
1. `app/views/repositories/index.html.erb` 생성
   - 검색 입력 필드 (Stimulus search_controller)
   - 정렬 드롭다운
   - Turbo Frame으로 감싼 리포지토리 그리드

2. `app/views/repositories/_repository_card.html.erb` 생성
   - 리포지토리 이름, 태그 수, 마지막 업데이트
   - 클릭 시 상세로 이동
   - 반응형: 모바일 1열, 태블릿 2열, 데스크탑 3열

3. `app/views/repositories/index.turbo_stream.erb` 생성 (검색용)

4. 검증 후 커밋: `feat: implement Repository listing view with responsive grid`

---

## 📋 남은 작업 (Wave 3 & Wave 4)

### Wave 3: 뷰 및 인터랙션
- [ ] **Task 10**: Tag 상세 뷰
  - app/views/repositories/show.html.erb
  - app/views/repositories/_tag_row.html.erb
  - Copy Pull Command 버튼

- [ ] **Task 11**: Stimulus 컨트롤러 구현
  - app/javascript/controllers/search_controller.js (디바운스)
  - app/javascript/controllers/clipboard_controller.js (복사)
  - theme_controller.js는 이미 완료됨

- [ ] **Task 12**: Skeleton UI 및 로딩 상태
  - app/views/repositories/_skeleton_card.html.erb
  - app/views/repositories/_skeleton_row.html.erb
  - TailwindCSS animate-pulse

### Wave 4: 테스트 및 완성
- [ ] **Task 13**: RSpec 테스트 작성
  - spec/services/docker_registry_service_spec.rb
  - spec/services/mock_registry_service_spec.rb
  - spec/models/repository_spec.rb
  - spec/models/tag_spec.rb
  - spec/requests/repositories_spec.rb

- [ ] **Task 14**: Playwright E2E 테스트 작성
  - e2e/repository-list.spec.ts
  - e2e/search.spec.ts
  - e2e/tag-details.spec.ts
  - e2e/dark-mode.spec.ts

- [ ] **Task 15**: 최종 통합 및 문서화
  - README.md 업데이트
  - 전체 검증 (bin/dev, 테스트)
  - RuboCop 실행

---

## 🎯 다음 시작 지점

**Task 9부터 재개하세요:**

```bash
# 1. 서버 실행하여 현재 상태 확인
bin/dev

# 2. http://localhost:3000 접속
# 예상 동작: RepositoriesController#index 실행되나 뷰가 없어서 에러

# 3. Task 9 구현 시작
# app/views/repositories/index.html.erb 생성
# app/views/repositories/_repository_card.html.erb 생성
```

---

## 📁 프로젝트 파일 구조 (현재)

```
repo-vista/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb ✅
│   │   ├── repositories_controller.rb ✅
│   │   └── concerns/
│   │       └── registry_error_handler.rb ✅
│   ├── models/
│   │   ├── repository.rb ✅
│   │   └── tag.rb ✅
│   ├── services/
│   │   ├── docker_registry_service.rb ✅
│   │   └── mock_registry_service.rb ✅
│   ├── views/
│   │   ├── layouts/
│   │   │   └── application.html.erb ✅
│   │   └── repositories/
│   │       ├── index.html.erb ❌ (다음 작업)
│   │       ├── show.html.erb ❌
│   │       ├── _repository_card.html.erb ❌
│   │       └── _tag_row.html.erb ❌
│   ├── javascript/controllers/
│   │   ├── theme_controller.js ✅
│   │   ├── search_controller.js ❌
│   │   └── clipboard_controller.js ❌
│   └── assets/stylesheets/
│       └── application.tailwind.css ✅
├── config/
│   ├── routes.rb ✅
│   ├── tailwind.config.js ✅
│   └── initializers/
│       └── docker_registry.rb ✅
├── spec/ (빈 상태 - Task 13에서 작성)
├── e2e/
│   └── example.spec.ts ✅ (Task 14에서 실제 테스트 작성)
├── Gemfile ✅
├── playwright.config.ts ✅
└── package.json ✅
```

---

## 🔧 환경 설정

### 환경 변수 (.env 또는 시스템 환경변수)
```bash
REGISTRY_URL=https://registry.hub.docker.com
REGISTRY_USERNAME=your_username
REGISTRY_PASSWORD=your_password
USE_MOCK_REGISTRY=true  # 개발 중에는 true
```

### 개발 서버 실행
```bash
bin/dev  # Rails 서버 + Tailwind watcher
```

### 테스트 실행
```bash
bundle exec rspec  # RSpec (Task 13 이후)
npx playwright test  # E2E (Task 14 이후)
```

---

## 📊 예상 남은 시간

- **Wave 3 (Task 9-12)**: 약 2-3시간 (뷰 구현 + Stimulus)
- **Wave 4 (Task 13-15)**: 약 2-3시간 (테스트 + 문서화)
- **총**: 약 4-6시간

---

## 💡 참고사항

1. **Mock Registry 사용 중**: 현재 `USE_MOCK_REGISTRY=true`로 설정됨
2. **Gemini Limit 이슈**: 서브에이전트 사용 시 limit 문제 발생 가능. 필요 시 직접 구현 방식 사용
3. **계획 파일 위치**: `.sisyphus/plans/repovista-implementation.md`
4. **Boulder 상태**: `.sisyphus/boulder.json`

---

**작업 재개 시**: Task 9부터 시작하세요. 파일 생성부터 진행하면 됩니다.
