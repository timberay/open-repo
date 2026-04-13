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
  → GET /v2/blobs/sha256:...               (blob 다운로드)
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
- tar 파싱: manifest.json → config blob → layer blobs 추출
- 진행률 표시 (Turbo Stream)
- Repository 이름/tag 자동 추출, 사용자 override 가능

**이미지 Export (`GET /repositories/:name/tags/:tag/export`)**
- `docker load` 호환 tar 생성 및 스트리밍 다운로드

### Import/Export 서비스

```ruby
class ImageImportService
  def call(tar_io, repository_name: nil, tag_name: nil)
  end
end

class ImageExportService
  def call(repository_name, tag_name)
  end
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

## 7. 테스트 전략

### RSpec 테스트 구조

```
spec/
├── models/                        # 모든 새 모델의 유효성, 관계 테스트
├── services/                      # BlobStore, ManifestProcessor, DigestCalculator,
│                                  #   ImageImportService, ImageExportService
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

### 중요 테스트

5. Image import/export tar round-trip 정합성
6. Tag 삭제 시 manifest 참조 정리
7. 웹 UI CRUD (repository/tag 조회, 삭제)

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
