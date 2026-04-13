# RepoVista: Self-Hosted Docker Registry 전환 설계

## 개요

RepoVista를 외부 Docker Registry에 의존하는 클라이언트에서, 자체적으로 Docker Registry V2 API를 구현하여 `docker push`/`docker pull`을 직접 처리하는 독립 서비스로 전환한다.

### 핵심 결정 사항

| 항목 | 결정 |
|------|------|
| 접근 방식 | Rails 단일 앱에서 Registry V2 API 직접 구현 |
| 스토리지 | 로컬 파일시스템 (content-addressable) |
| 인증 | 없음 (오픈) |
| 기존 외부 registry 기능 | 완전 제거 |
| Manifest 형식 | V2 Schema 2 단일 플랫폼만 |
| 메타데이터 | DB에 풍부하게 저장 (layer, config, manifest 전체) |
| 웹 UI CRUD | 조회, 검색, 삭제 + tar import/export |

---

## 1. 전체 아키텍처

### 구조

```
RepoVista (단일 Rails 8 프로세스)
├── Registry V2 API (/v2/...)     ← Docker CLI 엔드포인트
├── Web UI (/, /repositories/...) ← 브라우저 엔드포인트
├── SQLite DB                     ← 메타데이터
└── Local Filesystem Storage      ← Blob/Manifest 실제 데이터
     └── storage/
         ├── blobs/
         │   └── sha256/
         │       └── <aa>/<digest>
         └── uploads/
             └── <uuid>/
```

### 요청 흐름

**Docker CLI → Registry V2 API:**

```
docker push myimage:latest
  → PUT /v2/myimage/blobs/uploads/        (blob 업로드 시작)
  → PATCH /v2/myimage/blobs/uploads/<uuid> (chunk 전송)
  → PUT /v2/myimage/blobs/uploads/<uuid>?digest=sha256:...  (업로드 완료)
  → PUT /v2/myimage/manifests/latest       (manifest 저장)

docker pull myimage:latest
  → GET /v2/myimage/manifests/latest       (manifest 조회)
  → GET /v2/myimage/blobs/sha256:...        (blob 다운로드)
```

**브라우저 → Web UI:**

```
GET /                                        → 대시보드 (repo 목록)
GET /repositories/:name                      → tag 목록 + 상세 정보
DELETE /repositories/:name/tags/:tag         → tag 삭제
POST /repositories/import                    → tar 업로드
GET /repositories/:name/tags/:tag/export     → tar 다운로드
```

### 제거 대상

기존 코드에서 완전히 제거:
- `Registry` 모델 및 마이그레이션
- `DockerRegistryService`, `MockRegistryService`, `RegistryConnectionTester`, `RegistryHealthCheckService`, `LocalRegistryScanner`
- `RegistriesController` 및 관련 뷰
- `registry_selector_controller.js`, `registry_form_controller.js`
- 세션 기반 registry 전환 로직
- `config/initializers/docker_registry.rb`, `config/initializers/registry_setup.rb`

---

## 2. 데이터베이스 스키마

### 테이블 설계

```ruby
# repositories
create_table :repositories do |t|
  t.string :name, null: false
  t.integer :tags_count, default: 0
  t.bigint :total_size, default: 0
  t.timestamps
  t.index :name, unique: true
end

# tags
create_table :tags do |t|
  t.references :repository, null: false, foreign_key: true
  t.references :manifest, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps
  t.index [:repository_id, :name], unique: true
end

# manifests
create_table :manifests do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :digest, null: false
  t.string :media_type, null: false
  t.text :payload, null: false
  t.bigint :size, null: false
  t.string :config_digest
  t.string :architecture
  t.string :os
  t.text :docker_config
  t.timestamps
  t.index :digest, unique: true
  t.index [:repository_id, :digest]
end

# layers
create_table :layers do |t|
  t.references :manifest, null: false, foreign_key: true
  t.references :blob, null: false, foreign_key: true
  t.integer :position, null: false
  t.index [:manifest_id, :position], unique: true
  t.index [:manifest_id, :blob_id], unique: true
end

# blobs
create_table :blobs do |t|
  t.string :digest, null: false
  t.bigint :size, null: false
  t.string :content_type
  t.integer :references_count, default: 0
  t.timestamps
  t.index :digest, unique: true
end

# blob_uploads
create_table :blob_uploads do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :uuid, null: false
  t.bigint :byte_offset, default: 0
  t.timestamps
  t.index :uuid, unique: true
end
```

