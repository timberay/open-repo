# RepoVista: Self-Hosted Docker Registry 전환 설계

## 개요

RepoVista를 외부 Docker Registry에 의존하는 클라이언트에서, 자체적으로 Docker Registry V2 API를 구현하여 `docker push`/`docker pull`을 직접 처리하는 독립 서비스로 전환한다.

### 대상 사용자 및 핵심 워크플로우

회사 내부 개발팀이 빌드용 Docker 이미지를 관리하는 용도:

1. 개발자가 툴체인 포함 빌드 이미지를 만들어 registry에 push
2. Jenkins/K8s/배치 스크립트에서 이미지를 pull하여 빌드 컨테이너 실행
3. 빌드 완료 후 컨테이너 종료
4. 프로젝트별 빌드 이미지 버전 관리 (이력 추적, 담당자, 사용량)

### 핵심 결정 사항

| 항목 | 결정 |
|------|------|
| 접근 방식 | Rails 단일 앱에서 Registry V2 API 직접 구현 |
| 스토리지 | 로컬 파일시스템 (content-addressable) |
| 인증 | 없음 (오픈, 내부 네트워크 전용) |
| 기존 외부 registry 기능 | 완전 제거 |
| Manifest 형식 | V2 Schema 2 단일 플랫폼만 (Multi-arch 명시적 거부) |
| 메타데이터 | DB에 풍부하게 저장 (layer, config, manifest, pull 이력, tag 변경 이력) |
| 웹 UI CRUD | 조회, 검색, 삭제, 설명 편집, tag 이력, 사용량 통계 + tar import/export |
| 비동기 처리 | Solid Queue (import/export, GC, retention) |

---

## 1. 전체 아키텍처

### 구조

```
RepoVista (단일 Rails 8 프로세스)
├── Registry V2 API (/v2/...)     ← Docker CLI 엔드포인트
├── Web UI (/, /repositories/...) ← 브라우저 엔드포인트
├── Solid Queue Worker            ← 백그라운드 Job (import/export/GC/retention)
├── SQLite DB                     ← 메타데이터 + 이벤트 로그
└── Local Filesystem Storage      ← Blob/Manifest 실제 데이터
     └── storage/
         ├── blobs/
         │   └── sha256/
         │       └── <aa>/<digest>
         ├── uploads/
         │   └── <uuid>/
         └── tmp/
             ├── imports/
             └── exports/
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
  → GET  /v2/myimage/manifests/latest          (manifest 조회 + pull 카운터 증가)
  → HEAD /v2/myimage/blobs/sha256:...          (blob 존재 확인)
  → GET  /v2/myimage/blobs/sha256:...          (blob 다운로드)
```

**브라우저 → Web UI:**

```
GET /                                        → 대시보드 (repo 목록 + 사용량 통계)
GET /repositories/:name                      → tag 목록 + 상세 정보 + 이력
GET /repositories/:name/tags/:tag            → tag 상세 + layer diff 비교
PATCH /repositories/:name                    → repository 설명/담당자 편집
DELETE /repositories/:name/tags/:tag         → tag 삭제
POST /repositories/import                    → tar 업로드 (비동기)
GET /repositories/:name/tags/:tag/export     → tar 다운로드 (비동기)
```

### 환경 설정

