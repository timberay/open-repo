# Technical Design: Registry Auth (Stage 0/1/2)

**Status**: APPROVED (Phase 3 technical design) — Stage 1 auth scheme 변경 (2026-04-23): JWT Bearer → PAT Basic auth (D9 참조).
**Generated**: 2026-04-23 via `/superpowers:brainstorming`
**Upstream product design**: `~/.gstack/projects/timberay-open-repo/tonny-chore-design-review-polish-design-20260423-103952.md`
**Upstream test plan**: `~/.gstack/projects/timberay-open-repo/tonny-main-eng-review-test-plan-20260423-111911.md`
**Approach**: C (OmniAuth + PAT + Repository Ownership), confirmed over A/B
**Framework**: Minitest (RSpec→Minitest 포팅은 `TODOS.md [P0]` 로 선행)

## Scope

본 문서는 승인된 product design 의 Stage 0/1/2 를 구현자가 막힘 없이 짤 수 있는 수준의 기술 스펙이다. **why 논쟁은 끝났다 — how 만 확정**.

**포함**:
1. Stage 별 마이그레이션 파일 정확한 컬럼/인덱스/제약 스펙
2. 신규 서비스·concern 의 메서드 시그니처
3. Docker Registry V2 challenge/response HTTP 예시 (Basic auth)
4. `ManifestProcessor.call(..., actor:)` 변경 전/후 diff
5. PAT 검증 + ENV 설정
6. Minitest 파일 레이아웃
7. 크리티컬 갭 3건의 구체 테스트 셋업
8. Stage 0→1→2 배포 순서 + rollback 절차

**제외 (이미 결정됨)**:
- Approach A/B 재검토
- Full RBAC 전개 (ownership 모델 확정)
- 인증 프레임워크 선택 (OmniAuth 확정)
- Multi-arch / Private visibility (defer 확정)
- JWT Bearer / RSA 키쌍 / `/v2/token` (D9: Basic auth 채택으로 폐기)

## Confirmed Decisions (Phase 3 brainstorming 에서 확정)

| # | 결정 | 영향 |
|---|---|---|
| D1 | PAT 스키마에 `kind` 컬럼 추가 (`cli` / `ci`). `cli` 기본 만료 90일, `ci` 는 `expires_at = NULL` 허용 | `personal_access_tokens` 스키마 |
| D2 | First-pusher-owner (GitHub 스타일): V2 push 가 repo 자동 생성, 생성자가 owner | `V2::BlobUploadsController#create` |
| D3 | Stage 당 별도 long-lived feature branch + 순차 main 머지. RSpec→Minitest 는 선행 브랜치 | 브랜치 전략 |
| D4 | Import job actor 는 enqueue 시점에 `actor_email` 을 job arg 로 직렬화, fallback `"system:import"` | `ProcessTarImportJob` + `ImageImportService` |
| D5 | Anonymous pull gate: HTTP GET/HEAD + `{base#index, catalog#index, tags#index, manifests#show, blobs#show}` + `anonymous_pull_enabled` → 인증 스킵. 나머지 모두 인증 필수 | `V2::BaseController#authenticate_v2_basic!` |
| D6 | `V2::BlobsController#destroy` 는 Stage 2 에서 admin-only (`authorize_for!(:delete)`) | admin-only 경로 |
| D7 | `ManifestProcessor.call(..., actor:)` 는 **required keyword, default 없음** | TDD 에서 누락 즉시 ArgumentError |
| D8 | `TagsController#destroy` 는 Stage 1 에서 actor 실명화, Stage 2 에서 `authorize_for!(:delete)` 추가 | 2-step 진화 |
| **D9** | **Stage 1 auth scheme 은 PAT Basic auth (HTTP Basic, distribution spec 허용 포맷). JWT Bearer / `/v2/token` / RSA 키쌍 폐기. 이유: 사내 단일 registry 규모에서 JWT 의 stateless 검증 / scope 분리 / 외부 IdP federation 이점이 비용 대비 미미. 미래에 외부 노출 / federation 요구가 생기면 PAT 모델 위에 Bearer 레이어 추가 가능 (마이그레이션 비용 작음).** | **§2.4 PatAuthenticator, §3 Basic challenge/response, §5 PAT credentials only, §4.7 PR 분할 4 → 2** |

## Preceding Blockers (Stage 0 시작 전 완료 조건)

1. **[P0] RSpec→Minitest 포팅** (TODOS.md). Stage 0 이전 별도 브랜치.
2. **Google OAuth client** 발급 (사내 Workspace admin 협조). Redirect URI: `https://<host>/auth/google_oauth2/callback`.
3. **`REGISTRY_ADMIN_EMAIL`** 확정 (최초 admin 사용자 지정).

이전 Blocker 4 (JWT RSA 키쌍 생성) 와 5 (REGISTRY_JWT_ISSUER/AUDIENCE ENV) 는 D9 채택으로 **불필요**.

---

## 1. Migrations (Stage 별 스키마)

### 1.1 Stage 0 — OmniAuth 인프라 (마이그레이션 3개)

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :email,       null: false
      t.boolean  :admin,       null: false, default: false
      t.bigint   :primary_identity_id  # FK는 3번 마이그레이션에서 추가 (chicken-and-egg)
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end

# db/migrate/YYYYMMDDHHMMSS_create_identities.rb
class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.string   :provider,       null: false
      t.string   :uid,            null: false
      t.string   :email,          null: false
      t.boolean  :email_verified                 # tri-state: nil 허용 (provider 미보고)
      t.string   :name
      t.string   :avatar_url
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :identities, [:provider, :uid], unique: true
  end
end

# db/migrate/YYYYMMDDHHMMSS_add_primary_identity_fk_to_users.rb
class AddPrimaryIdentityFkToUsers < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :users, :identities, column: :primary_identity_id, on_delete: :restrict
    add_index :users, :primary_identity_id
  end
end
```

**`primary_identity_id` 의 NOT NULL 취급 (중요 tradeoff)**:
순환 FK 라서 SQLite 의 non-deferrable FK 제약상 DB 레벨 NOT NULL 은 불가능. 해결: **DB 레벨 NULLABLE + `after_commit` post-condition**. SessionCreator 트랜잭션 contract 로 "User 가 primary_identity 없는 상태" 는 단일 트랜잭션 내부 ~1ms 만 존재, 커밋 이후 unconditional non-nil 보장.

```ruby
# SessionCreator#call 내부 핵심
User.transaction do
  user = User.create!(email: profile.email, admin: admin_email?(profile.email))
  identity = user.identities.create!(provider: profile.provider, uid: profile.uid, ...)
  user.update!(primary_identity_id: identity.id)
end
# User 모델 — after_commit :guard_primary_identity_present
```

### 1.2 Stage 1 — Personal Access Token (마이그레이션 1개)

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_personal_access_tokens.rb
class CreatePersonalAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_access_tokens do |t|
      t.references :identity,   null: false, foreign_key: { on_delete: :cascade }
      t.string   :name,         null: false                  # 사용자 label
      t.string   :token_digest, null: false                  # SHA256(raw) hex
      t.string   :kind,         null: false, default: "cli"  # "cli" | "ci"
      t.datetime :last_used_at
      t.datetime :expires_at                                 # NULL = never (kind="ci" 허용)
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, [:identity_id, :name], unique: true
    add_index :personal_access_tokens, :revoked_at
  end
end
```

**Stage 1 에는 `tag_events` 스키마 변경 없음** — `actor` 컬럼 **내용만** `"anonymous"` → 실명 email 로 바뀜. 기존 데이터 migration 없음 (audit 무결성).

### 1.3 Stage 2 — Ownership + Delete 분리 (마이그레이션 3개)

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_owner_identity_to_repositories.rb
class AddOwnerIdentityToRepositories < ActiveRecord::Migration[8.1]
  def up
    add_reference :repositories, :owner_identity,
                  foreign_key: { to_table: :identities, on_delete: :restrict }
    admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL")
    admin_user = User.find_by!(email: admin_email)
    admin_identity_id = admin_user.primary_identity_id
    Repository.where(owner_identity_id: nil).update_all(owner_identity_id: admin_identity_id)
    change_column_null :repositories, :owner_identity_id, false
  end

  def down
    remove_reference :repositories, :owner_identity, foreign_key: true
  end
end

# db/migrate/YYYYMMDDHHMMSS_create_repository_members.rb
class CreateRepositoryMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :repository_members do |t|
      t.references :repository, null: false, foreign_key: { on_delete: :cascade }
      t.references :identity,   null: false, foreign_key: { on_delete: :cascade }
      t.string   :role, null: false   # "writer" | "admin"
      t.datetime :created_at, null: false
    end
    add_index :repository_members, [:repository_id, :identity_id], unique: true
    add_index :repository_members, [:identity_id, :role]
  end