### 모델 관계

```
Repository 1──N Tag
Repository 1──N Manifest
Manifest   1──N Layer
Layer      N──1 Blob
Tag        N──1 Manifest
```

### 설계 원칙

- Blob은 content-addressable: 같은 digest는 하나만 저장, 여러 manifest가 공유
- `references_count`: blob 참조 카운트 (추후 GC 대상 판별용)
- `payload`: manifest JSON 전체를 DB에 보관하여 파일시스템 없이도 빠른 조회
- `docker_config`: 이미지 config(env, cmd, entrypoint, labels 등)를 DB에 캐싱

---

## 3. Docker Registry V2 API

### 엔드포인트

```ruby
scope '/v2', defaults: { format: :json } do
  get '/', to: 'v2/base#index'
  get '/_catalog', to: 'v2/catalog#index'
  get '/*name/tags/list', to: 'v2/tags#index'

  get    '/*name/manifests/:reference', to: 'v2/manifests#show'
  put    '/*name/manifests/:reference', to: 'v2/manifests#update'
  delete '/*name/manifests/:reference', to: 'v2/manifests#destroy'

  get    '/*name/blobs/:digest', to: 'v2/blobs#show'
  head   '/*name/blobs/:digest', to: 'v2/blobs#show'
  delete '/*name/blobs/:digest', to: 'v2/blobs#destroy'

  post   '/*name/blobs/uploads', to: 'v2/blob_uploads#create'
  patch  '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#update'
  put    '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#complete'
  delete '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#destroy'
end
```

### 컨트롤러 구조

```
app/controllers/v2/
├── base_controller.rb          # V2 API 공통 (ActionController::API)
├── catalog_controller.rb       # GET /v2/_catalog
├── tags_controller.rb          # GET /v2/<name>/tags/list
├── manifests_controller.rb     # GET/PUT/DELETE manifests
├── blobs_controller.rb         # GET/HEAD/DELETE blobs
└── blob_uploads_controller.rb  # POST/PATCH/PUT/DELETE uploads
```

### Blob Upload Flow

1. `POST /v2/<name>/blobs/uploads/` → `202 Accepted` + `Location` 헤더, `BlobUpload` 레코드 생성
2. `PATCH /v2/<name>/blobs/uploads/<uuid>` → chunk append, `byte_offset` 갱신, `Content-Range` 응답
3. `PUT /v2/<name>/blobs/uploads/<uuid>?digest=sha256:...` → digest 검증, blob 영구 저장, 임시 파일 정리

Monolithic upload도 지원: `POST` 시 `?digest=` 파라미터가 있으면 한번에 완료.

### Manifest PUT Flow

1. Manifest JSON 파싱 및 V2 Schema 2 검증
2. 참조된 blob들 존재 확인
3. Config blob에서 이미지 메타데이터 추출 (os, architecture, env, cmd 등)
4. Manifest 레코드 생성/갱신
5. Tag 레코드 생성/갱신 (reference가 tag 이름인 경우)
6. Layer 레코드들 생성
7. Repository의 `total_size` 갱신

### 에러 응답 형식

```json
{
  "errors": [{
    "code": "BLOB_UNKNOWN",
    "message": "blob unknown to registry",
    "detail": { "digest": "sha256:..." }
  }]
}
```

에러 코드: `BLOB_UNKNOWN`, `BLOB_UPLOAD_UNKNOWN`, `MANIFEST_UNKNOWN`, `MANIFEST_INVALID`, `NAME_UNKNOWN`, `NAME_INVALID`, `TAG_INVALID`, `DIGEST_INVALID`, `UNSUPPORTED`

### 필수 응답 헤더

- `Docker-Distribution-API-Version: registry/2.0`
- `Docker-Content-Digest: sha256:...`
- `Content-Length`, `Content-Type`
- `Location` (upload 시)
- `Range` (chunked upload 진행 상태)

---

## 4. 파일시스템 스토리지

### 디렉토리 구조

```
storage/
├── blobs/
│   └── sha256/
│       ├── aa/
│       │   └── aabbccdd...full_digest
│       ├── bb/
│       │   └── bbccddee...full_digest
│       └── ...
└── uploads/
    ├── <uuid>/
    │   ├── data
    │   └── startedat
    └── ...
```