```bash
STORAGE_PATH=/var/data/registry    # Blob 스토리지 경로 (기본: Rails.root/storage/registry)
REGISTRY_HOST=registry.mycompany.com:5000  # Web UI에서 docker pull 명령어에 표시할 호스트
SENDFILE_HEADER=                   # 프로덕션: 'X-Accel-Redirect' (Nginx) 또는 'X-Sendfile' (Apache)
PUMA_THREADS=16                    # 동시 pull 대응 (기본 5 → 16 권장)
PUMA_WORKERS=2                     # 프로덕션 워커 수
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
# repositories — 이미지 저장소
create_table :repositories do |t|
  t.string :name, null: false           # e.g. "build-images/cpp-toolchain"
  t.text :description                   # 사용자 입력 설명 (용도, 포함 도구 등)
  t.string :maintainer                  # 담당자 이름/팀
  t.integer :tags_count, default: 0     # counter cache
  t.bigint :total_size, default: 0      # bytes
  t.timestamps
  t.index :name, unique: true
end

# tags — 이미지 태그
create_table :tags do |t|
  t.references :repository, null: false, foreign_key: true
  t.references :manifest, null: false, foreign_key: true
  t.string :name, null: false           # e.g. "latest", "v1.0.0"
  t.timestamps
  t.index [:repository_id, :name], unique: true
end

# manifests — 이미지 manifest
create_table :manifests do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :digest, null: false         # sha256:abcdef...
  t.string :media_type, null: false     # application/vnd.docker.distribution.manifest.v2+json
  t.text :payload, null: false          # manifest JSON 전체
  t.bigint :size, null: false           # manifest 자체 사이즈
  t.string :config_digest               # config blob digest
  t.string :architecture                # e.g. "amd64"
  t.string :os                          # e.g. "linux"
  t.text :docker_config                 # config blob JSON (env, cmd, entrypoint 등)
  t.integer :pull_count, default: 0     # pull 횟수 카운터
  t.datetime :last_pulled_at            # 마지막 pull 시간
  t.timestamps
  t.index :digest, unique: true
  t.index [:repository_id, :digest]
  t.index :last_pulled_at               # retention policy 쿼리용
end

# layers — manifest ↔ blob 조인 테이블
create_table :layers do |t|
  t.references :manifest, null: false, foreign_key: true
  t.references :blob, null: false, foreign_key: true
  t.integer :position, null: false      # layer 순서
  t.index [:manifest_id, :position], unique: true
  t.index [:manifest_id, :blob_id], unique: true
end

# blobs — content-addressable 바이너리 데이터
create_table :blobs do |t|
  t.string :digest, null: false         # sha256:abcdef...
  t.bigint :size, null: false           # bytes
  t.string :content_type
  t.integer :references_count, default: 0  # manifest 참조 수 (GC 판별)
  t.timestamps
  t.index :digest, unique: true
end

# blob_uploads — 진행 중인 chunked upload
create_table :blob_uploads do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :uuid, null: false
  t.bigint :byte_offset, default: 0
  t.timestamps
  t.index :uuid, unique: true
end

# tag_events — tag 변경 이력 (audit log)
create_table :tag_events do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :tag_name, null: false       # tag 이름
  t.string :action, null: false         # 'create', 'update', 'delete'
  t.string :previous_digest             # 이전 manifest digest (update/delete 시)
  t.string :new_digest                  # 새 manifest digest (create/update 시)
  t.string :actor                       # 변경 수행자 (향후 인증 추가 시 활용, 현재는 'anonymous')
  t.datetime :occurred_at, null: false
  t.index [:repository_id, :tag_name]
  t.index :occurred_at
end

# pull_events — pull 상세 이력
create_table :pull_events do |t|
  t.references :manifest, null: false, foreign_key: true
  t.references :repository, null: false, foreign_key: true
  t.string :tag_name                    # pull 시 사용한 tag (digest로 pull하면 nil)
  t.string :user_agent                  # Docker CLI / containerd / 브라우저 등
  t.string :remote_ip                   # 요청자 IP
  t.datetime :occurred_at, null: false
  t.index [:repository_id, :occurred_at]
  t.index [:manifest_id, :occurred_at]
  t.index :occurred_at                  # retention policy 쿼리용
end

# imports — 비동기 tar import 상태 추적
create_table :imports do |t|
  t.string :status, null: false, default: 'pending'
  t.string :repository_name
  t.string :tag_name
  t.string :tar_path
  t.text :error_message
  t.integer :progress, default: 0      # 0-100
  t.timestamps
end

# exports — 비동기 tar export 상태 추적
create_table :exports do |t|
  t.references :repository, null: false, foreign_key: true
  t.string :tag_name, null: false
  t.string :status, null: false, default: 'pending'
  t.string :output_path
  t.text :error_message
  t.timestamps
end
```

### 모델 관계

```
Repository 1──N Tag
Repository 1──N Manifest
Repository 1──N TagEvent
Manifest   1──N Layer
Manifest   1──N PullEvent
Layer      N──1 Blob
Tag        N──1 Manifest
```

### 설계 원칙

- Blob은 content-addressable: 같은 digest는 하나만 저장, 여러 manifest/repository가 공유
- `references_count`: blob 참조 카운트 (GC 대상 판별)
- `payload`: manifest JSON 전체를 DB에 보관하여 파일시스템 없이도 빠른 조회
- `docker_config`: 이미지 config(env, cmd, entrypoint, labels 등)를 DB에 캐싱
- `pull_count` + `last_pulled_at`: manifest 레벨 사용량 추적 (경량 카운터)
- `pull_events`: 상세 pull 이력 (누가, 언제, 어디서)
- `tag_events`: tag 변경 감사 로그 (생성/갱신/삭제 + 이전/이후 digest)