end

# db/migrate/YYYYMMDDHHMMSS_add_actor_identity_to_tag_events.rb
class AddActorIdentityToTagEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :tag_events, :actor_identity,
                  foreign_key: { to_table: :identities, on_delete: :nullify }
    # Legacy 행은 actor_identity_id = NULL. TagEvent#display_actor helper 가 렌더 결정.
  end
end
```

### 1.4 FK on_delete 정책 요약

| FK | on_delete | 근거 |
|---|---|---|
| `identities.user_id → users` | restrict | user 삭제 전 identities 정리 요구 |
| `users.primary_identity_id → identities` | restrict | 순환 구조, identity 삭제 시 user 이전 요구 |
| `personal_access_tokens.identity_id → identities` | cascade | identity 삭제 시 토큰 자동 폐기 (security) |
| `repositories.owner_identity_id → identities` | restrict | orphan repo 방지, ownership transfer 강제 |
| `repository_members.identity_id → identities` | cascade | identity 삭제 시 자동 정리 |
| `repository_members.repository_id → repositories` | cascade | repo 삭제 시 member 자동 정리 |
| `tag_events.actor_identity_id → identities` | nullify | 이력 유지 + FK 만 끊음 |

**합계: 7 마이그레이션 파일** (Stage 0: 3, Stage 1: 1, Stage 2: 3).

---

## 2. Services / Concerns — 메서드 시그니처

### 2.1 Auth 에러 계층

```ruby
# app/errors/auth.rb
module Auth
  class Error < StandardError; end

  # Stage 0: OAuth callback flow
  class InvalidProfile    < Error; end   # provider returned empty/blank email or uid
  class EmailMismatch     < Error; end   # Case B attempted but email_verified != true
  class ProviderOutage    < Error; end   # OAuth upstream 5xx / timeout

  # Stage 1+: request-time auth
  class Unauthenticated   < Error; end   # no/malformed Authorization on protected endpoint
  class PatInvalid        < Error; end   # PAT not found / revoked / expired / email mismatch

  # Stage 2: authorization
  class ForbiddenAction < Error
    attr_reader :repository, :action
    def initialize(repository:, action:)
      @repository = repository
      @action = action
      super("forbidden: cannot #{action} on repository '#{repository.name}'")
    end
  end
end
```

### 2.2 Stage 0 — OmniAuth 서비스 계층

```ruby
# app/services/auth/provider_profile.rb
module Auth
  ProviderProfile = Data.define(:provider, :uid, :email, :email_verified, :name, :avatar_url)
end

# app/services/auth/google_adapter.rb
module Auth
  class GoogleAdapter
    # @param auth_hash [OmniAuth::AuthHash] from request.env["omniauth.auth"]
    # @return [Auth::ProviderProfile]
    # @raise [Auth::InvalidProfile] if email or uid blank
    def to_profile(auth_hash); end
  end
end

# app/services/session_creator.rb
class SessionCreator
  # Three-case resolver. Atomic: entire op in User.transaction.
  #
  # Case A - existing Identity(provider, uid) → attach
  # Case B - profile.email matches existing user AND profile.email_verified == true
  #          → add new Identity to that user
  # Case C - neither → create User + Identity pair
  #
  # Post-case: always call user.track_login!(identity) for primary_identity_id + last_seen_at
  #
  # @param profile [Auth::ProviderProfile]
  # @return [User]
  # @raise [Auth::InvalidProfile], [Auth::EmailMismatch]
  def call(profile); end
end
```

### 2.3 Stage 0 — User 모델의 LoginTracker concern

```ruby
# app/models/concerns/auth/login_tracker.rb
module Auth
  module LoginTracker
    extend ActiveSupport::Concern

    # Called from SessionCreator after resolving Case A/B/C.
    # Single transaction: identity.last_login_at + user.primary_identity_id + user.last_seen_at.
    #
    # @param identity [Identity]
    # @return [self]
    def track_login!(identity)
      transaction do
        identity.update!(last_login_at: Time.current)
        update!(primary_identity_id: identity.id, last_seen_at: Time.current)
      end
      self
    end
  end
end

# app/models/user.rb
class User < ApplicationRecord
  include Auth::LoginTracker
  # ...
end
```

### 2.4 Stage 1 — PAT Basic auth 검증

JWT 발급/검증 레이어 없음. `V2::BaseController` 의 before_action 이 Authorization header 의 Basic credentials 를 PAT digest 와 직접 매칭한다.

```ruby
# app/services/auth/pat_authenticator.rb
module Auth
  class PatAuthenticator
    Result = Data.define(:user, :pat)

    # @param email     [String]
    # @param raw_token [String]
    # @return [Result]
    # @raise [Auth::PatInvalid]
    #   - PAT not found / revoked / expired
    #   - email does not match pat.identity.user.email (case-insensitive)
    def call(email:, raw_token:); end
  end
end
```

`V2::BaseController` 측 호출:

```ruby
# app/controllers/v2/base_controller.rb (스케치)
class V2::BaseController < ActionController::API
  before_action :authenticate_v2_basic!, unless: :anonymous_pull_allowed?

  attr_reader :current_user, :current_pat

  private

  def authenticate_v2_basic!
    email, raw = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
    raise Auth::Unauthenticated if email.blank? || raw.blank?
    result = Auth::PatAuthenticator.new.call(email: email, raw_token: raw)
    @current_user = result.user
    @current_pat  = result.pat
    result.pat.update_column(:last_used_at, Time.current)
  rescue Auth::Unauthenticated, Auth::PatInvalid
    render_v2_challenge
  end

  def anonymous_pull_allowed?
    Rails.configuration.x.registry.anonymous_pull_enabled &&
      request.get? || request.head? &&
      ANONYMOUS_PULL_ENDPOINTS.include?([controller_name, action_name])
  end

  ANONYMOUS_PULL_ENDPOINTS = [
    %w[base    index],
    %w[catalog index],
    %w[tags    index],
    %w[manifests show],
    %w[blobs   show]
  ].freeze
end
```

JWT TokenIssuer/Verifier 가 사라지면서 등장 클래스는 `Auth::PatAuthenticator` 1개로 축소.

### 2.5 Stage 2 — Authorization concern (dual-context)

```ruby
# app/controllers/concerns/repository_authorization.rb
module RepositoryAuthorization
  extend ActiveSupport::Concern

  # Loads @repository and authorizes current_user for `action`.
  #
  # @param action [:read, :write, :delete]
  # @raise [Auth::Unauthenticated] if no current_user
  # @raise [Auth::ForbiddenAction] if action is denied
  def authorize_for!(action)
    raise Auth::Unauthenticated if current_user.nil?
    identity = current_user.primary_identity

    allowed = case action
              when :read   then true                           # Stage 3 visibility defer
              when :write  then @repository.writable_by?(identity)
              when :delete then @repository.deletable_by?(identity)
              end

    return if allowed
    raise Auth::ForbiddenAction.new(repository: @repository, action: action)
  end
end
```

두 컨트롤러 베이스가 동일 concern 을 include 하되 **rescue_from 매핑은 각자 다름**:

```ruby
# V2::BaseController (ActionController::API)
include RepositoryAuthorization
rescue_from Auth::Unauthenticated, with: ->(e) { render_v2_challenge }
rescue_from Auth::ForbiddenAction, with: ->(e) {
  render_error("DENIED",
               "insufficient_scope: #{e.action} privilege required on repository '#{e.repository.name}'",
               403,
               detail: { action: e.action.to_s, repository: e.repository.name })
}

# ApplicationController (ActionController::Base) — Web UI
include RepositoryAuthorization
rescue_from Auth::Unauthenticated, with: -> { redirect_to "/auth/google_oauth2" }
rescue_from Auth::ForbiddenAction, with: ->(e) {
  redirect_to repository_path(e.repository.name),
              alert: "You don't have permission to #{e.action} in '#{e.repository.name}'."
}
```

### 2.6 Stage 2 — Repository 모델 권한 메서드

```ruby
# app/models/repository.rb (추가)
class Repository < ApplicationRecord
  belongs_to :owner_identity, class_name: "Identity"
  has_many :repository_members, dependent: :destroy
  has_many :member_identities, through: :repository_members, source: :identity

  def writable_by?(identity)
    return false if identity.nil?
    return true if owner_identity_id == identity.id
    repository_members.exists?(identity_id: identity.id, role: %w[writer admin])
  end

  def deletable_by?(identity)
    return false if identity.nil?
    return true if owner_identity_id == identity.id
    repository_members.exists?(identity_id: identity.id, role: "admin")
  end

  # `by:` is a User (the one performing the transfer); kept distinct from the
  # string `actor` used elsewhere so TagEvent.actor is derived, not passed raw.
  def transfer_ownership_to!(new_owner_identity, by:)
    transaction do
      previous_owner_id = owner_identity_id
      update!(owner_identity_id: new_owner_identity.id)
      repository_members
        .find_or_create_by!(identity_id: previous_owner_id) { |m| m.role = "admin" }
      TagEvent.create!(
        repository: self, tag_name: "-",
        action: "ownership_transfer",
        actor: by.primary_identity.email,
        actor_identity_id: by.primary_identity_id,
        occurred_at: Time.current
      )
    end
  end