### BlobStore 서비스

```ruby
class BlobStore
  def initialize(root_path = Rails.configuration.storage_path)

  # Blob 관리
  def get(digest)                        # → IO stream
  def put(digest, io)                    # → 영구 경로에 저장
  def exists?(digest)                    # → boolean
  def delete(digest)                     # → 삭제
  def path_for(digest)                   # → 파일 경로

  # Upload 세션 관리
  def create_upload(uuid)                # → 임시 디렉토리 생성
  def append_upload(uuid, io)            # → data 파일에 append
  def upload_size(uuid)                  # → 현재 바이트 수
  def finalize_upload(uuid, digest)      # → digest 검증 후 blobs/로 이동
  def cancel_upload(uuid)                # → 임시 디렉토리 삭제
  def cleanup_stale_uploads(max_age: 1.hour)
end
```

### 설계 원칙

- **Content-addressable**: digest를 파일명으로 사용, 중복 저장 방지
- **서브디렉토리 분산**: digest 앞 2글자로 분산 (`sha256/aa/`, `sha256/bb/`)
- **Atomic write**: 임시 파일에 쓴 뒤 `File.rename`으로 이동
- **Digest 검증**: `finalize_upload` 시 실제 SHA256 계산하여 클라이언트 제출 값과 비교
- **스트리밍 응답**: `send_file` 또는 chunked streaming으로 대용량 blob 응답

### 설정

```ruby
config.storage_path = ENV.fetch('STORAGE_PATH', Rails.root.join('storage', 'registry'))
```

### 대용량 파일 I/O 최적화

**다운로드 (blob GET):**
- 기본: `send_file`로 Puma 스레드에서 직접 서빙
- 프로덕션 최적화: `Rack::Sendfile` 헤더를 통한 리버스 프록시 위임 지원
  - Nginx: `X-Accel-Redirect` 헤더로 파일 서빙을 nginx에 위임
  - 환경변수 `SENDFILE_HEADER`로 설정 가능 (기본: 없음 = Rails 직접 서빙)

```ruby
# config/environments/production.rb
config.action_dispatch.x_sendfile_header = ENV.fetch('SENDFILE_HEADER', nil)
# Nginx: 'X-Accel-Redirect', Apache: 'X-Sendfile'
```

**업로드 (blob PATCH/PUT):**
- `request.body` (Rack::Input)를 직접 스트리밍 읽기 — 전체를 메모리에 버퍼링하지 않음
- chunk 단위(64KB)로 읽어서 디스크에 append
- `config.middleware`에서 `Rack::TempfileReaper` 활성화하여 임시 파일 자동 정리

---

## 5. 웹 UI 및 CRUD

### 라우팅

```ruby
root 'repositories#index'

resources :repositories, only: [:index, :show, :destroy], param: :name,
                         constraints: { name: /[^\/]+(?:\/[^\/]+)*/ } do
  resources :tags, only: [:show, :destroy], param: :name do
    member do
      get :export
    end
  end

  collection do
    post :import
  end
end
```

### 페이지별 기능

**대시보드 / Repository 목록 (`GET /`)**
- Repository 카드 그리드: 이름, tag 수, 총 사이즈, 최종 업데이트
- 검색 (debounced), 정렬 (이름순, 최근 업데이트순, 사이즈순)

**Repository 상세 (`GET /repositories/:name`)**
- Tag 목록 테이블: tag 이름, digest(축약), 사이즈, 생성일
- `docker pull` 명령어 복사 버튼
- Tag 삭제, Repository 삭제 버튼

**Tag 상세 (`GET /repositories/:name/tags/:tag`)**
- Manifest 정보: digest, media_type, 사이즈
- Image Config: OS, architecture, env, cmd, entrypoint, labels
- Layer 목록: digest, 사이즈, 순서
- tar export 다운로드 버튼

**이미지 Import (`POST /repositories/import`)**
- `docker save` tar 파일 업로드
- **비동기 처리 (Solid Queue)**: 대형 tar 파일은 웹 요청 타임아웃을 유발하므로, 업로드된 tar를 임시 경로에 저장 후 즉시 202 응답. 파싱/처리는 `ProcessTarImportJob`에서 백그라운드 실행
- 진행률: Turbo Stream 브로드캐스트로 실시간 갱신 (파싱 시작 → layer 처리 중 → 완료/실패)
- Repository 이름/tag 자동 추출, 사용자 override 가능
- Import 상태 추적을 위한 `imports` 테이블 추가 (상태: pending/processing/completed/failed)