---

## 3. Docker Registry V2 API

### 엔드포인트

```ruby
scope '/v2', defaults: { format: :json } do
  get '/', to: 'v2/base#index'

  get '/_catalog', to: 'v2/catalog#index'
  get '/*name/tags/list', to: 'v2/tags#index'

  get    '/*name/manifests/:reference', to: 'v2/manifests#show'
  head   '/*name/manifests/:reference', to: 'v2/manifests#show'
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
    handle_blob_mount
  elsif params[:digest].present?
    handle_monolithic_upload
  else
    handle_start_upload
  end
end
```

mount는 파일을 복사하지 않는다. content-addressable 스토리지이므로 동일 digest = 동일 파일이다. DB에서 참조 카운트만 증가시키면 된다. mount 성공 시 `201 Created`, 실패 시 일반 upload로 fallback (`202 Accepted`).

### HEAD Manifest

Docker CLI는 `pull` 전에 반드시 `HEAD /v2/<name>/manifests/<reference>`를 호출한다.

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
    # Pull 카운터 증가 + 이벤트 기록 (GET만, HEAD는 제외)
    record_pull_event(manifest)
    render json: manifest.payload, content_type: manifest.media_type
  end
end
```

`reference`는 tag 이름(`latest`) 또는 digest(`sha256:abc...`) 둘 다 가능:
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

### Pull 이벤트 기록

manifest GET 시 경량 카운터 + 상세 이력을 동시에 기록:

```ruby
def record_pull_event(manifest)
  # 경량 카운터 (원자적 증가, 매 요청)
  manifest.increment!(:pull_count)
  manifest.update_column(:last_pulled_at, Time.current)

  # 상세 이력 (별도 레코드)
  PullEvent.create!(
    manifest: manifest,
    repository: manifest.repository,
    tag_name: params[:reference].start_with?('sha256:') ? nil : params[:reference],
    user_agent: request.user_agent,
    remote_ip: request.remote_ip,
    occurred_at: Time.current
  )
end
```

### Manifest PUT Flow (+ Tag 이벤트 기록)

1. Content-Type 검증 (미지원 media type → 415 거부)
2. Manifest JSON 파싱 및 V2 Schema 2 구조 검증
3. 참조된 blob들 존재 확인
4. Config blob에서 이미지 메타데이터 추출 (os, architecture, env, cmd 등)
5. Manifest 레코드 생성/갱신
6. Tag 레코드 생성/갱신 (reference가 tag 이름인 경우)
7. **Tag 이벤트 기록** (create 또는 update + 이전 digest)
8. Layer 레코드들 생성
9. Repository의 `total_size` 갱신

```ruby
# ManifestProcessor 내 tag 이벤트 기록
def record_tag_event(repository, tag_name, old_manifest, new_manifest)
  TagEvent.create!(
    repository: repository,
    tag_name: tag_name,
    action: old_manifest ? 'update' : 'create',
    previous_digest: old_manifest&.digest,
    new_digest: new_manifest.digest,
    actor: 'anonymous',  # 현재 인증 없음
    occurred_at: Time.current
  )
end
```

### Catalog/Tags 페이지네이션

V2 스펙의 `?n=<count>&last=<last_item>` 페이지네이션을 지원한다.

```ruby
# V2::CatalogController#index
def index
  n = (params[:n] || 100).to_i.clamp(1, 1000)
  scope = Repository.order(:name)
  scope = scope.where('name > ?', params[:last]) if params[:last].present?
  repos = scope.limit(n + 1).pluck(:name)

  if repos.size > n
    repos.pop
    response.headers['Link'] = "</v2/_catalog?n=#{n}&last=#{repos.last}>; rel=\"next\""
  end

  render json: { repositories: repos }
end
```

Tags 목록도 동일한 패턴. `Link` 헤더 `rel="next"`로 Docker CLI가 자동 페이지네이션.

### Multi-Architecture Manifest 거부 정책

| Media Type | 처리 |
|---|---|
| `application/vnd.docker.distribution.manifest.v2+json` | **지원** |
| `application/vnd.docker.distribution.manifest.list.v2+json` | **거부 (415)** |
| `application/vnd.oci.image.manifest.v1+json` | **거부 (415)** |
| `application/vnd.oci.image.index.v1+json` | **거부 (415)** |

에러 메시지에 해결 방법을 포함:
```
"Use: docker build --platform linux/amd64 -t <image> ."
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

