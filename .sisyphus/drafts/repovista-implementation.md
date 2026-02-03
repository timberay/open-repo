# Draft: RepoVista 전체 구현 계획

## Requirements (확인됨)

### 핵심 기능
1. **Repository Listing (홈페이지)**
   - `/v2/_catalog` API 호출하여 모든 리포지토리 목록 표시
   - Grid 레이아웃 (반응형: 1/2/3열)
   - 실시간 검색 (디바운스, Turbo Streams)
   - 페이지네이션 (Link 헤더 파싱)
   - 정렬 (A-Z, Z-A)
   - 로딩 상태 (Skeleton UI)

2. **Tag Details (Repository 상세 페이지)**
   - `/v2/<name>/tags/list` API 호출
   - 태그 메타데이터: Name, Digest (12자), Size, Created Date
   - Copy Pull Command 버튼

3. **Navigation & UX**
   - 반응형 디자인 (TailwindCSS)
   - 다크 모드 (시스템 감지 + 수동 토글)
   - Hotwire 네비게이션 (Turbo Frames)
   - 로딩 피드백

### 기술 요구사항
- Docker Registry V2 API 통신 (Faraday + Basic Auth)
- Mock Service (개발용)
- 캐싱 (Solid Cache): Catalog/Tags 5분, Manifests 캐싱안함
- 보안: 서버사이드 프록시, 읽기 전용

## 프로젝트 현재 상태 (확인됨)

### 설정된 것들 ✅
- Rails 8.1.2 기본 구조
- TailwindCSS 설치됨 (tailwindcss-rails gem)
  - `app/assets/tailwind/application.css` 존재 (`@import "tailwindcss"`)
  - `Procfile.dev`에 tailwindcss:watch 포함
- Hotwire 설치됨 (turbo-rails, stimulus-rails)
  - importmap 설정됨
  - Stimulus controllers 폴더 구조 존재
- RSpec 설치됨 (rspec-rails gem)
  - `spec/rails_helper.rb`, `spec/spec_helper.rb` 존재
- Solid Cache/Queue/Cable gems 포함 (미설정)
- SQLite 설정됨

### 필요한 것들 ❌
- `faraday` gem (HTTP 클라이언트) - 미설치
- routes.rb - 기본 health check만 존재
- 컨트롤러 - application_controller만 존재
- 서비스 객체 - 없음
- 모델 - application_record만 존재
- 뷰 - 기본 레이아웃만 존재
- Stimulus 컨트롤러 - hello_controller만 존재
- 캐시 설정 - development에서 memory_store 사용

## Technical Decisions

### HTTP 클라이언트
- **결정**: Faraday 사용 (retry middleware, timeout 지원)
- **이유**: Rails 커뮤니티에서 가장 널리 사용, 미들웨어 시스템 우수

### 아키텍처
- **결정**: Service Object 패턴 사용
- **구조**:
  - `DockerRegistryService` - 핵심 API 클라이언트
  - `MockRegistryService` - 개발/테스트용
  - Adapter 패턴으로 전환 가능

### 캐싱
- **결정**: Rails.cache 사용 (development: memory, production: solid_cache)
- **TTL**: Catalog/Tags 5분, Manifests 안함 (자주 변경)

## Scope Boundaries

### INCLUDE
- Repository 목록 페이지 (index)
- Repository 상세 페이지 (show)
- 실시간 검색
- 페이지네이션
- 정렬
- 다크 모드
- Copy to clipboard
- Skeleton UI
- RSpec 테스트 (서비스, 컨트롤러)
- Playwright E2E 테스트

### EXCLUDE
- 이미지 삭제 기능 (읽기 전용)
- 인증/사용자 관리
- 다중 레지스트리 지원
- 이미지 푸시 기능
- Webhook/알림

## User Decisions (확정됨)

1. **테스트 전략**: Tests-after
   - RSpec으로 주요 서비스와 컨트롤러 테스트
   - 기능 구현 후 테스트 작성

2. **E2E 테스트**: Playwright 포함
   - 핵심 플로우만: 목록 조회, 검색, 태그 상세, Copy 버튼

3. **HTTP 클라이언트**: Faraday
   - Gemfile에 추가 필요
   - retry, timeout 미들웨어 활용

4. **개발 방식**: Mock 우선 개발
   - USE_MOCK_REGISTRY 환경변수로 전환

5. **병렬 작업**: 균형 (백엔드/프론트엔드 동시)

## Research Findings

### 완료됨 ✅
- **bg_b2ee1f22**: 프로젝트 구조 탐색
  - Rails 8.1.2, Ruby 3.4.8 완전 구성
  - Hotwire, TailwindCSS, RSpec 설정됨
  - routes, controllers, services, models 생성 필요
  - Faraday 미설치

### 실행 중
- bg_d9661798: Docker Registry V2 API 연구
- bg_5f43fcdc: Rails 8 Hotwire 패턴 연구