end
```

### 2.7 서비스별 Stage 매핑

| 파일 | Stage | 비고 |
|---|---|---|
| `app/errors/auth.rb` | 0 / 1 / 2 증분 | 단계별 예외 추가 |
| `app/services/auth/{provider_profile,google_adapter,session_creator}.rb` | 0 | |
| `app/models/concerns/auth/login_tracker.rb` | 0 | User include |
| `app/services/auth/{token_issuer,token_verifier}.rb` | 1 | |
| `app/controllers/concerns/repository_authorization.rb` | 2 | 양 베이스 include |
| Repository `writable_by?/deletable_by?/transfer_ownership_to!` | 2 | |

---

## 3. Docker Registry V2 Challenge/Response HTTP 예시 (Basic auth)

`docker push localhost:3000/myimage:v1` 가 Stage 1 이후 거치는 시퀀스. distribution spec 은 challenge response scheme 으로 `Basic` 도 허용하므로 token exchange 단계 없이 단일 challenge–retry 쌍으로 끝난다.

### 3.1 Step 1 — 최초 요청 (인증 없이)

```http
PUT /v2/myimage/manifests/v1 HTTP/1.1
Host: localhost:3000
User-Agent: docker/24.0.7 go/go1.20.10 git-commit/...
Content-Type: application/vnd.docker.distribution.manifest.v2+json
```

`docker push` 의 manifest upload 단계. Docker CLI 는 보통 BLOB upload 시도부터 같은 흐름을 거치므로 첫 번째 protected request 에서 challenge 가 나옴.

### 3.2 Step 2 — 서버 challenge (401)

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json
Docker-Distribution-API-Version: registry/2.0
WWW-Authenticate: Basic realm="Registry"
Content-Length: 83

{"errors":[{"code":"UNAUTHORIZED","message":"authentication required","detail":null}]}
```

**Header 주의사항** (구현 시 틀리는 지점):
- `WWW-Authenticate` 의 scheme 은 `Basic` (대문자 B, 소문자 가능하지만 표준은 `Basic`). Docker CLI 는 case-insensitive 파싱.
- `realm` 은 단순 식별자 ("Registry" 면 충분). Bearer flow 와 달리 `service` / `scope` 파라미터 불필요.
- 동일 challenge 가 모든 protected endpoint 에서 반환됨 (push / delete / Stage 2 의 admin scope).

### 3.3 Step 3 — Docker CLI 의 재시도 (Basic auth 첨부)

```http
PUT /v2/myimage/manifests/v1 HTTP/1.1
Host: localhost:3000
Authorization: Basic dG9ubnlAdGltYmVyYXkuY29tOm9wcmtfYWJjMTIz...
User-Agent: docker/24.0.7 ...
Content-Type: application/vnd.docker.distribution.manifest.v2+json
```

`Authorization: Basic <base64(email:pat_raw)>`. Docker CLI 는 `docker login` 시 저장한 자격을 자동으로 첨부. token exchange / 별도 endpoint 없이 같은 request 를 재시도.

### 3.4 Step 4 — 서버의 검증 처리

`V2::BaseController#authenticate_v2_basic!` (before_action):

1. `Authorization: Basic` 파싱 → `(email, pat_raw)`. 실패 → `401 + Basic challenge`.
2. `PersonalAccessToken.active.find_by(token_digest: Digest::SHA256.hexdigest(pat_raw))` 조회.
   - `.active` scope: `revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())`.
3. PAT 존재 안 함 → `401`.
4. `pat.identity.user.email.downcase == email.downcase` 검증 (email 불일치 → `401`, 정보 누출 방지로 메시지 동일).
5. 검증 성공:
   - `current_user = pat.identity.user`
   - `current_pat   = pat`
   - `pat.update_column(:last_used_at, Time.current)` (validation skip — write 부하 최소화)
6. **D5 anonymous pull gate** (push/delete 외):
   - HTTP method GET/HEAD + endpoint 가 `{base#index, catalog#index, tags#index, manifests#show, blobs#show}` 중 하나 + `Rails.configuration.x.registry.anonymous_pull_enabled == true` → `Authorization` header 가 비어도 통과 (current_user = nil).
   - 그 외 모든 경로는 인증 필수.

### 3.5 Step 5 — 서버의 200 응답 (push 정상 처리)

```http
HTTP/1.1 201 Created
Docker-Content-Digest: sha256:abc...
Location: /v2/myimage/manifests/sha256:abc...
```

이후 `ManifestProcessor.new.call(..., actor: current_user.email)` 로 진행. `TagEvent.actor` 에 `tonny@timberay.com` 기록.

### 3.6 스트레스 케이스 / 에러 응답

| 상황 | HTTP | body |
|---|---|---|
| Authorization header 누락 (push/delete 경로) | 401 + challenge | `{"errors":[{"code":"UNAUTHORIZED","message":"authentication required"}]}` |
| Basic 파싱 실패 (malformed base64 등) | 401 + challenge | 위와 동일 (정보 누출 방지) |
| PAT 존재 안 함 | 401 + challenge | 위와 동일 |
| PAT revoked / expired (`.active` 제외) | 401 + challenge | 위와 동일 |
| email 과 PAT 의 user 불일치 | 401 + challenge | 위와 동일 |
| anonymous pull 경로 + Authorization 없음 | 200 (정상 응답) | — |
| anonymous pull disabled (`REGISTRY_ANONYMOUS_PULL=false`) + 익명 pull | 401 + challenge | — |
| rack-attack throttle (push 경로 분당 N회 초과) | 429 | `Retry-After: 60` |

`/v2/token` endpoint 는 **존재하지 않음** (Bearer flow 폐기). rack-attack 는 일반 V2 endpoint 의 PAT 검증 부하만 throttle.

### 3.7 `render_v2_challenge` helper (구현 스케치)

```ruby
# app/controllers/v2/base_controller.rb
def render_v2_challenge
  response.headers["WWW-Authenticate"] = %(Basic realm="Registry")
  response.headers["Docker-Distribution-Api-Version"] = "registry/2.0"
  render json: {
    errors: [{ code: "UNAUTHORIZED", message: "authentication required", detail: nil }]
  }, status: :unauthorized
end
```

기존 §2.4 의 JWT TokenIssuer/Verifier / `kid` rotation / iss/aud 검증 로직은 모두 **제거**. `Authorization: Bearer ...` 흐름이 사라지므로 `service` / `scope` parameter 도 무관.

### 3.8 Bearer 미사용 결정의 trade-off (참고)

| 차원 | Basic (선택) | Bearer + JWT (포기) |
|---|---|---|
| 검증 비용 | 매 protected request 마다 PAT digest DB lookup | JWT 서명만 검증 (DB skip) |
| 토큰 만료 | PAT 자체 만료 (default 90 days) | JWT exp claim (15 분 자동) |
| 코드 양 | helper 1개 + PAT 검증 메서드 | TokenIssuer + Verifier + TokensController + RSA 키 관리 |
| 외부 표준 호환 | Docker CLI 호환 ✅ (distribution spec 허용) | 추가로 OIDC federation 가능 |
| 보안 표면 | base64 디코딩 + digest 비교 | JWT 라이브러리 취약점 (alg confusion 등) + 키 관리 |

사내 사용 규모 (분당 수회 push) 에서는 검증 비용 차이 무관. JWT 의 자동 만료 이점은 PAT 의 `expires_at` 으로 대체. 외부 IdP federation 요구가 생기면 그 시점에 Bearer 레이어를 PAT 위에 추가 (기존 PAT 모델 재사용 가능).

---

## 4. `actor:` 주입 변경 전/후 diff

### 4.1 `app/services/manifest_processor.rb` — Stage 1