- `Docker-Distribution-API-Version: registry/2.0` (모든 응답)
- `Docker-Content-Digest` (manifest/blob)
- `Content-Length`, `Content-Type`
- `Location`, `Range`, `Docker-Upload-UUID` (upload)

---

## 4. 파일시스템 스토리지

### 디렉토리 구조

```
storage/
├── blobs/
│   └── sha256/
│       ├── aa/
│       │   └── aabbccdd...full_digest
│       └── ...
├── uploads/
│   ├── <uuid>/
│   │   ├── data
│   │   └── startedat
│   └── ...
└── tmp/
    ├── imports/
    └── exports/
```

### BlobStore 서비스

```ruby
class BlobStore
  def initialize(root_path = Rails.configuration.storage_path)

  # Blob 관리
  def get(digest)                        # → IO stream
  def put(digest, io)                    # → atomic write (이미 존재하면 skip)
  def exists?(digest)                    # → boolean
  def delete(digest)                     # → 파일 삭제
  def path_for(digest)                   # → 절대 경로
  def size(digest)                       # → File.size

  # Upload 세션 관리
  def create_upload(uuid)                # → 임시 디렉토리 + startedat 생성
  def append_upload(uuid, io)            # → 64KB chunk 단위 스트리밍 append
  def upload_size(uuid)                  # → 현재 byte offset
  def finalize_upload(uuid, digest)      # → SHA256 검증 후 blobs/로 atomic move
  def cancel_upload(uuid)                # → 임시 디렉토리 삭제
  def cleanup_stale_uploads(max_age: 1.hour)
end
```

### 설계 원칙

- **Content-addressable**: digest = 파일명, 중복 방지, cross-repo mount 시 복사 불필요
- **서브디렉토리 분산**: digest 앞 2글자로 분산
- **Atomic write**: 임시 파일 → `File.rename`
- **Digest 검증**: finalize 시 실제 SHA256 계산하여 비교
- **중복 쓰기 방어**: 이미 존재하면 skip
- **스트리밍 I/O**: 전체를 메모리에 올리지 않음

### 대용량 파일 I/O 최적화

**다운로드:**
```ruby
# config/environments/production.rb
config.action_dispatch.x_sendfile_header = ENV.fetch('SENDFILE_HEADER', nil)
# Nginx: 'X-Accel-Redirect' → Puma 스레드 즉시 해제
```

**업로드:**
- `request.body` 64KB chunk 단위 스트리밍
- `Rack::TempfileReaper` 활성화

### 설정

```ruby
config.storage_path = ENV.fetch('STORAGE_PATH', Rails.root.join('storage', 'registry'))
```

---

## 5. 웹 UI 및 CRUD

### 라우팅

```ruby
root 'repositories#index'

resources :repositories, only: [:index, :show, :update, :destroy], param: :name,
                         constraints: { name: /[^\/]+(?:\/[^\/]+)*/ } do
  resources :tags, only: [:show, :destroy], param: :name do
    member do
      get :export         # tar 다운로드 (비동기)
      get :history        # tag 변경 이력
      get :compare        # 다른 tag와 layer diff
    end
  end

  member do
    get :pull_stats       # pull 사용량 통계
    get :dependency_graph # 이미지 의존 관계
  end

  collection do
    post :import          # tar 업로드 (비동기)
  end
end

resources :imports, only: [:show]
resources :exports, only: [:show]
```

### 페이지별 기능

**대시보드 / Repository 목록 (`GET /`)**
- Repository 카드 그리드: 이름, **설명**, 담당자, tag 수, 총 사이즈, 최종 업데이트
- 검색: 이름 + 설명 + 담당자로 검색 (debounced)
- 정렬: 이름순, 최근 업데이트순, 사이즈순, **최근 pull순**, **pull 횟수순**
- 필터: **"N일간 pull 없는 이미지"** 필터 (사용하지 않는 이미지 식별)

**Repository 상세 (`GET /repositories/:name`)**
- **설명/담당자 편집**: 인라인 편집 (Turbo Frame). 이미지 용도, 포함 도구, 담당 팀 기록
- Tag 목록 테이블: tag 이름, digest(축약), 사이즈, 생성일, **pull 횟수**, **마지막 pull**
- `docker pull` 명령어 복사 버튼 — **실제 서버 호스트 포함**
- Tag 삭제, Repository 삭제 버튼
- **Pull 사용량 차트**: 기간별 pull 횟수 그래프 (최근 30일)

