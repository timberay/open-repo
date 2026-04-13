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
| Manifest 형식 | V2 Schema 2 단일 플랫폼만 (Multi-arch 명시적 거부) |
| 메타데이터 | DB에 풍부하게 저장 (layer, config, manifest 전체) |
| 웹 UI CRUD | 조회, 검색, 삭제 + tar import/export |
| 비동기 처리 | Solid Queue (import/export, GC) |

---

## 1. 전체 아키텍처

### 구조

```
RepoVista (단일 Rails 8 프로세스)
├── Registry V2 API (/v2/...)     ← Docker CLI 엔드포인트
├── Web UI (/, /repositories/...) ← 브라우저 엔드포인트
├── Solid Queue Worker            ← 백그라운드 Job (import/export/GC)
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
  → POST /v2/myimage/blobs/uploads/                          (blob 업로드 시작)
  → POST /v2/myimage/blobs/uploads/?mount=<digest>&from=other (공유 layer mount)
  → PATCH /v2/myimage/blobs/uploads/<uuid>                    (chunk 전송)
  → PUT /v2/myimage/blobs/uploads/<uuid>?digest=sha256:...    (업로드 완료)
  → PUT /v2/myimage/manifests/latest                          (manifest 저장)

docker pull myimage:latest
  → HEAD /v2/myimage/manifests/latest          (manifest 존재 확인 + digest 획득)
  → GET  /v2/myimage/manifests/latest          (manifest 조회)
  → HEAD /v2/myimage/blobs/sha256:...          (blob 존재 확인)
  → GET  /v2/myimage/blobs/sha256:...          (blob 다운로드)
```

**브라우저 → Web UI:**

```
GET /                                        → 대시보드 (repo 목록)
GET /repositories/:name                      → tag 목록 + 상세 정보
DELETE /repositories/:name/tags/:tag         → tag 삭제
POST /repositories/import                    → tar 업로드 (비동기)
GET /repositories/:name/tags/:tag/export     → tar 다운로드 (비동기)
```

### 환경 설정