```diff
 class ManifestProcessor
-  def call(repo_name, reference, content_type, payload)
+  def call(repo_name, reference, content_type, payload, actor:)
     parsed = JSON.parse(payload)
     # ... unchanged ...
     repository.with_lock do
       # ... unchanged ...
-      assign_tag!(repository, tag_name, manifest) if tag_name
+      assign_tag!(repository, tag_name, manifest, actor: actor) if tag_name
       manifest
     end
   end

-  def assign_tag!(repository, tag_name, manifest)
+  def assign_tag!(repository, tag_name, manifest, actor:)
     # ... unchanged find-or-create logic ...
     # existing_tag branch:
         TagEvent.create!(
           ...,
-          actor: "anonymous",
+          actor: actor,
           occurred_at: Time.current
         )
     # else branch:
         TagEvent.create!(
           ...,
-          actor: "anonymous",
+          actor: actor,
           occurred_at: Time.current
         )
   end
 end
```

호출자 2곳은 반드시 `actor:` 제공 (default 없음, 누락 시 ArgumentError).

### 4.2 `app/controllers/v2/manifests_controller.rb` — Stage 1

```diff
 class V2::ManifestsController < V2::BaseController
+  before_action :authenticate_v2!
+  # `authenticate_v2!` (on V2::BaseController) skips the token check when:
+  #   (1) request.get? || request.head?
+  #   (2) action_name is in %w[index show] (for this ctrl: show only)
+  #   (3) Rails.configuration.x.registry.anonymous_pull_enabled == true
+  # Stage 2: before_action -> { authorize_for!(:write) },  only: [:update]
+  # Stage 2: before_action -> { authorize_for!(:delete) }, only: [:destroy]

   def update
     # ... unchanged media type check + raw_post ...
     manifest = ManifestProcessor.new.call(
       repo_name,
       params[:reference],
       request.content_type,
-      payload
+      payload,
+      actor: current_user_email
     )
     # ... unchanged headers, head :created ...
   end

   def destroy
     # ... unchanged protection enforcement ...
     manifest.tags.each do |tag|
       TagEvent.create!(
         ...,
-        actor: "anonymous",
+        actor: current_user_email,
+        actor_identity_id: current_user.primary_identity_id,  # Stage 2 only — see §4.5
         occurred_at: Time.current
       )
     end
     # ... rest unchanged ...
   end

+  private
+  def current_user_email
+    current_user.primary_identity.email
+  end
 end
```

Stage 2 에서 `actor_identity_id:` 줄 추가 — Stage 1 PR 에서는 제외, Stage 2 PR 에서 re-add.

### 4.3 `app/controllers/tags_controller.rb` — Stage 1

```diff
 class TagsController < ApplicationController
+  before_action :ensure_current_user
   before_action :set_repository
   before_action :set_tag, only: [ :show, :destroy, :history ]
+  # Stage 2: before_action -> { authorize_for!(:delete) }, only: [:destroy]

   def destroy
     @repository.enforce_tag_protection!(@tag.name)
     TagEvent.create!(
       repository: @repository,
       tag_name: @tag.name,
       action: "delete",
       previous_digest: @tag.manifest.digest,
-      actor: "anonymous",
+      actor: current_user.primary_identity.email,
+      actor_identity_id: current_user.primary_identity_id,  # Stage 2 only
       occurred_at: Time.current
     )
     # ... rest unchanged ...
   end
 end
```

### 4.4 `app/services/image_import_service.rb` + `ProcessTarImportJob` — Stage 1

```diff
 class ImageImportService
-  def call(tar_path, repository_name: nil, tag_name: nil)
+  def call(tar_path, actor:, repository_name: nil, tag_name: nil)
     # ... unchanged parsing ...
     processor = ManifestProcessor.new(@blob_store)
-    processor.call(repo_name, tag, "application/vnd.docker.distribution.manifest.v2+json", v2_manifest.to_json)
+    processor.call(repo_name, tag, "application/vnd.docker.distribution.manifest.v2+json", v2_manifest.to_json, actor: actor)
   end
 end

 class ProcessTarImportJob < ApplicationJob
-  def perform(import_id)
+  def perform(import_id, actor_email:)
     import = Import.find(import_id)
-    ImageImportService.new.call(import.tar_path, repository_name: import.repository_name, tag_name: import.tag_name)
+    ImageImportService.new.call(
+      import.tar_path,
+      actor: actor_email || "system:import",
+      repository_name: import.repository_name,
+      tag_name: import.tag_name
+    )
   end
 end
```

호출 controller:
```ruby
ProcessTarImportJob.perform_later(import.id, actor_email: current_user.primary_identity.email)
```

(Session 없는 CLI/rake 호출 경로는 `actor_email: "system:import"` 명시.)

### 4.5 `TagEvent` 모델 — Stage 1 (helper) + Stage 2 (belongs_to, validation)

```diff
 class TagEvent < ApplicationRecord
   belongs_to :repository
+  belongs_to :actor_identity, class_name: "Identity", optional: true  # Stage 2

   validates :tag_name, presence: true
-  validates :action, presence: true, inclusion: { in: %w[create update delete] }
+  validates :action, presence: true,
+            inclusion: { in: %w[create update delete ownership_transfer] }  # Stage 2
   validates :occurred_at, presence: true

+  # Stage 1 helper: render actor string with system-prefix for legacy/system values.
+  # Examples:
+  #   "anonymous"          -> "<system: anonymous>"
+  #   "retention-policy"   -> "<system: retention-policy>"
+  #   "system:import"      -> "<system: import>"
+  #   "tonny@timberay.com" -> "tonny@timberay.com"
+  def display_actor
+    return actor if actor.to_s.include?("@")
+    "<system: #{actor.to_s.delete_prefix('system:')}>"
+  end
 end
```

Stage 1 PR 에서 `display_actor` + 기본 validation. Stage 2 PR 에서 `belongs_to :actor_identity` 추가 + validation 확장.

### 4.6 하드코딩 제거 체크리스트

grep 기준 실제 수정 포인트:

| 파일 | 라인 | Before | After |
|---|---|---|---|
| `app/services/manifest_processor.rb` | 115 | `actor: "anonymous"` (update TagEvent) | `actor: actor` |
| `app/services/manifest_processor.rb` | 126 | `actor: "anonymous"` (create TagEvent) | `actor: actor` |
| `app/controllers/v2/manifests_controller.rb` | 57 | `actor: "anonymous"` (destroy TagEvent) | `actor: current_user_email` |
| `app/controllers/tags_controller.rb` | 18 | `actor: "anonymous"` (Web UI destroy) | `actor: current_user.primary_identity.email` |

**`app/jobs/enforce_retention_policy_job.rb:30`** 의 `actor: "retention-policy"` 는 그대로 유지 — 시스템 actor. `TagEvent#display_actor` 가 `<system: retention-policy>` 로 렌더.

### 4.7 Stage 1 PR 분할 (Basic auth 채택 후)

| PR | 성격 | 내용 |
|---|---|---|
| Stage 1 PR-1 | structural | `actor:` required kwarg 추가. 호출자 모두 `actor: "anonymous"` 명시 (behavior 불변). config/initializer 변경 없음 |
| Stage 1 PR-2 | behavioral | PAT 모델 + Settings UI (CRUD) + `V2::BaseController#authenticate_v2_basic!` + anonymous pull gate + `actor: current_user.email` 실명화 (V2 push/delete + Web UI delete) + import job `actor_email:` + `display_actor` helper + Critical Gap #3 regression |

JWT TokenIssuer/Verifier / `V2::TokensController` / RSA 키쌍 / `/v2/token` route 는 모두 **제외**. 이전 4 PR 분할 (PR-2 PAT/JWT infra → PR-3 auth gate → PR-4 import + UI) 은 옵션 1 채택으로 단일 PR-2 에 통합.

Stage 2 의 `actor_identity_id` 추가 + `ownership_transfer` 확장은 Stage 2 PR-3 에서.

---

## 5. PAT 검증 + ENV 설정

### 5.1 PAT 보안 모델

PAT 는 raw token 자체가 비밀. 서버는 SHA256 digest 만 저장 → 도난된 DB 로도 복원 불가.

| 항목 | 처리 |
|---|---|
| Raw token 형식 | `oprk_` prefix + `SecureRandom.urlsafe_base64(32)` (43 chars) |
| 발급 시 사용자 노출 | 한 번만 (생성 직후 화면). 재조회 불가 |
| DB 저장 | `token_digest = Digest::SHA256.hexdigest(raw)` (unique) |
| 검증 | request 의 raw token → SHA256 → digest column 매칭 |
| 폐기 | `revoked_at = Time.current` (soft delete, audit 보존) |
| 만료 | `expires_at` 컬럼. `kind = "cli"` 발급 시 default 90 days, `kind = "ci"` 는 NULL 허용 |