**이미지 Export (`GET /repositories/:name/tags/:tag/export`)**
- **비동기 처리 (Solid Queue)**: `PrepareExportJob`에서 `docker load` 호환 tar를 임시 경로에 생성
- 완료 후 Turbo Stream으로 다운로드 링크 브로드캐스트
- 생성된 tar 파일은 다운로드 후 또는 일정 시간(1시간) 후 자동 정리

### Import/Export 비동기 아키텍처

```
브라우저                      Rails                     Solid Queue
  │                            │                            │
  ├─ POST /import (tar) ──────►│                            │
  │                            ├─ tar 임시 저장              │
  │                            ├─ Import 레코드 생성 (pending)│
  │                            ├─ ProcessTarImportJob 등록 ─►│
  │◄─ 202 + import_id ─────────┤                            │
  │                            │                            ├─ tar 파싱
  │◄─ Turbo Stream (진행률) ───────────────────────────────── ├─ blob 저장
  │◄─ Turbo Stream (완료) ─────────────────────────────────── ├─ DB 레코드 생성
  │                            │                            │
```

### Import/Export 서비스 및 Job

```ruby
# 백그라운드 Job
class ProcessTarImportJob < ApplicationJob
  queue_as :default
  def perform(import_id)
    # ImageImportService 호출, Import 레코드 상태 갱신, Turbo Stream 브로드캐스트
  end
end

class PrepareExportJob < ApplicationJob
  queue_as :default
  def perform(export_id)
    # ImageExportService 호출, 완료 시 다운로드 URL 브로드캐스트
  end
end

# 서비스 (Job에서 호출)
class ImageImportService
  def call(tar_path, repository_name: nil, tag_name: nil)
  end
end

class ImageExportService
  def call(repository_name, tag_name, output_path:)
  end
end
```

### Import/Export 상태 추적 테이블

```ruby
create_table :imports do |t|
  t.string :status, null: false, default: 'pending'  # pending/processing/completed/failed
  t.string :repository_name
  t.string :tag_name
  t.string :tar_path                                   # 임시 tar 경로
  t.text :error_message
  t.integer :progress, default: 0                      # 0-100
  t.timestamps
end

create_table :exports do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :tag_name, null: false
  t.string :status, null: false, default: 'pending'
  t.string :output_path
  t.text :error_message
  t.timestamps
end
```

### 재활용 컴포넌트

| 컴포넌트 | 변경 |
|---|---|
| `search_controller.js` | 변경 없음 |
| `clipboard_controller.js` | 변경 없음 |
| `theme_controller.js` | 변경 없음 |
| TailwindCSS 테마 | 유지 |
| Turbo Frame/Stream | 유지 |

### 제거 대상

- `registries/` 뷰 전체
- Registry 선택 드롭다운
- `registry_selector_controller.js`, `registry_form_controller.js`

---

## 6. 서비스 레이어 및 에러 처리

### 서비스 구조

```
app/services/
├── blob_store.rb
├── image_import_service.rb
├── image_export_service.rb
├── manifest_processor.rb
└── digest_calculator.rb
```

### ManifestProcessor

manifest PUT 시 핵심 처리:
1. JSON 파싱 및 V2 Schema 2 검증
2. 참조 blob 존재 확인
3. Config blob에서 메타데이터 추출
4. Manifest/Tag/Layer 레코드 생성/갱신
5. Repository `total_size` 재계산

### DigestCalculator

```ruby
class DigestCalculator
  def self.compute(io_or_string)       # → "sha256:abcdef..."
  def self.verify!(io, expected_digest) # → raise Registry::DigestMismatch if mismatch
end
```

### 에러 처리

**V2 API (Docker CLI 대상):**

```ruby
class V2::BaseController < ActionController::API
  # Registry V2 스펙의 JSON 에러 포맷으로 응답
  # rescue_from 으로 각 커스텀 예외를 적절한 HTTP 상태 코드에 매핑
end
```

**웹 UI (브라우저 대상):**