```bash
STORAGE_PATH=/var/data/registry    # Blob 스토리지 경로 (기본: Rails.root/storage/registry)
REGISTRY_HOST=registry.mycompany.com:5000  # Web UI에서 docker pull 명령어에 표시할 호스트
SENDFILE_HEADER=                   # 프로덕션: 'X-Accel-Redirect' (Nginx) 또는 'X-Sendfile' (Apache)
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
  t.string :name, null: false          # e.g. "myapp", "team-a/backend"
  t.integer :tags_count, default: 0    # counter cache
  t.bigint :total_size, default: 0     # bytes
  t.timestamps
  t.index :name, unique: true
end

# tags
create_table :tags do |t|
  t.references :repository, null: false, foreign_key: true
  t.references :manifest, null: false, foreign_key: true
  t.string :name, null: false          # e.g. "latest", "v1.0.0"
  t.timestamps
  t.index [:repository_id, :name], unique: true
end

# manifests
create_table :manifests do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :digest, null: false        # sha256:abcdef...
  t.string :media_type, null: false    # application/vnd.docker.distribution.manifest.v2+json
  t.text :payload, null: false         # manifest JSON 전체
  t.bigint :size, null: false          # manifest 자체 사이즈
  t.string :config_digest              # config blob digest
  t.string :architecture               # e.g. "amd64"
  t.string :os                         # e.g. "linux"
  t.text :docker_config                # config blob JSON (env, cmd, entrypoint 등)
  t.timestamps
  t.index :digest, unique: true
  t.index [:repository_id, :digest]
end

# layers (manifest ↔ blob 조인 테이블)
create_table :layers do |t|
  t.references :manifest, null: false, foreign_key: true
  t.references :blob, null: false, foreign_key: true
  t.integer :position, null: false     # layer 순서
  t.index [:manifest_id, :position], unique: true
  t.index [:manifest_id, :blob_id], unique: true
end

# blobs
create_table :blobs do |t|
  t.string :digest, null: false        # sha256:abcdef...
  t.bigint :size, null: false          # bytes
  t.string :content_type
  t.integer :references_count, default: 0  # manifest 참조 수 (GC 판별)
  t.timestamps
  t.index :digest, unique: true
end

# blob_uploads (진행 중인 chunked upload)
create_table :blob_uploads do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :uuid, null: false
  t.bigint :byte_offset, default: 0
  t.timestamps
  t.index :uuid, unique: true
end

# imports (비동기 tar import 상태 추적)
create_table :imports do |t|
  t.string :status, null: false, default: 'pending'  # pending/processing/completed/failed
  t.string :repository_name
  t.string :tag_name
  t.string :tar_path
  t.text :error_message
  t.integer :progress, default: 0     # 0-100
  t.timestamps
end

# exports (비동기 tar export 상태 추적)
create_table :exports do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :tag_name, null: false
  t.string :status, null: false, default: 'pending'  # pending/processing/completed/failed
  t.string :output_path
  t.text :error_message
  t.timestamps
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

- Blob은 content-addressable: 같은 digest는 하나만 저장, 여러 manifest/repository가 공유
- `references_count`: blob 참조 카운트 (GC 대상 판별)
- `payload`: manifest JSON 전체를 DB에 보관하여 파일시스템 없이도 빠른 조회
- `docker_config`: 이미지 config(env, cmd, entrypoint, labels 등)를 DB에 캐싱

---

## 3. Docker Registry V2 API

### 엔드포인트

```ruby
scope '/v2', defaults: { format: :json } do
  # Base — API 버전 확인
  get '/', to: 'v2/base#index'

  # Catalog — repository 목록 (페이지네이션)
  get '/_catalog', to: 'v2/catalog#index'

  # Tags — tag 목록 (페이지네이션)
  get '/*name/tags/list', to: 'v2/tags#index'

  # Manifests (GET + HEAD + PUT + DELETE)
  get    '/*name/manifests/:reference', to: 'v2/manifests#show'
  head   '/*name/manifests/:reference', to: 'v2/manifests#show'
  put    '/*name/manifests/:reference', to: 'v2/manifests#update'
  delete '/*name/manifests/:reference', to: 'v2/manifests#destroy'

  # Blobs (GET + HEAD + DELETE)
  get    '/*name/blobs/:digest', to: 'v2/blobs#show'
  head   '/*name/blobs/:digest', to: 'v2/blobs#show'
  delete '/*name/blobs/:digest', to: 'v2/blobs#destroy'

  # Blob Uploads (chunked upload + cross-repo mount)
  post   '/*name/blobs/uploads', to: 'v2/blob_uploads#create'
  patch  '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#update'
  put    '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#complete'
  delete '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#destroy'
end
```

### 컨트롤러 구조

```
app/controllers/v2/
├── base_controller.rb          # V2 API 공통 베이스 (ActionController::API)
├── catalog_controller.rb       # GET /v2/_catalog (페이지네이션)
├── tags_controller.rb          # GET /v2/<name>/tags/list (페이지네이션)
├── manifests_controller.rb     # HEAD/GET/PUT/DELETE manifests
├── blobs_controller.rb         # HEAD/GET/DELETE blobs
└── blob_uploads_controller.rb  # POST/PATCH/PUT/DELETE uploads (mount 포함)
```

### Blob Upload Flow

**표준 chunked upload:**
1. `POST /v2/<name>/blobs/uploads/` → `202 Accepted` + `Location` 헤더, `BlobUpload` 레코드 생성
2. `PATCH /v2/<name>/blobs/uploads/<uuid>` → chunk append, `byte_offset` 갱신
3. `PUT /v2/<name>/blobs/uploads/<uuid>?digest=sha256:...` → digest 검증, blob 영구 저장, 임시 파일 정리

**Monolithic upload:**
`POST /v2/<name>/blobs/uploads/?digest=sha256:...` — body에 전체 blob을 담아 한번에 완료.

**Cross-repository blob mount:**
`POST /v2/<name>/blobs/uploads/?mount=<digest>&from=<other-repo>`

```ruby
# V2::BlobUploadsController#create
def create
  if params[:mount].present? && params[:from].present?
    # 1. from repo에서 해당 digest의 blob 존재 확인
    # 2. 존재하면: blob의 references_count 증가, 201 Created 응답
    # 3. 존재하지 않으면: 일반 upload 세션 시작으로 fallback (202 Accepted)
    handle_blob_mount
  elsif params[:digest].present?
    handle_monolithic_upload
  else
    handle_start_upload
  end