### 5.2 ENV 변수 — 환경별 값

```bash
# dev
REGISTRY_ADMIN_EMAIL=tonny@timberay.com
REGISTRY_ANONYMOUS_PULL=true

# staging / prod
REGISTRY_ADMIN_EMAIL=devops@timberay.com
REGISTRY_ANONYMOUS_PULL=true
```

JWT 관련 ENV (`REGISTRY_JWT_ISSUER`, `REGISTRY_JWT_AUDIENCE`) 는 Basic auth 채택으로 **불필요**. RSA 키쌍 / `config/credentials/<env>.yml.enc` 의 `jwt:` 블록도 **불필요**.

### 5.3 `config/initializers/registry.rb` — 설정 로딩

```ruby
Rails.application.configure do
  config.x.registry.admin_email  = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
  config.x.registry.anonymous_pull_enabled =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REGISTRY_ANONYMOUS_PULL", "true"))
end
```

Stage 0 의 admin_email 로딩 외에는 추가 설정 없음. JWT 섹션이 사라지면서 initializer 가 단순해진다.

### 5.4 `WWW-Authenticate` realm — Bearer → Basic

challenge response 의 scheme 이 `Bearer` 가 아니라 `Basic` 이므로 helper 가 단순:

```ruby
def render_v2_challenge
  response.headers["WWW-Authenticate"] = %(Basic realm="Registry")
  render_error("UNAUTHORIZED", "authentication required", 401)
end
```

`scope` / `service` 파라미터는 Bearer flow 의 token exchange 단계용이라 Basic 에서는 무관.

### 5.5 보안 운영 체크리스트 (Stage 1 배포 직전)

| 항목 | 확인 방법 |
|---|---|
| `personal_access_tokens.token_digest` 에 unique index 적용 | `bin/rails db:schema:dump | grep token_digest` |
| Raw token 이 로그/오류 추적기에 안 새는지 | `lograge.custom_payload` 에 `Authorization` 마스킹 |
| Rails default password log filter 에 PAT 추가 | `config/initializers/filter_parameter_logging.rb` 에 `:authorization` |
| `kind = "ci"` 토큰 (만료 NULL) 발급 권한 — admin only? | Stage 2 의 권한 정책에서 결정 (현재는 모든 user 가 발급) |

### 5.6 (의도적 공란)

이 섹션은 이전에 "키 생성 자동화 bin script" 였으나 Basic auth 채택으로 삭제. RSA 키쌍 자체가 불필요.

---

## 6. Minitest 테스트 파일 레이아웃

### 6.1 RSpec→Minitest 포팅 후 target 구조

```
test/
├── test_helper.rb
├── fixtures/
│   ├── files/keys/
│   │   ├── test_jwt_private.pem         # 테스트 전용 RSA 키쌍
│   │   └── test_jwt_public.pem
│   ├── users.yml                        # Stage 0
│   ├── identities.yml                   # Stage 0
│   ├── personal_access_tokens.yml       # Stage 1
│   ├── repository_members.yml           # Stage 2
│   └── ... (existing: repositories, manifests, tags, tag_events, blobs)
├── models/
│   ├── user_test.rb                     # Stage 0
│   ├── identity_test.rb                 # Stage 0
│   ├── personal_access_token_test.rb    # Stage 1
│   ├── repository_test.rb               # + Stage 2 권한 메서드
│   ├── tag_event_test.rb                # + display_actor + ownership_transfer validation
│   └── repository_member_test.rb        # Stage 2
├── services/
│   ├── auth/
│   │   ├── google_adapter_test.rb       # Stage 0
│   │   ├── token_issuer_test.rb         # Stage 1
│   │   └── token_verifier_test.rb       # Stage 1
│   ├── session_creator_test.rb          # Stage 0 (Case A/B/C)
│   └── manifest_processor_test.rb       # + actor: kwarg 강제
├── controllers/
│   ├── auth/sessions_controller_test.rb      # Stage 0
│   ├── settings/tokens_controller_test.rb    # Stage 1
│   ├── tags_controller_test.rb               # + Stage 1 실명화, + Stage 2 authz
│   ├── repositories_controller_test.rb       # + Stage 2 authz on destroy
│   └── v2/
│       ├── base_controller_test.rb           # Stage 1 auth + anonymous pull gate
│       ├── tokens_controller_test.rb         # Stage 1 /v2/token
│       ├── manifests_controller_test.rb      # + Stage 1 bearer, + Stage 2 authz
│       ├── blobs_controller_test.rb          # Stage 2 destroy authz
│       ├── blob_uploads_controller_test.rb   # Stage 2 first-pusher-owner
│       └── catalog_controller_test.rb        # anonymous pull
├── integration/
│   ├── auth_google_oauth_flow_test.rb        # Stage 0 E2E
│   ├── auth_session_restore_test.rb          # Stage 0
│   ├── docker_token_exchange_test.rb         # Stage 1 4-step
│   ├── docker_cli_flow_test.rb               # Stage 1/2 via `system("docker ...")`
│   ├── retention_ownership_interaction_test.rb  # Critical Gap #1
│   ├── first_pusher_race_test.rb                # Critical Gap #2
│   ├── anonymous_pull_regression_test.rb        # Critical Gap #3
│   ├── ownership_transfer_flow_test.rb          # Stage 2
│   └── jwt_signature_mismatch_test.rb           # Stage 1 (env isolation)
├── jobs/
│   ├── enforce_retention_policy_job_test.rb     # 포팅
│   └── process_tar_import_job_test.rb           # + actor_email: 전파
├── helpers/
│   └── tag_event_helper_test.rb                 # display_actor
└── system/
    ├── auth_login_test.rb                       # Stage 0
    ├── settings_tokens_test.rb                  # Stage 1
    └── repository_members_management_test.rb    # Stage 2
```

**Stage 별 신규/수정 파일 수** (RSpec 포팅 제외):
- Stage 0: ~9 신규
- Stage 1: ~10 신규 + 5 수정
- Stage 2: ~8 신규 + 5 수정

### 6.2 `test/test_helper.rb` — 전역 헬퍼 확장

```ruby
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  fixtures :all

  setup do
    Rails.configuration.x.registry.admin_email             = "admin@timberay.com"
    Rails.configuration.x.registry.anonymous_pull_enabled  = true
  end

  # Stage 0: mock OmniAuth callback
  def mock_omniauth(provider: "google_oauth2", uid: "12345",
                    email: "tonny@timberay.com", email_verified: true,
                    name: "Tonny Kim", avatar_url: nil)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: { email: email, name: name, image: avatar_url },
      extra: { raw_info: { email_verified: email_verified } }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[provider.to_sym]
  end

  # Stage 0: sign-in helper using test-only /testing/sign_in route
  def sign_in_as(user)
    post "/testing/sign_in", params: { user_id: user.id }
    assert_response :ok
  end
end

class ActionDispatch::IntegrationTest
  # Build PAT Basic auth headers for V2 protected endpoints.
  # @param pat_raw [String] raw token (TokenFixtures::TONNY_CLI_RAW 등)
  # @param email   [String] user email matching pat.identity.user.email
  def basic_auth_for(pat_raw:, email:)
    {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(email, pat_raw)
    }
  end
end
```

`bearer_headers_for` helper 는 JWT 폐기로 삭제 (D9). Stage 1 의 모든 V2 통합 테스트는 `basic_auth_for` 만 사용.

### 6.3 `/testing/sign_in` 전용 route (Rails.env.test? 가드)

```ruby
# config/routes.rb (Stage 0 추가)
if Rails.env.test?
  post "/testing/sign_in", to: "testing#sign_in"
end

# app/controllers/testing_controller.rb (Stage 0 추가)
class TestingController < ApplicationController
  def sign_in
    session[:user_id] = params[:user_id]
    head :ok
  end
end
```

prod 에서는 라우트 자체가 존재하지 않아 공격 벡터 없음.

### 6.4 Fixtures 전략

Rails fixtures 로 일원화 (QUALITY.md 지침). 동적 속성이 필요하면 테스트 내부 helper method 로, factory_bot gem 의존은 제거.

예시:

```yaml
# test/fixtures/users.yml
admin:
  email: admin@timberay.com
  admin: true
  primary_identity: admin_google
  last_seen_at: <%= 1.minute.ago %>
  created_at: <%= 2.days.ago %>
  updated_at: <%= 1.minute.ago %>

tonny:
  email: tonny@timberay.com
  admin: false
  primary_identity: tonny_google
  last_seen_at: <%= 5.minutes.ago %>
  created_at: <%= 1.day.ago %>
  updated_at: <%= 5.minutes.ago %>

# test/fixtures/identities.yml
admin_google:
  user: admin
  provider: google_oauth2
  uid: "admin-google-1"
  email: admin@timberay.com
  email_verified: true
  name: Admin User
  last_login_at: <%= 1.minute.ago %>

tonny_google:
  user: tonny
  provider: google_oauth2
  uid: "tonny-google-1"
  email: tonny@timberay.com
  email_verified: true
  name: Tonny Kim
  last_login_at: <%= 5.minutes.ago %>

# test/fixtures/personal_access_tokens.yml
tonny_cli_active:
  identity: tonny_google
  name: "laptop"
  token_digest: <%= Digest::SHA256.hexdigest("oprk_test_tonny_cli_raw") %>
  kind: cli
  expires_at: <%= 89.days.from_now %>
  created_at: <%= 1.day.ago %>
  updated_at: <%= 1.day.ago %>

tonny_ci_never_expires:
  identity: tonny_google
  name: "jenkins-prod"
  token_digest: <%= Digest::SHA256.hexdigest("oprk_test_tonny_ci_raw") %>
  kind: ci
  expires_at:
  created_at: <%= 1.day.ago %>
  updated_at: <%= 1.day.ago %>

tonny_revoked:
  identity: tonny_google
  name: "old-laptop"
  token_digest: <%= Digest::SHA256.hexdigest("oprk_test_tonny_revoked_raw") %>
  kind: cli
  revoked_at: <%= 1.hour.ago %>
  created_at: <%= 30.days.ago %>
  updated_at: <%= 1.hour.ago %>
```

raw token 상수는 테스트 전용 모듈에:
```ruby
# test/support/token_fixtures.rb
module TokenFixtures
  TONNY_CLI_RAW      = "oprk_test_tonny_cli_raw".freeze
  TONNY_CI_RAW       = "oprk_test_tonny_ci_raw".freeze
  TONNY_REVOKED_RAW  = "oprk_test_tonny_revoked_raw".freeze
end
```

### 6.5 Integration test 패턴 예시

Stage 1 의 대표:

```ruby
# test/integration/docker_basic_auth_test.rb
require "test_helper"

class DockerBasicAuthTest < ActionDispatch::IntegrationTest
  include TokenFixtures

  test "push without Authorization → 401 + Basic challenge" do
    put "/v2/myimage/manifests/v1",
        params: minimal_manifest_payload,
        headers: { "Content-Type" => "application/vnd.docker.distribution.manifest.v2+json" }
    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
  end

  test "push with valid PAT Basic auth → 201 + TagEvent.actor 실명 기록" do
    pat_raw = TONNY_CLI_RAW
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("tonny@timberay.com", pat_raw),
      "Content-Type"  => "application/vnd.docker.distribution.manifest.v2+json"
    }

    assert_difference -> { TagEvent.where(actor: "tonny@timberay.com").count }, +1 do
      put "/v2/myimage/manifests/v1", params: minimal_manifest_payload, headers: headers
    end
    assert_response :created

    pat = PersonalAccessToken.find_by!(token_digest: Digest::SHA256.hexdigest(pat_raw))
    assert_in_delta Time.current, pat.last_used_at, 5.seconds
  end

  test "push with revoked PAT → 401" do
    pat_raw = TONNY_REVOKED_RAW
    headers = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("tonny@timberay.com", pat_raw) }
    put "/v2/myimage/manifests/v1", params: "{}", headers: headers
    assert_response :unauthorized
  end

  test "anonymous pull (REGISTRY_ANONYMOUS_PULL=true) → 200 without Authorization" do
    seed_image_for("myimage", "v1")
    get "/v2/myimage/manifests/v1"
    assert_response :ok
  end
end
```

Bearer flow 의 token exchange 단계가 사라지면서 setup/assertion 이 1/3 수준으로 축소.

### 6.6 Docker CLI E2E — 별도 bin script

```ruby
# test/integration/docker_cli_flow_test.rb
require "test_helper"

class DockerCliFlowTest < ActionDispatch::IntegrationTest
  setup { skip "set DOCKER_E2E=1 to enable" unless ENV["DOCKER_E2E"] == "1" }

  test "docker login → push → pull round-trip" do
    email = "tonny@timberay.com"
    pat   = issue_real_pat_for(email)
    registry = ENV.fetch("REGISTRY_HOST", "localhost:3000")

    assert system("docker", "login", registry, "-u", email, "-p", pat),
           "docker login failed"
    # ... push, pull, assert docker pull succeeds ...
  end
end
```

```bash
#!/usr/bin/env bash
# bin/test-e2e-docker
set -euo pipefail
export DOCKER_E2E=1
export REGISTRY_HOST="${REGISTRY_HOST:-localhost:3001}"

bin/rails db:test:prepare
bin/rails server -e test -p 3001 &
SERVER_PID=$!
trap "kill $SERVER_PID" EXIT

until curl -sf "http://$REGISTRY_HOST/up" >/dev/null; do sleep 0.5; done

bin/rails test test/integration/docker_cli_flow_test.rb
```

### 6.7 Stage 별 테스트 작성 순서 (TDD Red-Green-Refactor)

| Stage | PR | 테스트 작성 순서 |
|---|---|---|
| 0 | PR-1 structural | users/identities 모델 (비정규화 FK 제약, presence) |
| 0 | PR-2 behavioral | session_creator Case A/B/C → 구현 → google_oauth_flow integration |
| 1 | PR-1 structural | ManifestProcessor `actor:` required kwarg (ArgumentError) |
| 1 | PR-2 behavioral | PAT 모델 (.active scope, authenticate_raw) → PatAuthenticator 단위 → V2::BaseController#authenticate_v2_basic! 통합 → anonymous_pull_regression → Settings::Tokens UI |
| 2 | PR-1 structural | repository_member 모델 + Repository 권한 메서드 |
| 2 | PR-2 behavioral | RepositoryAuthorization concern (V2 + Web UI) |
| 2 | PR-3 | ownership_transfer + first_pusher_race + retention_ownership_interaction |

---

## 7. Critical Gap Tests (3건 구체 셋업)

### 7.1 갭 #1 — Retention job × Stage 2 ownership 상호작용

**Iron rule**: Retention job 은 시스템 actor 로 `tag_protected?` 만 체크. `authorize_for!` 는 절대 호출 안 함.

```ruby
# test/integration/retention_ownership_interaction_test.rb
require "test_helper"

class RetentionOwnershipInteractionTest < ActionDispatch::IntegrationTest
  setup do
    ENV["RETENTION_ENABLED"] = "true"
    ENV["RETENTION_DAYS_WITHOUT_PULL"] = "90"
    ENV["RETENTION_MIN_PULL_COUNT"] = "5"
    ENV["RETENTION_PROTECT_LATEST"] = "true"
  end

  teardown do
    %w[RETENTION_ENABLED RETENTION_DAYS_WITHOUT_PULL
       RETENTION_MIN_PULL_COUNT RETENTION_PROTECT_LATEST].each { |k| ENV.delete(k) }
  end

  test "retention deletes owned-by-other stale tag without raising" do
    owner_identity = identities(:tonny_google)
    other_identity = identities(:admin_google)

    repo = Repository.create!(
      name: "other-owned-repo",
      owner_identity_id: other_identity.id,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:stale123",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "old-release")

    assert_difference -> { TagEvent.where(actor: "retention-policy").count }, +1 do
      assert_difference -> { repo.tags.count }, -1 do
        EnforceRetentionPolicyJob.perform_now
      end
    end

    event = TagEvent.order(:occurred_at).last
    assert_equal "retention-policy", event.actor
    assert_nil event.actor_identity_id
  end

  test "retention skips tag protected by policy even if owner-identity is set" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "protected-repo",
      owner_identity_id: owner_identity.id,
      tag_protection_policy: "semver"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:v1stale",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "v1.0.0")

    assert_no_difference -> { repo.tags.count } do
      EnforceRetentionPolicyJob.perform_now
    end
    refute TagEvent.exists?(repository: repo, tag_name: "v1.0.0", action: "delete")
  end

  test "retention does not call authorize_for!" do
    repo = Repository.create!(name: "r",
                              owner_identity: identities(:tonny_google),
                              tag_protection_policy: "none")
    manifest = repo.manifests.create!(
      digest: "sha256:x",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 1, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "t")

    RepositoryAuthorization.stub_any_instance(:authorize_for!,
      ->(*) { flunk "retention must not call authorize_for!" }) do
      EnforceRetentionPolicyJob.perform_now
    end
  end
end
```

### 7.2 갭 #2 — First-pusher race (`blob_uploads_controller.rb`)

**구현 요구사항**:

```ruby
# app/controllers/v2/blob_uploads_controller.rb — Stage 2
def ensure_repository!
  identity_id = current_user.primary_identity_id
  @repository = Repository.find_or_create_by!(name: repo_name) do |r|
    r.owner_identity_id = identity_id
  end
rescue ActiveRecord::RecordNotUnique
  @repository = Repository.find_by!(name: repo_name)
  retry unless (@retry_once ||= true).tap { @retry_once = false }
end
```

**테스트**:

```ruby
# test/integration/first_pusher_race_test.rb
require "test_helper"

class FirstPusherRaceTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false  # SQLite WAL unique race 재현

  test "concurrent first-push: exactly one owner" do
    tonny  = identities(:tonny_google)
    admin  = identities(:admin_google)
    repo_name = "race-repo-#{SecureRandom.hex(4)}"
    refute Repository.exists?(name: repo_name)

    tonny_hdrs = bearer_headers_for(identity: tonny,
      access: [ { type: "repository", name: repo_name, actions: %w[push pull] } ])
    admin_hdrs = bearer_headers_for(identity: admin,
      access: [ { type: "repository", name: repo_name, actions: %w[push pull] } ])

    barrier = Concurrent::CyclicBarrier.new(2)
    responses = {}

    threads = [[tonny, tonny_hdrs], [admin, admin_hdrs]].map do |(identity, hdrs)|
      Thread.new do
        barrier.wait
        post "/v2/#{repo_name}/blobs/uploads", headers: hdrs
        responses[identity.id] = response.status
      end
    end
    threads.each(&:join)

    assert_equal [202, 202], responses.values.sort
    assert_equal 1, Repository.where(name: repo_name).count

    repo = Repository.find_by!(name: repo_name)
    assert_includes [tonny.id, admin.id], repo.owner_identity_id

    loser_id = (repo.owner_identity_id == tonny.id) ? admin.id : tonny.id
    refute RepositoryMember.exists?(repository: repo, identity_id: loser_id)
  ensure
    Repository.where(name: repo_name).destroy_all if repo_name
  end

  test "no orphan blob_upload rows on loser's path" do
    repo_name = "orphan-check-#{SecureRandom.hex(4)}"
    # ... 유사 setup ...
    # race 이후 blob_uploads 개수 = 2
    assert_equal 2, BlobUpload.where(repository: Repository.find_by!(name: repo_name)).count
  end

  test "push to existing repo does NOT reassign owner_identity_id" do
    owner = identities(:tonny_google)
    intruder = identities(:admin_google)
    repo = Repository.create!(name: "pre-existing",
                              owner_identity: owner,
                              tag_protection_policy: "none")
    intruder_hdrs = bearer_headers_for(identity: intruder,
      access: [ { type: "repository", name: repo.name, actions: %w[push pull] } ])

    post "/v2/#{repo.name}/blobs/uploads", headers: intruder_hdrs

    assert_equal 403, response.status
    repo.reload
    assert_equal owner.id, repo.owner_identity_id
  end
end
```

### 7.3 갭 #3 — Anonymous pull regression

**5개 pull 엔드포인트 + 3개 non-pull + env flag off + PullEvent 기록**:

```ruby
# test/integration/anonymous_pull_regression_test.rb
require "test_helper"

class AnonymousPullRegressionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    @repo = repositories(:public_repo)
    @manifest = manifests(:public_v1)
    @blob = blobs(:public_blob)
    @tag = tags(:public_v1_tag)
  end

  test "GET /v2/ (discovery) 200 without token" do
    get "/v2/"
    assert_response :ok
  end

  test "GET /v2/_catalog 200 without token" do
    get "/v2/_catalog"
    assert_response :ok
  end

  test "GET /v2/:name/tags/list 200 without token" do
    get "/v2/#{@repo.name}/tags/list"
    assert_response :ok
  end

  test "GET /v2/:name/manifests/:ref 200 without token (tag ref)" do
    get "/v2/#{@repo.name}/manifests/#{@tag.name}"
    assert_response :ok
    assert_equal @manifest.digest, response.headers["Docker-Content-Digest"]
  end

  test "HEAD /v2/:name/manifests/:ref 200 without token (digest ref)" do
    head "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_response :ok
  end

  test "GET /v2/:name/blobs/:digest 200 without token" do
    BlobStore.stub_any_instance(:exists?, true) do
      BlobStore.stub_any_instance(:path_for,
        Rails.root.join("test/fixtures/files/empty.txt")) do
        get "/v2/#{@repo.name}/blobs/#{@blob.digest}"
        assert_response :ok
      end
    end
  end

  test "PUT /v2/:name/manifests/:ref without token 401 + challenge" do
    put "/v2/#{@repo.name}/manifests/newtag",
        params: {}.to_json,
        headers: { "Content-Type" => "application/vnd.docker.distribution.manifest.v2+json" }
    assert_response :unauthorized
    assert_match %r{\ABearer realm=}, response.headers["WWW-Authenticate"]
  end

  test "POST /v2/:name/blobs/uploads without token 401" do
    post "/v2/#{@repo.name}/blobs/uploads"
    assert_response :unauthorized
    assert_match %r{\ABearer realm=}, response.headers["WWW-Authenticate"]
  end

  test "DELETE /v2/:name/manifests/:ref without token 401" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_response :unauthorized
  end

  test "when anonymous_pull_enabled=false, GET manifests requires token" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/#{@repo.name}/manifests/#{@tag.name}"
    assert_response :unauthorized
    assert_match %r{\ABearer realm=}, response.headers["WWW-Authenticate"]
  end

  test "anonymous GET manifest records PullEvent with remote_ip" do
    assert_difference -> { PullEvent.count }, +1 do
      get "/v2/#{@repo.name}/manifests/#{@tag.name}",
          headers: { "REMOTE_ADDR" => "10.0.0.42" }
    end
    event = PullEvent.order(:occurred_at).last
    assert_equal "10.0.0.42", event.remote_ip
  end
end
```

### 7.4 CI 하드 게이트

이 3 파일은 Stage 1/2 PR merge 의 하드 게이트:

```yaml
# .github/workflows/ci.yml (발췌)
- name: Run critical gap tests
  run: |
    bin/rails test \
      test/integration/retention_ownership_interaction_test.rb \
      test/integration/first_pusher_race_test.rb \
      test/integration/anonymous_pull_regression_test.rb
  env:
    RAILS_ENV: test
```

3개 중 하나라도 실패 → merge 차단. Stage 2 완료 전 3개 모두 GREEN 이어야 production 배포.

---

## 8. Stage 0→1→2 배포 순서 + Rollback 절차

### 8.1 전체 타임라인

```
[T-1 week]   ├─ Blocker A: RSpec→Minitest 포팅 (P0)
             ├─ Blocker B: Google OAuth client 발급
             └─ Blocker C: REGISTRY_ADMIN_EMAIL ENV (staging/prod)

[T0]         Stage 0 배포 (OmniAuth 인프라)
             · feature/registry-auth-stage0 → main
             · 3 PR 머지 + CI green + staging 1일 soak
             · prod 효과: anonymous push/pull 유지, /auth/google 로그인 가능

[T+3~7d]     Stage 1 배포 (PAT Basic auth + attribution)
             · feature/registry-auth-stage1 → main
             · 2 PR 머지 (PR-1 structural + PR-2 behavioral)
             · ⚠️ 배포 순간부터 docker push/delete 는 PAT 필수. pull 은 anonymous.
             · 사전 공지: 모든 CI/K8s credential 을 PAT 로 사전 교체 완료 상태

[T+5~12d]    Stage 2 배포 (ownership + delete 분리)
             · feature/registry-auth-stage2 → main
             · 3 PR 머지
             · Stage 1→2 간격 최대 5일 이내 (Risk 경고 준수)
             · prod 효과: 내가 owner/writer 아닌 repo push → 403
```

### 8.2 Stage 별 배포 체크리스트

**Stage 0 체크리스트**:
```
□ Blocker A (RSpec→Minitest) main 머지 완료
□ Blocker B/C/D ENV + credentials 주입
□ Gemfile 에 omniauth + omniauth-google-oauth2 + omniauth-rails_csrf_protection 추가
□ db:migrate 3 마이그레이션 dry-run (staging)
□ staging canary: admin OAuth 로그인 → /settings 진입 → session persist 확인
□ rack-attack 10/min/IP 반영
□ production traffic 영향 0 (anonymous push 경로 미변경)
```