**Tag 상세 (`GET /repositories/:name/tags/:tag`)**
- Manifest 정보: digest, media_type, 사이즈, pull 횟수, 마지막 pull
- Image Config: OS, architecture, env, cmd, entrypoint, labels
- Layer 목록: digest, 사이즈, 순서
- `docker pull` 명령어 복사 + tar export 버튼
- **변경 이력**: 이 tag가 가리킨 manifest digest의 변천사 (tag_events 기반)
  - "2026-04-10: sha256:abc... → sha256:def... 으로 갱신"
  - "2026-04-01: 최초 생성 (sha256:abc...)"

**Tag 변경 이력 (`GET /repositories/:name/tags/:tag/history`)**
- tag_events 테이블 기반 시간순 이력
- 각 이벤트: 시간, action(create/update/delete), 이전 digest, 새 digest
- 이전 manifest의 config 정보도 함께 표시 (무엇이 바뀌었는지 파악)

**Tag 간 비교 (`GET /repositories/:name/tags/:tag/compare?with=other_tag`)**
- 두 tag의 manifest를 비교하여:
  - 공통 layer (동일 digest) — 변경 없음으로 표시
  - 추가된 layer — 새 tag에만 있는 layer
  - 제거된 layer — 이전 tag에만 있던 layer
- Image Config diff: env, cmd, entrypoint 차이점 하이라이트
- 총 사이즈 변화량 표시

**이미지 의존 관계 (`GET /repositories/:name/dependency_graph`)**
- 현재 repository의 manifest layer들을 분석하여, 동일 layer를 공유하는 다른 repository 식별
- "이 repository가 삭제되면 영향받을 수 있는 다른 repository" 목록
- layer 공유 비율 표시 (e.g. "qa-images/cpp-test와 layer 80% 공유")

**Pull 사용량 통계 (`GET /repositories/:name/pull_stats`)**
- 기간별 pull 횟수 (일간/주간/월간)
- pull_events 기반: 요청 IP별, user_agent별 분류
- "어떤 Jenkins agent가 이 이미지를 가장 많이 pull하는가" 파악 가능

**이미지 Import (`POST /repositories/import`)**
- `docker save` tar 파일 업로드
- 비동기: tar 임시 저장 → 즉시 202 → `ProcessTarImportJob`에서 처리
- Turbo Stream 진행률 브로드캐스트
- Repository 이름/tag 자동 추출, 사용자 override 가능

**이미지 Export (`GET /repositories/:name/tags/:tag/export`)**
- 비동기: `PrepareExportJob`에서 docker load 호환 tar 생성
- Turbo Stream으로 다운로드 링크 브로드캐스트
- 1시간 후 GC Job에서 자동 정리

### Docker Pull 명령어 표시

```ruby
# app/helpers/repositories_helper.rb
def docker_pull_command(repository_name, tag_name = 'latest')
  host = Rails.configuration.registry_host
  "docker pull #{host}/#{repository_name}:#{tag_name}"
end

# config/application.rb
config.registry_host = ENV.fetch('REGISTRY_HOST', 'localhost:3000')
```

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
```

### 재활용 컴포넌트

| 컴포넌트 | 변경 |
|---|---|
| `search_controller.js` | 변경 없음 |
| `clipboard_controller.js` | 변경 없음 |
| `theme_controller.js` | 변경 없음 |
| TailwindCSS 테마 | 유지 |
| Turbo Frame/Stream | 유지 + 확장 |

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
├── manifest_processor.rb       # manifest 파싱, 검증, 메타데이터 추출, 이벤트 기록
├── digest_calculator.rb        # SHA256 digest 계산
├── tag_diff_service.rb         # 두 tag 간 layer/config 비교
└── dependency_analyzer.rb      # 이미지 간 layer 공유 분석

app/jobs/
├── process_tar_import_job.rb   # import 비동기 처리
├── prepare_export_job.rb       # export 비동기 처리
├── cleanup_orphaned_blobs_job.rb  # GC
├── enforce_retention_policy_job.rb # 자동 만료 정책
└── prune_old_events_job.rb     # 오래된 pull_events 정리
```

### TagDiffService

두 manifest의 layer 구성과 config를 비교:

```ruby
class TagDiffService
  def call(manifest_a, manifest_b)
    # Returns:
    # {
    #   common_layers: [...],      # 양쪽 모두에 있는 layer digests
    #   added_layers: [...],       # b에만 있는 layers
    #   removed_layers: [...],     # a에만 있던 layers
    #   config_diff: {             # config 변경점
    #     env: { added: [...], removed: [...] },
    #     cmd: { before: ..., after: ... },
    #     ...
    #   },
    #   size_delta: 12345          # 사이즈 변화 (bytes)
    # }
  end
end
```

### DependencyAnalyzer

이미지 간 layer 공유 관계 분석:

```ruby
class DependencyAnalyzer
  def call(repository)
    # 1. 해당 repo의 모든 manifest에서 layer digest 수집
    # 2. 같은 layer digest를 사용하는 다른 repository 조회
    # 3. 공유 비율 계산
    # Returns:
    # [
    #   { repository: "qa-images/cpp-test", shared_layers: 5, total_layers: 7, ratio: 0.71 },
    #   ...
    # ]
  end
end
```

### ManifestProcessor

manifest PUT 시 핵심 처리:
1. JSON 파싱 및 V2 Schema 2 구조 검증
2. 참조 blob 존재 확인
3. Config blob에서 메타데이터 추출
4. Manifest/Tag/Layer 레코드 생성/갱신
5. **TagEvent 기록** (create/update + 이전/이후 digest)
6. Repository `total_size` 재계산

### 에러 처리

**V2 API:**
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
end
```

**웹 UI:**
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

## 7. Garbage Collection 및 Retention Policy

### GC: 2단계 삭제

**1단계 — 참조 해제 (동기):**
- Tag 삭제: Tag 레코드 삭제 + **TagEvent 기록** (action: 'delete')
- Repository 삭제: Tag, Manifest, Layer 삭제. Blob references_count 감소
- Manifest 삭제 (V2 API): Tag 참조 해제, Layer 삭제, Blob references_count 감소

**2단계 — 고아 리소스 정리 (비동기):**

```ruby
class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :default

  def perform
    # 1. references_count == 0인 Blob → 재확인 후 디스크+DB 삭제
    # 2. Tag 없는 Manifest 정리
    # 3. uploads/ 1시간 이상 된 임시 파일 정리
    # 4. tmp/exports/ 1시간 이상 된 tar 정리
    # 5. tmp/imports/ completed/failed + 24시간 이상 된 tar 정리
  end
end
```

### Retention Policy: 자동 만료

사용하지 않는 오래된 이미지를 자동 식별하고 정리:

```ruby
class EnforceRetentionPolicyJob < ApplicationJob
  queue_as :default

  def perform
    policy = RetentionPolicy.current
    return unless policy.enabled?

    # last_pulled_at이 threshold 이전이고 pull_count가 낮은 manifest의 tag 삭제
    # (latest tag는 자동 삭제 대상에서 제외)
    stale_manifests = Manifest
      .where('last_pulled_at < ? OR last_pulled_at IS NULL', policy.days_without_pull.days.ago)
      .where('pull_count < ?', policy.min_pull_count)

    stale_manifests.find_each do |manifest|
      manifest.tags.where.not(name: 'latest').find_each do |tag|
        tag.destroy
        TagEvent.create!(
          repository: manifest.repository,
          tag_name: tag.name,
          action: 'delete',
          previous_digest: manifest.digest,
          actor: 'retention-policy',
          occurred_at: Time.current
        )
      end
    end
  end
end
```

### Retention Policy 설정

```ruby
# DB에 저장 또는 환경변수로 설정
# 초기에는 환경변수로 단순하게:
RETENTION_ENABLED=false              # 기본 비활성
RETENTION_DAYS_WITHOUT_PULL=90       # N일간 pull 없으면 대상
RETENTION_MIN_PULL_COUNT=5           # 최소 N회 이상 pull된 이미지는 제외
RETENTION_PROTECT_LATEST=true        # latest tag 보호
```

### 오래된 이벤트 정리

pull_events가 무한 증가하지 않도록 오래된 레코드 정리:

```ruby
class PruneOldEventsJob < ApplicationJob
  queue_as :default

  def perform
    # 90일 이상 된 pull_events 삭제 (pull_count/last_pulled_at은 유지)
    PullEvent.where('occurred_at < ?', 90.days.ago).in_batches.delete_all
  end