end
```

mount 성공 시 응답:
```
201 Created
Location: /v2/<name>/blobs/<digest>
Docker-Content-Digest: <digest>
```

mount는 파일을 복사하지 않는다. content-addressable 스토리지이므로 동일 digest = 동일 파일이다. DB에서 참조 카운트만 증가시키면 된다.

### HEAD Manifest

Docker CLI는 `pull` 전에 반드시 `HEAD /v2/<name>/manifests/<reference>`를 호출하여 manifest 존재 여부와 digest를 확인한다.

```ruby
# V2::ManifestsController#show
def show
  manifest = find_manifest(params[:name], params[:reference])
  raise Registry::ManifestUnknown unless manifest

  response.headers['Docker-Content-Digest'] = manifest.digest
  response.headers['Content-Type'] = manifest.media_type
  response.headers['Content-Length'] = manifest.size.to_s

  if request.head?
    head :ok
  else
    render json: manifest.payload, content_type: manifest.media_type
  end
end
```

`reference`는 tag 이름(`latest`) 또는 digest(`sha256:abc...`) 둘 다 가능하다:
```ruby
def find_manifest(repo_name, reference)
  repo = Repository.find_by!(name: repo_name)
  if reference.start_with?('sha256:')
    repo.manifests.find_by!(digest: reference)
  else
    repo.tags.find_by!(name: reference)&.manifest
  end
rescue ActiveRecord::RecordNotFound
  nil
end
```

### Manifest PUT Flow

1. Content-Type 검증 (지원 media type만 허용, 미지원 시 415 거부)
2. Manifest JSON 파싱 및 V2 Schema 2 구조 검증
3. 참조된 blob들 존재 확인
4. Config blob에서 이미지 메타데이터 추출 (os, architecture, env, cmd 등)
5. Manifest 레코드 생성/갱신
6. Tag 레코드 생성/갱신 (reference가 tag 이름인 경우)
7. Layer 레코드들 생성
8. Repository의 `total_size` 갱신

### Catalog/Tags 페이지네이션

V2 스펙의 `?n=<count>&last=<last_item>` 페이지네이션을 지원한다.

**`GET /v2/_catalog?n=100&last=myapp`**

```ruby
# V2::CatalogController#index
def index
  n = (params[:n] || 100).to_i.clamp(1, 1000)
  scope = Repository.order(:name)
  scope = scope.where('name > ?', params[:last]) if params[:last].present?
  repos = scope.limit(n + 1).pluck(:name)

  # 다음 페이지 존재 여부 판단
  if repos.size > n
    repos.pop
    response.headers['Link'] = "</v2/_catalog?n=#{n}&last=#{repos.last}>; rel=\"next\""
  end

  render json: { repositories: repos }