**Stage 1 체크리스트**:
```
□ Stage 0 main 머지 + 1일+ staging soak
□ PR-1 (structural: actor: required kwarg) 머지
□ PR-2 (behavioral: PAT 모델 + V2 Basic auth gate + 실명화 + import job actor_email + Settings UI) 머지
□ staging: docker login → push → pull 전체 사이클 성공
□ TagEvent.actor 가 실명 email 로 기록 (DB 직접 확인)
□ V2 push 경로 rack-attack 스로틀 반영 (PAT digest lookup 부하 보호)
□ CI / K8s ImagePullSecrets PAT 교체 완료
□ 크리티컬 갭 테스트 3건 GREEN
□ 배포 2일 전 Slack 공지: "Stage 1 배포 순간 모든 push/delete 가 PAT 필수"
```

**Stage 2 체크리스트**:
```
□ Stage 1 main 머지 + 3~5일 soak
□ PR-1 (structural: repository_members + owner_identity_id + actor_identity_id + backfill)
  └ 마이그레이션 dry-run on staging: 기존 repo 개수만큼 owner = ADMIN 세팅 확인
□ PR-2 (behavioral: RepositoryAuthorization concern + Repository 권한 메서드)
□ PR-3 (ownership_transfer + first-pusher-race + retention coupling 회귀 테스트)
□ staging: "다른 owner repo push → 403" 수동 확인
□ Ownership transfer UI 동작 확인
□ 크리티컬 갭 테스트 3건 GREEN 유지
□ 배포 공지: "Stage 2 배포 순간 권한 체크 활성. 기본적으로 모든 repo 는 admin 소유."
```

### 8.3 Rollback 절차

**일반 원칙**:
- **Schema rollback 은 최후 수단**. `db:rollback` 은 prod 데이터 파괴 위험. 우선 **앱 rollback** (`kamal rollback`) 시도.
- 마이그레이션 파일은 모두 reversible (`def change` 또는 `def up/down`). Backfill 있는 마이그레이션(Stage 2 `owner_identity_id`) 은 `down` 에 명시적 `remove_reference` 만.

#### Stage 0 rollback 시나리오

- **A. OAuth callback 전체 실패** (Google API 장애 / redirect URI mismatch): `kamal rollback`. Schema 유지 (anonymous 경로 미변경이라 무해). Blocker B 재점검 후 재배포.
- **B. users/identities 마이그레이션 실패**: `kamal app exec 'bin/rails db:rollback STEP=3'`. 앱 이전 커밋 복귀. Solid Queue worker 중지 후 재마이그레이션.

#### Stage 1 rollback 시나리오

- **C. docker push 401 — PAT 검증 버그 (digest 비교 / email 매칭)**: `kamal rollback` → Stage 0 상태. V2 가 다시 anonymous push 허용 (기능 복구, audit 갭 발생 가능). Schema 유지 (PAT 테이블은 비어있어도 무해). 다음 재배포 시 마이그레이션 skip.
- **D. 인증은 되나 `ManifestProcessor.call` actor kwarg 누락 배포**: PR-1/PR-2 분리되어 있으므로 **PR-2 만 revert** → `current_user.email` 대신 `"anonymous"` 로 복귀. TagEvent.actor 일시적 anonymous, 기능 복구.
- **E. `REGISTRY_ANONYMOUS_PULL` 조건 분기 버그로 모든 pull 이 401**: 앱 rollback 또는 긴급 hotfix PR. K8s ImagePullBackOff 즉각 영향 → canary 에서 20분 내 탐지 필수.

#### Stage 2 rollback 시나리오

- **F. owner_identity_id backfill 실패**: 사내용 repo 수 < 100 예상이라 가능성 낮음. 실패 시 마이그레이션 분할(NULL 허용 add_reference → 데이터 마이그레이션 task → not null 제약).
- **G. `authorize_for!(:write)` 너무 까다로워 대량 차단**: PR-2 만 revert, DB 스키마 유지, Stage 1 수준 권한 복구. Web UI Members 로 writer 추가 후 재배포.
- **H. retention job 이 authorize_for! 실수 경유**: 크리티컬 갭 #1 테스트가 pre-merge 게이트에서 잡아야 함. 만일 prod 에서 터지면: `config/recurring.yml` 에서 retention schedule 주석 → 재배포 → hotfix.
- **I. first-pusher-race 에서 owner 오기록**: 즉시 복구 SQL `UPDATE repositories SET owner_identity_id = ? WHERE name = ?` 또는 admin 이 Web UI Transfer ownership. 사건 후 크리티컬 갭 #2 테스트 보강.

### 8.4 배포 관측 지표

각 Stage 배포 직후 15분 모니터링:

| Stage | 지표 | alert 임계값 |
|---|---|---|
| 0 | `/auth/google/callback` 성공률 | < 95% 5min 초과 |
| 0 | Session-restore 실패 (user_id 있으나 User 미존재) | > 0 count |
| 1 | `/v2/token` 200 응답률 | < 95% |
| 1 | `V2::BaseController#authenticate_v2!` 의 401 비율 (baseline 대비) | > baseline + 10% |
| 1 | `TagEvent.where(actor: "anonymous").where("created_at > ?", T)` | > 0 (audit 갭 경보) |
| 2 | `Auth::ForbiddenAction.count` spike | > 평균 + 3σ |
| 2 | `/v2/_catalog` 응답 시간 | > 1s (N+1 회귀) |

구현: `ActiveSupport::Notifications` 로 `auth.oauth_callback`, `auth.token_issued`, `auth.token_verified`, `auth.forbidden_action` 이벤트 발행 → Timberay 기존 모니터링 스택에 맞춤.

### 8.5 Rollback decision tree

```
Stage 배포 후 15분 canary
 ├─ 0% 에러 증가 → 즉시 full rollout
 ├─ 에러 증가 but < 5%, 단일 edge case → hotfix PR 우선 시도, 1시간 타임박스
 ├─ 에러 > 5% OR 기능 완전 실패 → 즉시 kamal rollback
 └─ 5xx burst + 원인 불명 → 즉시 kamal rollback + incident review
```

**Rollback 결정권자**: 배포 담당자 단독. 설명은 post-mortem 에서.

### 8.6 Stage 3 (후속) 마이그레이션 힌트 — 본 설계 범위 밖

- Private repository: `repositories.visibility` enum + anonymous pull gate 에 repo-level 체크
- Multi-arch / OCI image index: manifest list 지원 컬럼
- JWT dual-key rotation: `jwt_keys` 배열 + `kid` 분기 (TODOS P2)
- NAT-aware throttling: rack-attack key `(username, ip)` (TODOS P2)

Stage 0/1/2 설계는 이 미래 확장을 차단하지 않는 경로로 설계됨.

---

## 9. Risk & Deferred

### 9.1 감수한 trade-off

| Trade-off | 근거 |
|---|---|
| `primary_identity_id` DB 레벨 NULLABLE + after_commit 보장 | SQLite non-deferrable FK 제약. SessionCreator 트랜잭션 contract 로 효과적 NOT NULL |
| JWT 15분 revocation window | distribution spec 호환성 + revocation DB lookup 성능 회피. 15분 허용 risk < operational simplicity |
| First-pusher-owner (GitHub 스타일) | CI dynamic repo naming 지원 > repo 난립 관리 비용 |
| `iss == aud == service_name` | 단일 서비스, 외부 위임 계획 없음. 분화 필요해지면 추후 audience 구분 |
| `kind` 컬럼 (cli/ci) 으로 만료 차등 | CI credential rotation 부담 vs 테이블 복잡도 +1 컬럼. 실사용 UX 이득 큼 |

### 9.2 Defer 된 항목 (TODOS.md 로 기록 완료)

- [P0] RSpec→Minitest 포팅 (Stage 0 선행 블로커)
- [P2] JWT signing key rotation procedure
- [P2] NAT-aware `/v2/token` throttling for CI
- [P2] Tag protection policy change audit (기존)
- [P2] Policy transition impact preview (기존)

### 9.3 크리티컬 갭 (테스트 커버리지)

3건 모두 `test/integration/` 에 구현, CI 하드 게이트:
1. Retention job × Stage 2 ownership 상호작용
2. First-pusher race condition
3. Anonymous pull regression

---

## Handoff

이 spec 은 `/superpowers:writing-plans` 로 넘겨져 Stage 0 구현 plan 이 된다. 각 Stage 마다 별도의 plan 문서 (`docs/superpowers/plans/2026-04-23-registry-auth-stage{0,1,2}-plan.md`) 가 생성되고, 각 plan 은 해당 Stage 의 3–4 PR 을 TDD Red-Green-Refactor + Tidy First 순서로 분해한다.

첫 실행 대상: **Blocker A (RSpec→Minitest 포팅)**. 포팅 완료 후 **Stage 0 plan** 부터 착수.