end
```

### 실행 주기

```yaml
# config/recurring.yml
cleanup_orphaned_blobs:
  class: CleanupOrphanedBlobsJob
  schedule: every 30 minutes

enforce_retention_policy:
  class: EnforceRetentionPolicyJob
  schedule: every day at 3am

prune_old_events:
  class: PruneOldEventsJob
  schedule: every day at 4am
```

### 안전장치

- Blob 삭제 전 references_count 재확인
- 삭제 순서: DB → 파일 (역순은 위험)
- Batch 처리 (100개씩)
- Retention policy에서 latest tag 보호
- Retention은 기본 비활성, 명시적으로 활성화해야 동작

---

## 8. 동시성 (Concurrency) 방어

### Blob 레코드 — `create_or_find_by`:

```ruby
blob = Blob.create_or_find_by!(digest: digest) do |b|
  b.size = size
  b.content_type = content_type
end
```

### references_count — 원자적 연산:

```ruby
blob.increment!(:references_count)   # DB: SET references_count = references_count + 1
blob.decrement!(:references_count)
```

### pull_count — 원자적 연산:

```ruby
manifest.increment!(:pull_count)     # DB: SET pull_count = pull_count + 1
```

### 파일시스템 — 이미 존재하면 skip:

```ruby
def put(digest, io)
  target = path_for(digest)
  return if File.exist?(target)
  # atomic write
end
```

### Upload 세션 격리:

각 BlobUpload는 고유 UUID. 동일 blob 동시 업로드해도 독립 진행, finalize 시 먼저 완료된 쪽이 저장.

---

## 9. 프로덕션 배포 가이드

### Puma 설정

Jenkins/K8s에서 동시 다수 pull이 발생하므로 기본값(5 threads)으로는 부족:

```ruby
# config/puma.rb
threads_count = ENV.fetch("PUMA_THREADS", 16)
threads threads_count, threads_count

workers ENV.fetch("PUMA_WORKERS", 2)
```

X-Accel-Redirect 사용 시 blob 다운로드가 Puma 스레드를 점유하지 않으므로 스레드 수를 줄일 수 있다.

### Docker Daemon 설정 (클라이언트 측)

HTTP registry를 사용하려면 Docker daemon에 insecure-registries 설정 필요:

```json
// /etc/docker/daemon.json (모든 Docker 클라이언트 머신)
{
  "insecure-registries": ["registry.mycompany.com:5000"]
}
```

설정 후 `systemctl restart docker` 필요.

### Kubernetes containerd 설정

K8s 노드에서 HTTP registry 접속을 위한 containerd 설정:

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.mycompany.com:5000"]
  endpoint = ["http://registry.mycompany.com:5000"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."registry.mycompany.com:5000".tls]
  insecure_skip_verify = true
```

### Nginx 리버스 프록시 (권장)

```nginx
server {
  listen 5000;
  server_name registry.mycompany.com;

  client_max_body_size 0;  # 무제한 (대용량 blob)

  location /v2/ {
    proxy_pass http://localhost:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_request_buffering off;   # 스트리밍 업로드
    proxy_buffering off;           # 스트리밍 다운로드
  }

  # X-Accel-Redirect로 파일 직접 서빙
  location /internal-storage/ {
    internal;
    alias /var/data/registry/blobs/;
  }
}
```

### 웹 UI 도움말 페이지

위 Docker/K8s/Nginx 설정 가이드를 웹 UI 내 도움말 페이지(`GET /help`)에서도 제공한다. REGISTRY_HOST 값을 자동으로 치환하여 복사 가능한 설정 코드를 표시:

```ruby
# app/controllers/help_controller.rb
class HelpController < ApplicationController
  def show
    @registry_host = Rails.configuration.registry_host
  end
end
```

---

## 10. 테스트 전략

### RSpec 테스트 구조