end
```

**`GET /v2/<name>/tags/list?n=50&last=v1.0.0`**

```ruby
# V2::TagsController#index
def index
  repo = Repository.find_by!(name: params[:name])
  n = (params[:n] || 100).to_i.clamp(1, 1000)
  scope = repo.tags.order(:name)
  scope = scope.where('name > ?', params[:last]) if params[:last].present?
  tags = scope.limit(n + 1).pluck(:name)

  if tags.size > n
    tags.pop
    response.headers['Link'] = "</v2/#{repo.name}/tags/list?n=#{n}&last=#{tags.last}>; rel=\"next\""
  end

  render json: { name: repo.name, tags: tags }
end
```

`Link` 헤더에 `rel="next"`를 포함하여 Docker CLI가 다음 페이지를 자동으로 요청할 수 있게 한다.

### Multi-Architecture Manifest 거부 정책

본 설계는 V2 Schema 2 단일 플랫폼만 지원한다. 미지원 media type은 명시적으로 거부한다:

| Media Type | 처리 |
|---|---|
| `application/vnd.docker.distribution.manifest.v2+json` | **지원** |
| `application/vnd.docker.distribution.manifest.list.v2+json` | **거부 (415)** |
| `application/vnd.oci.image.manifest.v1+json` | **거부 (415)** |
| `application/vnd.oci.image.index.v1+json` | **거부 (415)** |

```ruby
# V2::ManifestsController
SUPPORTED_MEDIA_TYPES = [
  'application/vnd.docker.distribution.manifest.v2+json'
].freeze

def update
  unless SUPPORTED_MEDIA_TYPES.include?(request.content_type)
    raise Registry::Unsupported,
      "Unsupported manifest media type: #{request.content_type}. " \
      "This registry supports single-platform V2 Schema 2 manifests only. " \
      "Use: docker build --platform linux/amd64 -t <image> ."
  end
  # ...
end
```

에러 응답 (`415 Unsupported Media Type`):
```json
{
  "errors": [{
    "code": "UNSUPPORTED",
    "message": "Unsupported manifest media type: ...",
    "detail": {}
  }]
}
```

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

모든 V2 API 응답에 포함:
- `Docker-Distribution-API-Version: registry/2.0`

Manifest/Blob 응답 시:
- `Docker-Content-Digest: sha256:...`
- `Content-Length`, `Content-Type`

Upload 관련:
- `Location` (upload URL)
- `Range: 0-<offset>` (chunked upload 진행 상태)
- `Docker-Upload-UUID` (upload 세션 ID)

---

## 4. 파일시스템 스토리지

### 디렉토리 구조

```
storage/                          # STORAGE_PATH 환경변수로 설정
├── blobs/
│   └── sha256/
│       ├── aa/
│       │   └── aabbccdd...full_digest
│       ├── bb/
│       │   └── bbccddee...full_digest
│       └── ...                   # digest 앞 2자로 서브디렉토리 분산
├── uploads/
│   ├── <uuid1>/
│   │   ├── data                  # chunk들이 append되는 파일
│   │   └── startedat             # 업로드 시작 시간
│   └── ...
└── tmp/
    ├── imports/                  # import tar 임시 저장
    └── exports/                  # export tar 생성 임시 경로
```

### BlobStore 서비스

```ruby
class BlobStore
  def initialize(root_path = Rails.configuration.storage_path)

  # Blob 관리
  def get(digest)                        # → IO stream
  def put(digest, io)                    # → 영구 경로에 atomic write (이미 존재하면 skip)
  def exists?(digest)                    # → boolean
  def delete(digest)                     # → 파일 삭제
  def path_for(digest)                   # → 절대 경로
  def size(digest)                       # → File.size

  # Upload 세션 관리
  def create_upload(uuid)                # → 임시 디렉토리 + startedat 생성
  def append_upload(uuid, io)            # → data 파일에 chunk append (64KB 단위 스트리밍)
  def upload_size(uuid)                  # → 현재 byte offset
  def finalize_upload(uuid, digest)      # → SHA256 검증 후 blobs/로 atomic move
  def cancel_upload(uuid)                # → 임시 디렉토리 삭제
  def cleanup_stale_uploads(max_age: 1.hour) # → 오래된 upload 정리