```ruby
class ApplicationController < ActionController::Base
  # ActiveRecord::RecordNotFound → redirect + flash alert
  # Registry::Error → redirect_back + flash alert
end
```

### 커스텀 예외

```ruby
module Registry
  class Error < StandardError; end
  class BlobUnknown < Error; end
  class BlobUploadUnknown < Error; end
  class ManifestUnknown < Error; end
  class ManifestInvalid < Error; end
  class NameUnknown < Error; end
  class DigestMismatch < Error; end
  class Unsupported < Error; end
end
```

### 컨트롤러 분리

- `V2::BaseController` → `ActionController::API` (세션/CSRF 불필요)
- `ApplicationController` → `ActionController::Base` (Rails 풀스택)

---

## 7. Garbage Collection (GC) 정책

### 문제

Tag나 Repository를 삭제해도, 해당 blob이 다른 manifest에서 공유 중일 수 있어 즉각 삭제가 불가능하다.
업로드 중단된 임시 파일도 디스크에 잔존할 수 있다.

### 설계: 2단계 삭제

**1단계 — 참조 해제 (동기, 웹 요청 내):**
- Tag 삭제: `Tag` 레코드만 삭제. `Manifest`는 다른 tag가 참조 중일 수 있으므로 유지
- Repository 삭제: 해당 repo의 `Tag`, `Manifest`, `Layer` 레코드 삭제. `Blob`의 `references_count` 감소
- Manifest 삭제 (V2 API): `Tag` 참조 해제, `Layer` 레코드 삭제, `Blob`의 `references_count` 감소

**2단계 — 고아 blob 정리 (비동기, Solid Queue):**

```ruby
class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :default

  def perform
    # 1. references_count == 0인 Blob 레코드 조회
    # 2. 해당 blob 파일을 디스크에서 삭제
    # 3. Blob DB 레코드 삭제
    # 4. uploads/ 디렉토리에서 1시간 이상 된 임시 파일 정리
    # 5. exports/ 디렉토리에서 1시간 이상 된 tar 파일 정리
    # 6. imports/에서 completed/failed 상태이고 24시간 이상 된 tar 파일 정리
  end
end
```

### 실행 주기

- **Solid Queue recurring schedule**: 매 30분마다 `CleanupOrphanedBlobsJob` 실행
- 설정: `config/recurring.yml`

```yaml
# config/recurring.yml
cleanup_orphaned_blobs:
  class: CleanupOrphanedBlobsJob
  schedule: every 30 minutes
```

### 안전장치

- Blob 삭제 전 `references_count`를 다시 확인 (race condition 방어)
- 삭제 작업은 트랜잭션 내에서 DB 레코드 삭제 → 파일 삭제 순서로 진행 (DB 삭제 실패 시 파일 잔존은 안전, 파일만 삭제되고 DB에 남는 것은 위험)

---

## 8. 동시성 (Concurrency) 방어

### 문제

Docker CLI는 push 시 여러 layer를 병렬 업로드한다. 동일한 base image layer가 동시에 다른 요청으로 push될 수 있어 race condition이 발생한다.

### 방어 전략

**Blob 레코드 생성 — `create_or_find_by` 패턴:**

```ruby
# Blob이 이미 존재하면 찾고, 없으면 생성
# find_or_create_by와 달리 INSERT 먼저 시도 → 충돌 시 SELECT
blob = Blob.create_or_find_by!(digest: digest) do |b|
  b.size = size
  b.content_type = content_type
end
```

`find_or_create_by`는 SELECT → INSERT 순서라 TOCTOU race가 있다. `create_or_find_by`는 INSERT 먼저 시도하므로 unique index가 보장하는 원자성을 활용한다.

**references_count 갱신 — 원자적 연산:**

```ruby
# 증가 (manifest 생성 시)
blob.increment!(:references_count)

# 감소 (manifest 삭제 시)
blob.decrement!(:references_count)
```

`increment!`/`decrement!`는 `UPDATE blobs SET references_count = references_count + 1`로 변환되어 DB 레벨 원자성이 보장된다.

**파일시스템 중복 쓰기 방어:**

```ruby
# BlobStore#put — 이미 존재하면 덮어쓰지 않음
def put(digest, io)
  target = path_for(digest)
  return if File.exist?(target)  # content-addressable이므로 동일 digest = 동일 내용
  # atomic write (임시 파일 → rename)
end
```