```
spec/
├── models/                        # Repository, Tag, Manifest, Blob, Layer,
│                                  #   BlobUpload, TagEvent, PullEvent, Import, Export
├── services/
│   ├── blob_store_spec.rb
│   ├── manifest_processor_spec.rb # tag_event 기록 포함
│   ├── digest_calculator_spec.rb
│   ├── image_import_service_spec.rb
│   ├── image_export_service_spec.rb
│   ├── tag_diff_service_spec.rb
│   └── dependency_analyzer_spec.rb
├── jobs/
│   ├── cleanup_orphaned_blobs_job_spec.rb
│   ├── enforce_retention_policy_job_spec.rb
│   └── prune_old_events_job_spec.rb
├── requests/
│   ├── v2/
│   │   ├── base_spec.rb
│   │   ├── catalog_spec.rb        # 페이지네이션
│   │   ├── tags_spec.rb           # 페이지네이션
│   │   ├── manifests_spec.rb      # HEAD/GET/PUT/DELETE, pull 카운터, tag 이벤트
│   │   ├── blobs_spec.rb          # HEAD/GET/DELETE
│   │   └── blob_uploads_spec.rb   # POST/PATCH/PUT, mount, monolithic
│   ├── repositories_spec.rb       # CRUD + 설명 편집
│   └── help_spec.rb               # 도움말 페이지
├── helpers/
│   └── repositories_helper_spec.rb
└── fixtures/
    ├── manifests/v2_schema2.json
    ├── configs/image_config.json
    └── tarballs/sample_image.tar
```

### 핵심 테스트

1. **Blob upload full flow** — POST → PATCH → PUT
2. **Cross-repo blob mount** — 201 성공 + 파일 미복사, 202 fallback
3. **HEAD manifest** — digest, content-type, content-length 헤더
4. **Manifest PUT/GET** — push/pull 정상 동작
5. **Digest 검증** — 잘못된 digest 거부
6. **BlobStore atomic write** — 불완전 파일 방지
7. **동시 blob 업로드** — create_or_find_by race condition 방어
8. **Multi-arch manifest 거부** — 415 응답
9. **Pull 카운터** — GET manifest 시 pull_count 증가, HEAD 시 미증가
10. **Tag 이벤트** — push 시 create/update 이벤트, delete 시 delete 이벤트

### 중요 테스트

11. **Catalog/Tags 페이지네이션** — n, last 파라미터, Link 헤더
12. **Import/Export round-trip** — tar 왕복 정합성
13. **GC Job** — references_count 0 → 디스크 정리
14. **Retention Policy** — stale manifest tag 삭제, latest 보호
15. **Tag Diff** — layer 비교, config diff
16. **Dependency Analyzer** — layer 공유 관계 식별
17. **Pull Events** — user_agent, remote_ip 기록
18. **Repository 설명 편집** — PATCH 동작
19. **Docker pull 명령어** — REGISTRY_HOST 반영
20. **X-Accel-Redirect** — SENDFILE_HEADER 설정 시 헤더 응답

### Docker CLI 통합 테스트

```bash
# test/integration/docker_cli_test.sh
#!/bin/bash
set -e

REGISTRY=localhost:3000

# 빌드 이미지 push
echo "FROM alpine:latest" | docker build -t $REGISTRY/test-image:v1 -
docker push $REGISTRY/test-image:v1

# 같은 base의 다른 이미지 push (mount 발생)
echo -e "FROM alpine:latest\nRUN echo hello" | docker build -t $REGISTRY/test-image:v2 -
docker push $REGISTRY/test-image:v2

# Pull 확인
docker rmi $REGISTRY/test-image:v1
docker pull $REGISTRY/test-image:v1

# latest tag 갱신
docker tag $REGISTRY/test-image:v2 $REGISTRY/test-image:latest
docker push $REGISTRY/test-image:latest

# API 확인
curl -s http://$REGISTRY/v2/_catalog | jq .
curl -s http://$REGISTRY/v2/test-image/tags/list | jq .
curl -sI http://$REGISTRY/v2/test-image/manifests/v1  # HEAD 확인

# 정리
docker rmi $REGISTRY/test-image:v1 $REGISTRY/test-image:v2 $REGISTRY/test-image:latest 2>/dev/null || true

echo "All Docker CLI integration tests passed."
```

### E2E 테스트 (Playwright)

유지/수정: `repository-list`, `tag-details`, `search`, `dark-mode`
신규: `image-import`, `image-export`, `tag-history`, `tag-compare`, `pull-stats`, `repository-edit`, `help-page`
제거: `registry-management`, `registry-switching`, `registry-dropdown`

### 테스트 헬퍼

```ruby
module RegistryTestHelpers
  def create_test_blob(content = SecureRandom.random_bytes(1024))
  def build_test_manifest(config_digest:, layer_digests:)
  def simulate_docker_push(repo_name, tag_name)
  def simulate_blob_mount(from_repo:, to_repo:, digest:)
  def create_tag_event(repo, tag_name, action, old_digest: nil, new_digest: nil)
  def create_pull_events(manifest, count:)
end
```