end
```

### 설계 원칙

- **Content-addressable**: digest를 파일명으로 사용, 중복 저장 방지. cross-repo mount 시 파일 복사 불필요
- **서브디렉토리 분산**: digest 앞 2글자로 분산 (`sha256/aa/`, `sha256/bb/`)
- **Atomic write**: 임시 파일에 쓴 뒤 `File.rename`으로 이동
- **Digest 검증**: `finalize_upload` 시 실제 SHA256 계산하여 클라이언트 제출 값과 비교
- **중복 쓰기 방어**: `put` 시 이미 존재하면 skip (동일 digest = 동일 내용)
- **스트리밍 I/O**: 업로드/다운로드 모두 전체를 메모리에 올리지 않음

### 대용량 파일 I/O 최적화

**다운로드 (blob GET):**
- 기본: `send_file`로 Puma 스레드에서 직접 서빙
- 프로덕션 최적화: `Rack::Sendfile` 헤더를 통한 리버스 프록시 위임

```ruby
# config/environments/production.rb
config.action_dispatch.x_sendfile_header = ENV.fetch('SENDFILE_HEADER', nil)
# Nginx: 'X-Accel-Redirect', Apache: 'X-Sendfile'
```

Nginx 설정 시 Rails는 파일 경로만 헤더에 전달하고, 실제 파일 서빙은 Nginx가 처리하여 Puma 스레드가 즉시 해제된다.

**업로드 (blob PATCH/PUT):**
- `request.body` (Rack::Input)를 64KB chunk 단위로 스트리밍 읽기
- 전체를 메모리에 버퍼링하지 않음
- `Rack::TempfileReaper` 활성화하여 Rack 임시 파일 자동 정리

### 설정

```ruby
# config/application.rb
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
      get :export    # tar 다운로드 요청 (비동기)
    end
  end

  collection do
    post :import     # tar 업로드 (비동기)
  end
end

# Import/Export 상태 조회
resources :imports, only: [:show]
resources :exports, only: [:show]
```

### 페이지별 기능

**대시보드 / Repository 목록 (`GET /`)**
- Repository 카드 그리드: 이름, tag 수, 총 사이즈, 최종 업데이트
- 검색 (debounced), 정렬 (이름순, 최근 업데이트순, 사이즈순)

**Repository 상세 (`GET /repositories/:name`)**
- Tag 목록 테이블: tag 이름, digest(축약), 사이즈, 생성일
- `docker pull` 명령어 복사 버튼 — **실제 서버 호스트 포함**
- Tag 삭제, Repository 삭제 버튼

**Tag 상세 (`GET /repositories/:name/tags/:tag`)**
- Manifest 정보: digest, media_type, 사이즈
- Image Config: OS, architecture, env, cmd, entrypoint, labels
- Layer 목록: digest, 사이즈, 순서
- `docker pull` 명령어 복사 + tar export 버튼

**이미지 Import (`POST /repositories/import`)**
- `docker save` tar 파일 업로드
- **비동기 처리**: tar를 임시 경로에 저장 후 즉시 202 응답. `ProcessTarImportJob`에서 백그라운드 파싱/처리
- 진행률: Turbo Stream 브로드캐스트로 실시간 갱신
- Repository 이름/tag 자동 추출, 사용자 override 가능

**이미지 Export (`GET /repositories/:name/tags/:tag/export`)**
- **비동기 처리**: `PrepareExportJob`에서 `docker load` 호환 tar 생성
- 완료 후 Turbo Stream으로 다운로드 링크 브로드캐스트
- 생성된 tar는 다운로드 후 또는 1시간 후 GC Job에서 자동 정리

### Docker Pull 명령어 표시

웹 UI에서 복사하는 `docker pull` 명령어에 실제 서버 주소를 포함한다:

```ruby
# app/helpers/repositories_helper.rb
def docker_pull_command(repository_name, tag_name = 'latest')
  host = Rails.configuration.registry_host
  "docker pull #{host}/#{repository_name}:#{tag_name}"