Content-addressable 스토리지의 특성상, 같은 digest 파일이 이미 존재하면 내용이 동일하므로 안전하게 skip 가능.

**Upload 세션 격리:**

각 `BlobUpload`는 고유 UUID를 가지므로 서로 다른 upload 세션 간 충돌 없음. 동일 blob을 두 클라이언트가 동시에 업로드해도 각자의 임시 디렉토리에서 독립 진행 후 `finalize_upload`에서 합류.

---

## 9. Multi-Architecture Manifest 거부 정책

### 범위

본 설계는 V2 Schema 2 단일 플랫폼 이미지만 지원한다. 다음 media type들은 명시적으로 거부한다:

| Media Type | 설명 | 처리 |
|---|---|---|
| `application/vnd.docker.distribution.manifest.v2+json` | V2 Schema 2 Image | **지원** |
| `application/vnd.docker.distribution.manifest.list.v2+json` | Manifest List (multi-arch) | **거부** |
| `application/vnd.oci.image.manifest.v1+json` | OCI Image Manifest | **거부** |
| `application/vnd.oci.image.index.v1+json` | OCI Image Index (multi-arch) | **거부** |

### 구현

```ruby
# V2::ManifestsController#update
SUPPORTED_MEDIA_TYPES = [
  'application/vnd.docker.distribution.manifest.v2+json'
].freeze

def update
  content_type = request.content_type
  unless SUPPORTED_MEDIA_TYPES.include?(content_type)
    raise Registry::Unsupported, "Unsupported manifest media type: #{content_type}"
  end
  # ... manifest 처리
end
```

### 에러 응답

```json
{
  "errors": [{
    "code": "UNSUPPORTED",
    "message": "Unsupported manifest media type: application/vnd.docker.distribution.manifest.list.v2+json",
    "detail": {}
  }]
}
```

HTTP 상태 코드: `415 Unsupported Media Type`

### 사용자 안내

Multi-arch 이미지를 push하려는 사용자에게는 단일 플랫폼을 명시하도록 안내:

```bash
# multi-arch 대신 단일 플랫폼 지정
docker build --platform linux/amd64 -t myregistry:5000/myimage:latest .
docker push myregistry:5000/myimage:latest
```

---

## 10. 테스트 전략

### RSpec 테스트 구조

```
spec/
├── models/                        # 모든 새 모델의 유효성, 관계 테스트
├── services/                      # BlobStore, ManifestProcessor, DigestCalculator,
│                                  #   ImageImportService, ImageExportService
├── jobs/                          # CleanupOrphanedBlobsJob, ProcessTarImportJob, PrepareExportJob
├── requests/
│   ├── v2/                        # Registry V2 API 전체 엔드포인트
│   └── repositories_spec.rb       # 웹 UI CRUD, import/export
├── helpers/
└── fixtures/
    ├── manifests/v2_schema2.json
    ├── configs/image_config.json
    └── tarballs/sample_image.tar
```

### 핵심 테스트 (반드시 통과)

1. Blob upload full flow (POST → PATCH → PUT)
2. Manifest PUT/GET (push 후 pull 정상 동작)
3. Digest 검증 (잘못된 digest 거부)
4. BlobStore atomic write (불완전 파일 방지)
5. 동시 blob 업로드 시 race condition 미발생 (create_or_find_by 동작 확인)
6. Manifest List/OCI media type push 시 415 Unsupported 거부 응답

### 중요 테스트

7. Image import/export tar round-trip 정합성 (비동기 Job 완료 후 검증)
8. Tag 삭제 → GC Job 실행 → 고아 blob 디스크 정리 확인
9. 웹 UI CRUD (repository/tag 조회, 삭제)
10. Import 진행률 Turbo Stream 브로드캐스��
11. X-Accel-Redirect 헤더 설정 시 send_file 대신 헤더 응답 확인

### E2E 테스트 (Playwright)

유지/수정: `repository-list`, `tag-details`, `search`, `dark-mode`
신규: `image-import`, `image-export`
제거: `registry-management`, `registry-switching`, `registry-dropdown`

### 테스트 헬퍼

```ruby
module RegistryTestHelpers
  def create_test_blob(content = SecureRandom.random_bytes(1024))
  def build_test_manifest(config_digest:, layer_digests:)
  def simulate_docker_push(repo_name, tag_name)
end
```