end

# config/application.rb
config.registry_host = ENV.fetch('REGISTRY_HOST', 'localhost:3000')
```

표시 예시: `docker pull registry.mycompany.com:5000/team-a/backend:v1.2.3`

`REGISTRY_HOST`가 설정되지 않으면 `localhost:3000`으로 fallback하여 개발 환경에서도 동작한다.

### Import/Export 비동기 아키텍처

```
브라우저                      Rails                     Solid Queue
  │                            │                            │
  ├─ POST /import (tar) ──────►│                            │
  │                            ├─ tar → storage/tmp/imports/ │
  │                            ├─ Import 레코드 생성 (pending)│
  │                            ├─ ProcessTarImportJob 등록 ─►│
  │◄─ 202 + import status page ┤                            │
  │                            │                            ├─ tar 파싱
  │◄─ Turbo Stream (진행률) ───────────────────────────────── ├─ blob 저장
  │◄─ Turbo Stream (완료) ─────────────────────────────────── ├─ DB 레코드 생성
  │                            │                            │
```

### Import/Export Job 및 서비스

```ruby
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

class ImageImportService
  def call(tar_path, repository_name: nil, tag_name: nil)
    # tar 파싱 → manifest.json 읽기 → config/layer blob 추출 → DB 레코드 생성
  end
end

class ImageExportService
  def call(repository_name, tag_name, output_path:)
    # DB + 파일시스템에서 docker load 호환 tar 생성
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
| Turbo Frame/Stream | 유지 + import/export 브로드캐스트 추가 |

### 제거 대상

- `registries/` 뷰 전체
- Registry 선택 드롭다운
- `registry_selector_controller.js`, `registry_form_controller.js`

---

## 6. 서비스 레이어 및 에러 처리

### 서비스 구조

```
app/services/
├── blob_store.rb               # 파일시스템 스토리지
├── image_import_service.rb     # tar → registry import
├── image_export_service.rb     # registry → tar export
├── manifest_processor.rb       # manifest 파싱, 검증, 메타데이터 추출
└── digest_calculator.rb        # SHA256 digest 계산

app/jobs/
├── process_tar_import_job.rb   # import 비동기 처리
├── prepare_export_job.rb       # export 비동기 처리
└── cleanup_orphaned_blobs_job.rb  # GC
```

### ManifestProcessor

manifest PUT 시 핵심 처리:
1. JSON 파싱 및 V2 Schema 2 구조 검증
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
  before_action :set_registry_headers

  rescue_from Registry::BlobUnknown,       with: -> (e) { render_error('BLOB_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestUnknown,   with: -> (e) { render_error('MANIFEST_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestInvalid,   with: -> (e) { render_error('MANIFEST_INVALID', e.message, 400) }
  rescue_from Registry::BlobUploadUnknown, with: -> (e) { render_error('BLOB_UPLOAD_UNKNOWN', e.message, 404) }
  rescue_from Registry::NameUnknown,       with: -> (e) { render_error('NAME_UNKNOWN', e.message, 404) }
  rescue_from Registry::DigestMismatch,    with: -> (e) { render_error('DIGEST_INVALID', e.message, 400) }
  rescue_from Registry::Unsupported,       with: -> (e) { render_error('UNSUPPORTED', e.message, 415) }

  private

  def set_registry_headers
    response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
  end

  def render_error(code, message, status, detail: {})
    render json: { errors: [{ code: code, message: message, detail: detail }] }, status: status
  end
end
```

**웹 UI (브라우저 대상):**

```ruby
class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from Registry::Error, with: :registry_error
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

Tag나 Repository를 삭제해도, 해당 blob이 다른 manifest에서 공유 중일 수 있어 즉각 삭제가 불가능하다. 업로드 중단된 임시 파일, 만료된 export tar도 디스크에 잔존한다.

### 설계: 2단계 삭제

**1단계 — 참조 해제 (동기, 웹 요청 내):**
- Tag 삭제: `Tag` 레코드만 삭제. `Manifest`는 다른 tag가 참조 중일 수 있으므로 유지
- Repository 삭제: 해당 repo의 `Tag`, `Manifest`, `Layer` 삭제. `Blob`의 `references_count` 감소
- Manifest 삭제 (V2 API DELETE): `Tag` 참조 해제, `Layer` 삭제, `Blob`의 `references_count` 감소

**2단계 — 고아 리소스 정리 (비동기, Solid Queue):**

```ruby
class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :default

  def perform
    # 1. references_count == 0인 Blob 레코드 조회
    #    → 삭제 전 references_count 재확인 (race condition 방어)
    # 2. 해당 blob 파일을 디스크에서 삭제
    # 3. Blob DB 레코드 삭제
    # 4. Tag가 없는 Manifest 레코드 정리
    # 5. uploads/ 디렉토리에서 1시간 이상 된 임시 파일 정리
    # 6. tmp/exports/ 에서 1시간 이상 된 tar 파일 정리
    # 7. tmp/imports/ 에서 completed/failed 상태이고 24시간 이상 된 tar 파일 정리
  end
end
```

### 실행 주기

```yaml
# config/recurring.yml
cleanup_orphaned_blobs:
  class: CleanupOrphanedBlobsJob
  schedule: every 30 minutes
```

### 안전장치

- Blob 삭제 전 `references_count`를 DB에서 다시 확인 (race condition 방어)
- 삭제 순서: DB 레코드 삭제 → 파일 삭제 (DB 삭제 실패 시 파일 잔존은 안전, 역순은 위험)
- 삭제 대상이 많을 경우 batch 처리 (한번에 100개씩)

---

## 8. 동시성 (Concurrency) 방어

### 문제

Docker CLI는 push 시 여러 layer를 병렬 업로드한다. 동일 base image layer가 동시에 다른 요청으로 push될 수 있어 race condition이 발생한다.

### 방어 전략

**Blob 레코드 생성 — `create_or_find_by` 패턴:**

```ruby
# INSERT 먼저 시도 → unique index 충돌 시 SELECT
blob = Blob.create_or_find_by!(digest: digest) do |b|
  b.size = size
  b.content_type = content_type
end
```

`find_or_create_by`는 SELECT → INSERT 순서라 TOCTOU race가 있다. `create_or_find_by`는 INSERT를 먼저 시도하므로 unique index의 원자성을 활용한다.

**references_count 갱신 — 원자적 연산:**

```ruby
blob.increment!(:references_count)   # UPDATE SET references_count = references_count + 1
blob.decrement!(:references_count)   # UPDATE SET references_count = references_count - 1
```

Ruby 레벨이 아닌 DB 레벨 `SET col = col + 1`로 변환되어 원자성이 보장된다.

**파일시스템 중복 쓰기 방어:**

```ruby
def put(digest, io)
  target = path_for(digest)
  return if File.exist?(target)  # content-addressable: 동일 digest = 동일 내용
  # atomic write (임시 파일 → File.rename)
end
```

**Upload 세션 격리:**

각 `BlobUpload`는 고유 UUID를 가지므로 서로 다른 upload 세션 간 충돌 없음. 동일 blob을 두 클라이언트가 동시에 업로드해도 각자의 임시 디렉토리에서 독립 진행, `finalize_upload` 시 먼저 완료된 쪽이 저장하고 나중 쪽은 skip.

---

## 9. 테스트 전략

### RSpec 테스트 구조

```
spec/
├── models/                        # 모든 새 모델의 유효성, 관계 테스트
├── services/                      # BlobStore, ManifestProcessor, DigestCalculator,
│                                  #   ImageImportService, ImageExportService
├── jobs/                          # CleanupOrphanedBlobsJob, ProcessTarImportJob, PrepareExportJob
├── requests/
│   ├── v2/
│   │   ├── base_spec.rb           # GET /v2/ → 200, 헤더 확인
│   │   ├── catalog_spec.rb        # 목록, 페이지네이션, Link 헤더
│   │   ├── tags_spec.rb           # tag 목록, 페이지네이션
│   │   ├── manifests_spec.rb      # HEAD/GET/PUT/DELETE, media type 거부
│   │   ├── blobs_spec.rb          # HEAD/GET/DELETE
│   │   └── blob_uploads_spec.rb   # POST/PATCH/PUT, mount, monolithic
│   └── repositories_spec.rb       # 웹 UI CRUD, import/export
├── helpers/
│   └── repositories_helper_spec.rb # docker_pull_command 헬퍼
└── fixtures/
    ├── manifests/v2_schema2.json
    ├── configs/image_config.json
    └── tarballs/sample_image.tar
```

### 핵심 테스트 (반드시 통과)

1. **Blob upload full flow** — POST → PATCH → PUT 순서대로 blob이 저장되는지
2. **Cross-repo blob mount** — mount 성공 시 201 + 파일 미복사, 실패 시 202 fallback
3. **HEAD manifest** — digest, content-type, content-length 헤더 정확성
4. **Manifest PUT/GET** — push 후 pull이 정상 동작하는지
5. **Digest 검증** — 잘못된 digest 제출 시 거부
6. **BlobStore atomic write** — 불완전한 파일이 읽히지 않는지
7. **동시 blob 업로드** — create_or_find_by로 race condition 미발생
8. **Multi-arch manifest 거부** — manifest list/OCI media type push 시 415 응답

### 중요 테스트

9. **Catalog/Tags 페이지네이션** — n, last 파라미터, Link 헤더
10. **Import/Export round-trip** — tar 왕복 정합성 (비동기 Job 완료 후 검증)
11. **GC Job** — Tag 삭제 → references_count 감소 → GC 실행 → 디스크 정리
12. **웹 UI CRUD** — repository/tag 조회, 삭제
13. **Docker pull 명령어** — REGISTRY_HOST 반영 확인
14. **X-Accel-Redirect** — SENDFILE_HEADER 설정 시 헤더 응답 확인

### Docker CLI 통합 테스트

RSpec/Playwright 외에, 실제 Docker CLI로 push/pull을 수행하는 통합 테스트를 별도로 구성한다:

```bash
# test/integration/docker_cli_test.sh
#!/bin/bash
set -e

REGISTRY=localhost:3000

# 테스트 이미지 생성
echo "FROM alpine:latest" | docker build -t $REGISTRY/test-image:v1 -

# Push
docker push $REGISTRY/test-image:v1

# Pull (다른 이름으로)
docker pull $REGISTRY/test-image:v1
docker tag $REGISTRY/test-image:v1 $REGISTRY/test-image:v2
docker push $REGISTRY/test-image:v2

# 공유 layer mount 확인 (v2 push 시 base layer는 mount로 처리)

# Catalog 확인
curl -s http://$REGISTRY/v2/_catalog | jq .

# Tags 확인
curl -s http://$REGISTRY/v2/test-image/tags/list | jq .

# 정리
docker rmi $REGISTRY/test-image:v1 $REGISTRY/test-image:v2

echo "All Docker CLI integration tests passed."
```

이 스크립트는 CI에서 실제 Rails 서버를 띄운 상태로 실행한다. V2 스펙의 세부 호환성(헤더, content negotiation 등)은 단위 테스트만으로 잡기 어려우므로 실제 Docker CLI와의 통합 테스트가 필수다.

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
  def simulate_blob_mount(from_repo:, to_repo:, digest:)
end
```
