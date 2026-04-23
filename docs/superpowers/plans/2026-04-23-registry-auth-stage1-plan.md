# Registry Auth Stage 1 Implementation Plan (옵션 1: PAT Basic Auth)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Docker Registry V2 push/delete 경로를 Personal Access Token 기반 **HTTP Basic** 인증으로 전환하고, `TagEvent.actor` 를 `"anonymous"` 하드코딩에서 실제 로그인 이메일로 실명화한다. Pull 은 flag-gated anonymous 허용 유지.

**Auth scheme 결정 (tech design D9, 2026-04-23 변경):** JWT Bearer 대신 PAT HTTP Basic auth 채택. Docker CLI 의 distribution spec 는 Basic scheme 도 허용 (`WWW-Authenticate: Basic realm="..."`). 사내 단일 registry 규모에서 JWT 의 stateless 검증 / scope 분리 / 외부 IdP federation 이점은 비용 대비 미미. 외부 노출 / federation 요구가 생기면 PAT 모델 위에 Bearer 레이어를 추가하는 식으로 발전 (PAT 모델 재사용, 마이그레이션 비용 작음). 자세한 trade-off: tech design §3.8 표.

**Architecture:**
- Docker CLI 는 distribution spec challenge–response 로 `WWW-Authenticate: Basic realm="Registry"` 를 받고 `Authorization: Basic base64(email:pat_raw)` 로 같은 요청을 재시도. token exchange 단계 없음 (Bearer flow 와 달리).
- `PersonalAccessToken` (SHA256 digest) 으로 `Auth::PatAuthenticator` 가 email + digest 매칭 → `V2::BaseController#authenticate_v2_basic!` (before_action) 가 `current_user` / `current_pat` 설정.
- `actor:` 는 `ManifestProcessor`, `ImageImportService`, `ProcessTarImportJob` 에 required keyword 로 전파되어 `TagEvent` 에 실명 이메일을 기록. `ProcessTarImportJob` 의 session-less 경로는 `"system:import"` fallback.
- 2 PR 분할. PR-1 은 Tidy First 의 structural 전용 (behavior 불변), PR-2 는 behavioral 일괄.

**Tech Stack:** Rails 8.1, Minitest, SQLite, rack-attack (6.8.0), omniauth-google-oauth2 (Stage 0 상속), Hotwire, ViewComponent. (JWT 라이브러리 `jwt` / RSA 키쌍은 불필요.)

**Source spec:** `docs/superpowers/specs/2026-04-23-registry-auth-tech-design.md` D9, §1.2, §2.1, §2.4, §3, §4 (actor 주입), §4.7 (PR 분할), §5 (PAT 보안 모델), §6.1–6.5, §6.7, §7.3 (Critical Gap #3), §7.4 (CI 하드 게이트), §8.2 Stage 1 체크리스트, §8.3 Stage 1 rollback.

**Branching strategy:**
- `feature/registry-auth-stage1-pr1` — Phase 1 commits. main 에서 분기.
- `feature/registry-auth-stage1-pr2` — PR-1 머지 후 분기.
- 각 PR 은 독립 green CI 가능해야 함. 병렬 금지.

---

## PR 분할 근거

Tech design D9 (Basic auth 채택) 적용으로 이전 4 PR 분할이 2 PR 로 압축.

| PR | 성격 | 내용 | 이전 4 PR 매핑 |
|---|---|---|---|
| **PR-1** | structural | `actor:` required kwarg 도입 (호출자는 `"anonymous"` 명시 유지) + `admin_email` / `anonymous_pull_enabled` 만 로드하는 initializer | 옛 PR-1 (structural) |
| **PR-2** | behavioral | PAT 모델 + `Auth::PatAuthenticator` + V2 Basic auth gate + V2/Web UI 실명화 + `display_actor` + anonymous pull gate + Critical Gap #3 regression + ProcessTarImportJob `actor_email:` 전파 + Settings::TokensController CRUD UI + Navigation + System test + rack-attack on V2 protected paths | 옛 PR-2 일부 (PAT 모델) + 옛 PR-3 전체 (auth gate + 실명화) + 옛 PR-4 전체 (Import + UI) |

**PR-2 가 큰 이유:** `V2::BaseController#authenticate_v2_basic!` (auth gate) 이 먼저 있어야 `actor: current_user.email` 실명화가 가능. auth gate 와 실명화를 같은 PR 에 묶는다. JWT TokenIssuer/Verifier / `V2::TokensController` / `/v2/token` endpoint / RSA 키쌍 관리가 빠지면서 실제 코드량은 옛 4 PR 합계 대비 ~1/3 수준.

**PR-2 내부 커밋은 task 단위로 분리** (13 commits 예상) — review 단계에서 fine-grained 추적 가능.

---

## Prerequisites

### P1. `REGISTRY_ADMIN_EMAIL` 확인 (Stage 0 에서 이미 설정)

```bash
echo "${REGISTRY_ADMIN_EMAIL:-UNSET}"
# 기대: tonny@timberay.com 또는 admin@timberay.com
```

미설정이면 `.env` 또는 shell profile 에 `export REGISTRY_ADMIN_EMAIL=<이메일>` 추가. staging/prod 는 devops 와 별도 협의.

### P2. Stage 0 main 머지 확인

```bash
git log main --oneline -20 | grep -iE "omniauth|google|session"
```

Stage 0 (OmniAuth Google 로그인) 이 main 에 머지된 상태여야 함 (commit 733c3fa 기준 — 2026-04-23 시점 완료).

### P3. `REGISTRY_ANONYMOUS_PULL` ENV (선택, default 동작)

```bash
# .env 또는 shell profile
export REGISTRY_ANONYMOUS_PULL=true
```

미설정 시 `config/initializers/registry.rb` 의 default 가 `"true"` → 동일 동작. 개발 단계에서는 생략 가능.

### 이전 plan 의 P1–P5 (JWT 관련) — 불필요

옵션 1 (Basic auth) 채택으로 다음 항목은 **삭제**:
- RSA 키쌍 생성 (`openssl genrsa`) — **불필요**
- `config/credentials/<env>.yml.enc` 의 `jwt:` 블록 — **불필요**
- `REGISTRY_JWT_ISSUER` / `REGISTRY_JWT_AUDIENCE` ENV — **불필요**
- `test/fixtures/files/keys/` 디렉토리 — **불필요** (이미 생성된 test 키쌍은 Task 1.1 Step 1 에서 정리)

`.gitignore` 의 `/config/credentials/*.key` 패턴은 Basic 에서도 다른 credential 보호 용으로 유용 — **유지**.

---

## Phase 1 — PR-1 Structural: `actor:` required kwarg

### Scope

| 파일 | 변경 |
|---|---|
| `app/services/manifest_processor.rb` | `call` / `assign_tag!` 에 `actor:` required kwarg. 내부는 `"anonymous"` 로 설정된 값을 그대로 전달 (behavior 불변) |
| `app/controllers/v2/manifests_controller.rb` | `ManifestProcessor.new.call(..., actor: "anonymous")` — 명시적 전달 |
| `app/services/image_import_service.rb` | `call` 에 `actor:` required kwarg. 내부 `ManifestProcessor` 호출 시 `actor: actor` 전파 |
| `app/jobs/process_tar_import_job.rb` | `ImageImportService.new.call(..., actor: "anonymous")` — 명시적 전달 |
| `config/initializers/registry.rb` | `admin_email` + `anonymous_pull_enabled` 만 로드 |
| `test/test_helper.rb` | `Rails.configuration.x.registry` 테스트 기본값 setup |
| 기존 테스트 | 위 호출자 변경 반영 (keyword 추가) |

**목표:** Red (ArgumentError) → Green (kwarg 추가) 사이클. 모든 behavior 는 `"anonymous"` 그대로 유지. `TagEvent.actor` 값 변화 **없음**.

### Task 1.1: registry initializer 확장 + test helper setup + 불필요 fixture 정리

**Files:**
- Modify: `config/initializers/registry.rb`
- Modify: `test/test_helper.rb`
- Create: `test/initializers/registry_config_test.rb` (신규 디렉토리)
- Delete: `test/fixtures/files/keys/` (옵션 1 채택 전 생성된 잔여물)

**출발 상태:** `config/initializers/registry.rb` 는 `admin_email` 만 로드. `test_helper.rb` 는 fixtures / parallelize 만.

- [ ] **Step 1: 불필요 fixture 디렉토리 삭제**

```bash
cd /home/tonny/projects/open-repo
rm -rf test/fixtures/files/keys/
```

Basic auth 로 전환했기 때문에 JWT test 키쌍은 사용되지 않음. 디렉토리가 이미 없으면 skip.

- [ ] **Step 2: Write failing test**

Create `test/initializers/registry_config_test.rb`:

```ruby
require "test_helper"

class RegistryConfigTest < ActiveSupport::TestCase
  test "loads admin_email from test_helper default" do
    assert_equal "admin@timberay.com", Rails.configuration.x.registry.admin_email
  end

  test "anonymous_pull_enabled is true by default" do
    assert_equal true, Rails.configuration.x.registry.anonymous_pull_enabled
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bin/rails test test/initializers/registry_config_test.rb -v
```

Expected: 2 FAIL (method missing or nil on `Rails.configuration.x.registry`).

- [ ] **Step 4: Overwrite `config/initializers/registry.rb`**

```ruby
Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
  config.x.registry.anonymous_pull_enabled =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REGISTRY_ANONYMOUS_PULL", "true"))
end
```

- [ ] **Step 5: Modify `test/test_helper.rb`**

기존 `test_helper.rb` 의 `class ActiveSupport::TestCase` 블록에 `setup do` 추가 (다른 setup 이 이미 있으면 해당 블록 안에 병합):

```ruby
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  fixtures :all

  setup do
    Rails.configuration.x.registry.admin_email            = "admin@timberay.com"
    Rails.configuration.x.registry.anonymous_pull_enabled = true
  end
end
```

**주의:** 기존 `test_helper.rb` 에 `webmock` require 나 다른 설정이 있을 수 있음 — 삭제 금지. 위 `setup do` 블록만 class body 안에 추가.

- [ ] **Step 6: Run test to verify PASS**

```bash
bin/rails test test/initializers/registry_config_test.rb -v
```

Expected: 2 PASS.

- [ ] **Step 7: Full suite regression**

```bash
bin/rails test
```

Expected: 337+ runs, 0 failures. (Stage 0 baseline 유지.)

- [ ] **Step 8: Commit**

```bash
git checkout -b feature/registry-auth-stage1-pr1
git add config/initializers/registry.rb test/test_helper.rb test/initializers/registry_config_test.rb .gitignore
git commit -m "chore(registry): load admin_email + anonymous_pull_enabled from ENV"
```

**주의:** `.gitignore` 의 `/config/credentials/*.key` 패턴도 같은 커밋에 포함 (옵션 1 과 무관한 안전망이므로 유지).

---

### Task 1.2: `ManifestProcessor` — `actor:` required kwarg

**Files:**
- Modify: `app/services/manifest_processor.rb`
- Modify: `app/controllers/v2/manifests_controller.rb` (호출자 — `actor: "anonymous"` 명시)
- Modify: `test/services/manifest_processor_test.rb`
- Modify: 기타 `ManifestProcessor.new.call` 을 직접 호출하는 테스트 (grep 으로 발견)

- [ ] **Step 1: Write the failing test — ArgumentError without actor:**

Append to `test/services/manifest_processor_test.rb`:

```ruby
test "call without actor: raises ArgumentError" do
  assert_raises(ArgumentError, /missing keyword: :actor/) do
    ManifestProcessor.new.call(
      "repo-no-actor",
      "v1",
      "application/vnd.docker.distribution.manifest.v2+json",
      "{}"
    )
  end
end

test "call with actor: 'anonymous' writes TagEvent.actor = 'anonymous'" do
  manifest_json = valid_manifest_payload_fixture  # 기존 helper
  assert_difference -> { TagEvent.where(actor: "anonymous").count }, +1 do
    ManifestProcessor.new.call(
      "repo-actor-kwarg",
      "v1",
      "application/vnd.docker.distribution.manifest.v2+json",
      manifest_json,
      actor: "anonymous"
    )
  end
end
```

**주의:** `valid_manifest_payload_fixture` 는 기존 ManifestProcessor 테스트에서 사용 중인 helper 재사용. 없으면 spec 내 단일 literal JSON 문자열로 대체.

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/services/manifest_processor_test.rb -v
```

Expected: 2 FAIL (전자: 현재는 `actor:` 없이 성공, 후자: 현재는 `actor:` keyword 거부).

- [ ] **Step 3: Modify `app/services/manifest_processor.rb`**

```ruby
class ManifestProcessor
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(repo_name, reference, content_type, payload, actor:)
    # ... (existing parse / repository resolution code — unchanged) ...
    repository.with_lock do
      # ... (existing manifest persistence — unchanged) ...
      assign_tag!(repository, tag_name, manifest, actor: actor) if tag_name
      manifest
    end
  end

  private

  def assign_tag!(repository, tag_name, manifest, actor:)
    existing_tag = repository.tags.find_by(name: tag_name)
    if existing_tag
      old_digest = existing_tag.manifest.digest
      if old_digest != manifest.digest
        existing_tag.update!(manifest: manifest)
        TagEvent.create!(
          repository: repository,
          tag_name: tag_name,
          action: "update",
          previous_digest: old_digest,
          new_digest: manifest.digest,
          actor: actor,
          occurred_at: Time.current
        )
      end
    else
      Tag.create!(repository: repository, name: tag_name, manifest: manifest)
      TagEvent.create!(
        repository: repository,
        tag_name: tag_name,
        action: "create",
        new_digest: manifest.digest,
        actor: actor,
        occurred_at: Time.current
      )
    end
  end
end
```

**주의:** diff 의 범위 외 부분 (manifest parse / BlobStore 연결 / with_lock 본체) 은 원본 유지. `assign_tag!` 호출 라인 하나에 `actor: actor` 키워드 전달.

- [ ] **Step 4: Modify `app/controllers/v2/manifests_controller.rb` 호출부**

```ruby
manifest = ManifestProcessor.new.call(
  repo_name,
  params[:reference],
  request.content_type,
  payload,
  actor: "anonymous"
)
```

**주의:** `current_user.email` 전환은 PR-2 Task 2.5 에서. PR-1 은 structural only — `"anonymous"` 명시.

- [ ] **Step 5: Grep + fix other callers**

```bash
rg -n "ManifestProcessor.new.call" test/ app/
```

호출자마다 `actor: "anonymous"` 추가 (behavior 그대로 유지).

- [ ] **Step 6: Run tests**

```bash
bin/rails test test/services/manifest_processor_test.rb test/controllers/v2/manifests_controller_test.rb -v
```

Expected: PASS.

- [ ] **Step 7: Full suite regression**

```bash
bin/rails test
```

Expected: 0 failures. `TagEvent.actor` 는 여전히 `"anonymous"`.

- [ ] **Step 8: Commit**

```bash
git add app/services/manifest_processor.rb app/controllers/v2/manifests_controller.rb test/services/manifest_processor_test.rb test/controllers/v2/manifests_controller_test.rb
git commit -m "refactor(registry): require actor: kwarg in ManifestProcessor#call"
```

---

### Task 1.3: `ImageImportService` + `ProcessTarImportJob` — `actor:` required kwarg

**Files:**
- Modify: `app/services/image_import_service.rb`
- Modify: `app/jobs/process_tar_import_job.rb`
- Modify: `test/services/image_import_service_test.rb`
- Modify: `test/jobs/process_tar_import_job_test.rb`

- [ ] **Step 1: Write the failing test for `ImageImportService`**

Append to `test/services/image_import_service_test.rb`:

```ruby
test "call without actor: raises ArgumentError" do
  tar_path = Rails.root.join("test/fixtures/files/sample.tar").to_s
  assert_raises(ArgumentError, /missing keyword: :actor/) do
    ImageImportService.new.call(tar_path, repository_name: "r", tag_name: "v1")
  end
end
```

**주의:** `sample.tar` 가 없으면 기존 import 테스트의 fixture 경로 재사용. grep 으로 위치 확인.

- [ ] **Step 2: Write the failing test for `ProcessTarImportJob`**

Append to `test/jobs/process_tar_import_job_test.rb`:

```ruby
test "perform forwards actor: 'anonymous' to ImageImportService" do
  import = imports(:pending_import)
  service = Minitest::Mock.new
  service.expect(:call, nil, [import.tar_path], actor: "anonymous", repository_name: import.repository_name, tag_name: import.tag_name)

  ImageImportService.stub(:new, service) do
    ProcessTarImportJob.new.perform(import.id)
  end
  service.verify
end
```

**주의:** `imports(:pending_import)` fixture 가 없으면 test 내 `Import.create!(...)` 로 대체.

- [ ] **Step 3: Run tests to verify FAIL**

```bash
bin/rails test test/services/image_import_service_test.rb test/jobs/process_tar_import_job_test.rb -v
```

Expected: 2 FAIL.

- [ ] **Step 4: Modify `app/services/image_import_service.rb`**

```ruby
class ImageImportService
  # ... (기존 initialize, 기타 private 메서드 그대로) ...

  def call(tar_path, actor:, repository_name: nil, tag_name: nil)
    # ... (기존 tar 파싱 unchanged) ...
    processor = ManifestProcessor.new(@blob_store)
    processor.call(
      repo_name,
      tag,
      "application/vnd.docker.distribution.manifest.v2+json",
      v2_manifest.to_json,
      actor: actor
    )
  end
end
```

**주의:** `actor:` 는 required keyword. 위치는 `tar_path` 직후 (다른 kwarg 보다 먼저).

- [ ] **Step 5: Modify `app/jobs/process_tar_import_job.rb`**

```ruby
class ProcessTarImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Import.find(import_id)
    import.update!(status: "processing", progress: 10)

    begin
      ImageImportService.new.call(
        import.tar_path,
        actor: "anonymous",
        repository_name: import.repository_name,
        tag_name: import.tag_name
      )
      import.update!(status: "completed", progress: 100)
    rescue => e
      import.update!(status: "failed", error_message: e.message)
      raise
    end
  end
end
```

**주의:** `actor_email:` 로 확장하는 건 PR-2 Task 2.10. 이 커밋은 `"anonymous"` 그대로.

- [ ] **Step 6: Run modified tests**

```bash
bin/rails test test/services/image_import_service_test.rb test/jobs/process_tar_import_job_test.rb -v
```

Expected: PASS.

- [ ] **Step 7: Full suite regression**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/services/image_import_service.rb app/jobs/process_tar_import_job.rb test/services/image_import_service_test.rb test/jobs/process_tar_import_job_test.rb
git commit -m "refactor(registry): require actor: kwarg in ImageImportService + ProcessTarImportJob"
```

---

### Task 1.4: PR-1 pre-flight + PR open

- [ ] **Step 1: Full CI-equivalent check**

```bash
cd /home/tonny/projects/open-repo
bin/rails test
bin/rubocop
bin/brakeman --no-pager
```

Expected: 모두 green.

- [ ] **Step 2: `TagEvent.actor` 불변 확인 (integration)**

```bash
bin/rails runner 'p TagEvent.pluck(:actor).tally'
```

Expected: `"anonymous"` 와 `"retention-policy"` 만 존재. 실명 이메일은 아직 없음 (PR-2 에서 등장).

- [ ] **Step 3: Push + PR open**

```bash
git push -u origin feature/registry-auth-stage1-pr1
gh pr create --title "feat(registry): Stage 1 PR-1 — actor: required kwarg (structural)" --body "$(cat <<'EOF'
## Summary
- Introduce `actor:` as required keyword to `ManifestProcessor#call` / `assign_tag!`, `ImageImportService#call`.
- All callers pass `actor: "anonymous"` explicitly. No behavior change.
- Simplify `config/initializers/registry.rb` to load `admin_email` + `anonymous_pull_enabled` only (JWT keys removed — option 1 / Basic auth decided in tech design D9).

## Acceptance (Stage 1 PR-1)
- [x] `TagEvent.actor` values unchanged in integration suite
- [x] `bin/rails test` green (337+ runs)
- [x] `bin/rubocop`, `bin/brakeman` green
- [x] No production behavior change

## Notes
Tidy First — structural only. Behavioral transition (PAT model + Basic auth gate + `current_user.email`) lands in PR-2.

🤖 Generated with Claude Code
EOF
)"
```

- [ ] **Step 4: Confirm PR merged to main before starting Phase 2**

wait for code review + CI green + merge. 이후 `git checkout main && git pull origin main` 로 로컬 동기화.

---

## Phase 2 — PR-2 Behavioral: PAT + V2 Basic auth + 실명화 + Settings UI

### Scope

| 파일 | 변경 |
|---|---|
| `db/migrate/YYYYMMDDHHMMSS_create_personal_access_tokens.rb` | 신규 migration (tech design §1.2) |
| `app/models/personal_access_token.rb` | 신규. `.active` scope, `authenticate_raw` class method, `revoke!`, `generate_raw` |
| `app/models/identity.rb` | `has_many :personal_access_tokens, dependent: :destroy` |
| `app/errors/auth.rb` | `Unauthenticated`, `PatInvalid` 추가 |
| `app/services/auth/pat_authenticator.rb` | 신규. email + raw token → (user, pat) |
| `app/controllers/v2/base_controller.rb` | `authenticate_v2_basic!` + `anonymous_pull_allowed?` + `render_v2_challenge` + `current_user`/`current_pat` |
| `app/controllers/v2/manifests_controller.rb` | `ManifestProcessor.new.call(..., actor: current_user.email)` + DELETE TagEvent actor |
| `app/controllers/tags_controller.rb` | `destroy` 의 TagEvent actor → `current_user.email` (Web UI) |
| `app/models/tag_event.rb` | `display_actor` helper |
| `app/jobs/process_tar_import_job.rb` | `perform(id, actor_email:)` kwarg. fallback `"system:import"` |
| `app/controllers/imports_controller.rb` | `ProcessTarImportJob.perform_later(..., actor_email: current_user&.primary_identity&.email)` |
| `app/controllers/settings/tokens_controller.rb` | 신규. `index` / `create` / `destroy` |
| `app/views/settings/tokens/` | `index.html.erb`, `_form.html.erb`, `_token_row.html.erb` |
| `app/components/nav_component.html.erb` (or `app/views/layouts/_nav.html.erb`) | "Tokens" 링크 (signed-in only) |
| `config/routes.rb` | `namespace :settings { resources :tokens }` |
| `config/initializers/rack_attack.rb` | V2 protected paths throttle (분당 N회 per IP) |
| `test/fixtures/personal_access_tokens.yml` | active / ci / revoked / expired 4 rows |
| `test/support/token_fixtures.rb` | raw token 상수 모듈 |
| `test/integration/docker_basic_auth_test.rb` | V2 Basic auth 통합 시나리오 |
| `test/integration/anonymous_pull_regression_test.rb` | Critical Gap #3 (tech design §7.3) |
| `test/system/settings_tokens_test.rb` | PAT CRUD flow |
| `.github/workflows/ci.yml` | critical gap hard gate |

**목표:** 로그인 사용자가 Web UI 에서 PAT 발급/폐기. Docker CLI 가 PAT Basic auth 로 push/delete 시 `TagEvent.actor` 실명 기록. Anonymous pull 은 GET/HEAD + whitelist endpoints + `anonymous_pull_enabled=true` 조건에서 허용.

---

### Task 2.1: Migration — `personal_access_tokens`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_personal_access_tokens.rb`
- Modify: `db/schema.rb` (자동 생성)
- Create: `app/models/personal_access_token.rb` (skeleton)

- [ ] **Step 1: Generate migration**

```bash
git checkout main && git pull origin main
git checkout -b feature/registry-auth-stage1-pr2
bin/rails g migration CreatePersonalAccessTokens
```

- [ ] **Step 2: Overwrite migration file** (timestamp 은 Rails 자동 생성 유지)

```ruby
class CreatePersonalAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_access_tokens do |t|
      t.references :identity, null: false, foreign_key: { on_delete: :cascade }
      t.string   :name,         null: false
      t.string   :token_digest, null: false
      t.string   :kind,         null: false, default: "cli"
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, [:identity_id, :name], unique: true
    add_index :personal_access_tokens, :revoked_at
  end
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
bin/rails db:migrate RAILS_ENV=test
```

- [ ] **Step 4: Verify schema**

```bash
bin/rails runner 'puts PersonalAccessToken.connection.columns("personal_access_tokens").map { |c| [c.name, c.type, c.null, c.default] }.inspect'
```

Expected: 8 column spec (identity_id, name, token_digest, kind=cli, last_used_at, expires_at, revoked_at, created_at, updated_at).

- [ ] **Step 5: Create model skeleton**

`app/models/personal_access_token.rb`:

```ruby
class PersonalAccessToken < ApplicationRecord
  belongs_to :identity
end
```

(본격 내용은 Task 2.2.)

- [ ] **Step 6: Commit (structural)**

```bash
git add db/migrate db/schema.rb app/models/personal_access_token.rb
git commit -m "feat(registry): add personal_access_tokens table + identity FK"
```

---

### Task 2.2: `PersonalAccessToken` 모델 + `.active` scope + `authenticate_raw` + `generate_raw` + `revoke!`

**Files:**
- Modify: `app/models/personal_access_token.rb`
- Modify: `app/models/identity.rb`
- Create: `test/fixtures/personal_access_tokens.yml`
- Create: `test/support/token_fixtures.rb`
- Create: `test/models/personal_access_token_test.rb`
- Modify: `test/test_helper.rb` (support 디렉토리 autoload)

- [ ] **Step 1: Create fixtures**

`test/fixtures/personal_access_tokens.yml`:

```yaml
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

tonny_expired:
  identity: tonny_google
  name: "ancient-laptop"
  token_digest: <%= Digest::SHA256.hexdigest("oprk_test_tonny_expired_raw") %>
  kind: cli
  expires_at: <%= 1.day.ago %>
  created_at: <%= 100.days.ago %>
  updated_at: <%= 100.days.ago %>
```

**주의:** `tonny_google` identity fixture 는 Stage 0 에서 생성됨 (`test/fixtures/identities.yml`).

- [ ] **Step 2: Create `test/support/token_fixtures.rb`**

```ruby
module TokenFixtures
  TONNY_CLI_RAW      = "oprk_test_tonny_cli_raw".freeze
  TONNY_CI_RAW       = "oprk_test_tonny_ci_raw".freeze
  TONNY_REVOKED_RAW  = "oprk_test_tonny_revoked_raw".freeze
  TONNY_EXPIRED_RAW  = "oprk_test_tonny_expired_raw".freeze
end
```

- [ ] **Step 3: Load `test/support` in test_helper**

Append to `test/test_helper.rb` — `class ActiveSupport::TestCase` 선언 **앞**:

```ruby
Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }
```

- [ ] **Step 4: Write failing model tests**

`test/models/personal_access_token_test.rb`:

```ruby
require "test_helper"

class PersonalAccessTokenTest < ActiveSupport::TestCase
  include TokenFixtures

  test ".active excludes revoked" do
    assert_not_includes PersonalAccessToken.active, personal_access_tokens(:tonny_revoked)
  end

  test ".active excludes expired" do
    assert_not_includes PersonalAccessToken.active, personal_access_tokens(:tonny_expired)
  end

  test ".active includes never-expiring ci kind" do
    assert_includes PersonalAccessToken.active, personal_access_tokens(:tonny_ci_never_expires)
  end

  test ".active includes unexpired cli" do
    assert_includes PersonalAccessToken.active, personal_access_tokens(:tonny_cli_active)
  end

  test ".authenticate_raw returns token for matching raw secret" do
    found = PersonalAccessToken.authenticate_raw(TONNY_CLI_RAW)
    assert_equal personal_access_tokens(:tonny_cli_active), found
  end

  test ".authenticate_raw returns nil for non-existent raw" do
    assert_nil PersonalAccessToken.authenticate_raw("oprk_nonexistent")
  end

  test ".authenticate_raw returns nil for revoked PAT (via .active)" do
    assert_nil PersonalAccessToken.authenticate_raw(TONNY_REVOKED_RAW)
  end

  test ".authenticate_raw returns nil for expired PAT" do
    assert_nil PersonalAccessToken.authenticate_raw(TONNY_EXPIRED_RAW)
  end

  test ".generate_raw returns oprk_-prefixed url-safe string" do
    raw = PersonalAccessToken.generate_raw
    assert_match(/\Aoprk_[A-Za-z0-9_-]+\z/, raw)
    assert_operator raw.length, :>=, 40
  end

  test "#revoke! sets revoked_at" do
    pat = personal_access_tokens(:tonny_cli_active)
    pat.revoke!
    assert_not_nil pat.reload.revoked_at
  end

  test "validates name uniqueness per identity" do
    dup = PersonalAccessToken.new(
      identity: identities(:tonny_google),
      name: "laptop",
      token_digest: "dup_digest",
      kind: "cli"
    )
    assert_not dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end
end
```

- [ ] **Step 5: Verify FAIL**

```bash
bin/rails test test/models/personal_access_token_test.rb -v
```

Expected: 대부분 NoMethodError / undefined scope.

- [ ] **Step 6: Implement `app/models/personal_access_token.rb`**

```ruby
class PersonalAccessToken < ApplicationRecord
  RAW_PREFIX = "oprk_".freeze

  belongs_to :identity

  validates :name, presence: true, uniqueness: { scope: :identity_id }
  validates :token_digest, presence: true, uniqueness: true
  validates :kind, inclusion: { in: %w[cli ci] }

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  def self.generate_raw
    RAW_PREFIX + SecureRandom.urlsafe_base64(32)
  end

  # @param raw_token [String]
  # @return [PersonalAccessToken, nil]
  def self.authenticate_raw(raw_token)
    return nil if raw_token.blank?
    active.find_by(token_digest: Digest::SHA256.hexdigest(raw_token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
```

- [ ] **Step 7: Modify `app/models/identity.rb`**

Append to class body:

```ruby
has_many :personal_access_tokens, dependent: :destroy
```

- [ ] **Step 8: Verify PASS**

```bash
bin/rails test test/models/personal_access_token_test.rb -v
```

Expected: 11 PASS.

- [ ] **Step 9: Full suite regression**

```bash
bin/rails test
```

- [ ] **Step 10: Commit**

```bash
git add app/models/personal_access_token.rb app/models/identity.rb test/fixtures/personal_access_tokens.yml test/support/token_fixtures.rb test/models/personal_access_token_test.rb test/test_helper.rb
git commit -m "feat(registry): PersonalAccessToken model + .active scope + authenticate_raw"
```

---

### Task 2.3: Auth 에러 확장 + `Auth::PatAuthenticator`

**Files:**
- Modify: `app/errors/auth.rb` (기존 Stage 0 errors 에 추가)
- Create: `app/services/auth/pat_authenticator.rb`
- Create: `test/services/auth/pat_authenticator_test.rb`

- [ ] **Step 1: Extend `app/errors/auth.rb`**

기존 파일에 추가 (Stage 0 errors 유지):

```ruby
module Auth
  class Error < StandardError; end

  # Stage 0 (existing)
  class InvalidProfile   < Error; end
  class EmailMismatch    < Error; end
  class ProviderOutage   < Error; end

  # Stage 1 (new)
  class Unauthenticated  < Error; end   # no/malformed Authorization header
  class PatInvalid       < Error; end   # PAT not found / revoked / expired / email mismatch
end
```

- [ ] **Step 2: Write failing test**

`test/services/auth/pat_authenticator_test.rb`:

```ruby
require "test_helper"

class Auth::PatAuthenticatorTest < ActiveSupport::TestCase
  include TokenFixtures

  test "returns (user, pat) for matching email + active raw token" do
    result = Auth::PatAuthenticator.new.call(
      email: "tonny@timberay.com",
      raw_token: TONNY_CLI_RAW
    )
    assert_equal users(:tonny), result.user
    assert_equal personal_access_tokens(:tonny_cli_active), result.pat
  end

  test "email matching is case-insensitive" do
    result = Auth::PatAuthenticator.new.call(
      email: "Tonny@Timberay.COM",
      raw_token: TONNY_CLI_RAW
    )
    assert_equal users(:tonny), result.user
  end

  test "raises PatInvalid when raw token is unknown" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "tonny@timberay.com", raw_token: "oprk_bogus")
    end
  end

  test "raises PatInvalid when PAT is revoked" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "tonny@timberay.com", raw_token: TONNY_REVOKED_RAW)
    end
  end

  test "raises PatInvalid when PAT is expired" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "tonny@timberay.com", raw_token: TONNY_EXPIRED_RAW)
    end
  end

  test "raises PatInvalid when email does not match pat.identity.user.email" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "admin@timberay.com", raw_token: TONNY_CLI_RAW)
    end
  end

  test "raises PatInvalid when email is blank" do
    assert_raises(Auth::PatInvalid) do
      Auth::PatAuthenticator.new.call(email: "", raw_token: TONNY_CLI_RAW)
    end
  end
end
```

- [ ] **Step 3: Verify FAIL**

```bash
bin/rails test test/services/auth/pat_authenticator_test.rb -v
```

- [ ] **Step 4: Implement `app/services/auth/pat_authenticator.rb`**

```ruby
module Auth
  class PatAuthenticator
    Result = Data.define(:user, :pat)

    # @param email     [String]
    # @param raw_token [String]
    # @return [Result]
    # @raise [Auth::PatInvalid]
    def call(email:, raw_token:)
      raise Auth::PatInvalid, "email blank" if email.blank?
      raise Auth::PatInvalid, "token blank" if raw_token.blank?

      pat = PersonalAccessToken.authenticate_raw(raw_token)
      raise Auth::PatInvalid, "unknown or inactive PAT" if pat.nil?

      user = pat.identity.user
      unless user.email.to_s.downcase == email.to_s.downcase
        raise Auth::PatInvalid, "email mismatch"
      end

      Result.new(user: user, pat: pat)
    end
  end
end
```

- [ ] **Step 5: Verify PASS**

```bash
bin/rails test test/services/auth/pat_authenticator_test.rb -v
```

Expected: 7 PASS.

- [ ] **Step 6: Full suite regression**

```bash
bin/rails test
```

- [ ] **Step 7: Commit**

```bash
git add app/errors/auth.rb app/services/auth/pat_authenticator.rb test/services/auth/pat_authenticator_test.rb
git commit -m "feat(registry): Auth::PatAuthenticator + PatInvalid/Unauthenticated errors"
```

---

### Task 2.4: `V2::BaseController#authenticate_v2_basic!` + anonymous pull gate + `render_v2_challenge`

**Files:**
- Modify: `app/controllers/v2/base_controller.rb`
- Create: `test/controllers/v2/base_controller_test.rb` (없으면)

- [ ] **Step 1: Write failing tests — challenge, Basic auth success, PAT errors, anonymous pull**

`test/controllers/v2/base_controller_test.rb`:

```ruby
require "test_helper"

class V2::BaseControllerTest < ActionDispatch::IntegrationTest
  include TokenFixtures

  # --- Challenge on protected endpoints ---

  test "POST /v2/<name>/blobs/uploads without Authorization → 401 + Basic challenge" do
    post "/v2/myimage/blobs/uploads"
    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
    assert_equal "registry/2.0", response.headers["Docker-Distribution-Api-Version"]
  end

  test "PUT /v2/<name>/manifests/<ref> with malformed Authorization → 401 + challenge" do
    put "/v2/myimage/manifests/v1",
        headers: { "Authorization" => "Basic not-base64!" }
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
  end

  # --- Basic auth success ---

  test "with valid PAT Basic auth → current_user set and request proceeds" do
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_CLI_RAW)
    }
    post "/v2/myimage/blobs/uploads", headers: headers
    # blob upload 실제 로직은 기존 유지 — 여기서는 authenticate_v2_basic! 가 raise 하지 않음만 확인
    assert_not_equal 401, response.status
  end

  test "updates pat.last_used_at on successful auth" do
    pat = personal_access_tokens(:tonny_cli_active)
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_CLI_RAW)
    }
    freeze_time do
      post "/v2/myimage/blobs/uploads", headers: headers
      assert_in_delta Time.current, pat.reload.last_used_at, 2.seconds
    end
  end

  # --- PAT errors ---

  test "with revoked PAT → 401" do
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_REVOKED_RAW)
    }
    post "/v2/myimage/blobs/uploads", headers: headers
    assert_response :unauthorized
  end

  test "with mismatched email → 401" do
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "admin@timberay.com", TONNY_CLI_RAW)
    }
    post "/v2/myimage/blobs/uploads", headers: headers
    assert_response :unauthorized
  end

  # --- Anonymous pull gate (D5 / tech design §7.3) ---

  test "GET /v2/ without Authorization → 200 (anonymous discovery)" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/"
    assert_response :ok
  end

  test "GET /v2/ with anonymous_pull_enabled=false → 401" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/"
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
  end
end
```

- [ ] **Step 2: Verify FAIL**

```bash
bin/rails test test/controllers/v2/base_controller_test.rb -v
```

- [ ] **Step 3: Modify `app/controllers/v2/base_controller.rb`**

```ruby
class V2::BaseController < ActionController::API
  before_action :authenticate_v2_basic!, unless: :anonymous_pull_allowed?

  attr_reader :current_user, :current_pat

  private

  ANONYMOUS_PULL_ENDPOINTS = [
    %w[base      index],
    %w[catalog   index],
    %w[tags      index],
    %w[manifests show],
    %w[blobs     show]
  ].freeze

  def anonymous_pull_allowed?
    return false unless Rails.configuration.x.registry.anonymous_pull_enabled
    return false unless request.get? || request.head?
    ANONYMOUS_PULL_ENDPOINTS.include?([controller_name, action_name])
  end

  def authenticate_v2_basic!
    email, raw = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
    raise Auth::Unauthenticated if email.blank? || raw.blank?

    result = Auth::PatAuthenticator.new.call(email: email, raw_token: raw)
    @current_user = result.user
    @current_pat  = result.pat
    result.pat.update_column(:last_used_at, Time.current)
  rescue ActionController::HttpAuthentication::Basic::HttpBasicAuthenticationError,
         Auth::Unauthenticated,
         Auth::PatInvalid
    render_v2_challenge
  end

  def render_v2_challenge
    response.headers["WWW-Authenticate"]               = %(Basic realm="Registry")
    response.headers["Docker-Distribution-Api-Version"] = "registry/2.0"
    render json: {
      errors: [ { code: "UNAUTHORIZED", message: "authentication required", detail: nil } ]
    }, status: :unauthorized
  end
end
```

**주의:**
- `ActionController::HttpAuthentication::Basic.user_name_and_password` 는 header 파싱 실패 시 nil 또는 예외. rescue 에 포함.
- `update_column` (not `update!`) — validations skip + updated_at 변경 방지. 순수 last_used_at write.
- `controller_name` / `action_name` 매칭은 route mapping 에 의존 — 기존 V2 routes 가 `base#index`, `catalog#index`, `tags#index`, `manifests#show`, `blobs#show` 인지 `rails routes -g /v2` 로 확인 후 상수 값 조정.

- [ ] **Step 4: Verify PASS**

```bash
bin/rails test test/controllers/v2/base_controller_test.rb -v
```

- [ ] **Step 5: Full suite regression**

```bash
bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/v2/base_controller.rb test/controllers/v2/base_controller_test.rb
git commit -m "feat(registry): V2 Basic auth gate + anonymous pull whitelist + challenge helper"
```

---

### Task 2.5: `V2::ManifestsController` — `actor: current_user.email`

**Files:**
- Modify: `app/controllers/v2/manifests_controller.rb`
- Modify: `test/controllers/v2/manifests_controller_test.rb`

- [ ] **Step 1: Write failing test — authenticated PUT writes actor = email**

```ruby
test "authenticated PUT /v2/<name>/manifests/<ref> records TagEvent.actor = current_user.email" do
  headers = {
    "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
      "tonny@timberay.com", TokenFixtures::TONNY_CLI_RAW),
    "Content-Type" => "application/vnd.docker.distribution.manifest.v2+json"
  }

  assert_difference -> { TagEvent.where(actor: "tonny@timberay.com").count }, +1 do
    put "/v2/myimage/manifests/v1",
        params: minimal_manifest_payload,  # 기존 helper
        headers: headers
  end
end

test "authenticated DELETE /v2/<name>/manifests/<digest> records TagEvent.actor = current_user.email" do
  # 기존 fixture: tag 가 이미 있는 repository
  repo = repositories(:myimage_repo)  # 기존 fixture 사용
  manifest = manifests(:v1_manifest)
  headers = {
    "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
      "tonny@timberay.com", TokenFixtures::TONNY_CLI_RAW)
  }

  assert_difference -> { TagEvent.where(actor: "tonny@timberay.com", action: "delete").count }, +1 do
    delete "/v2/#{repo.name}/manifests/#{manifest.digest}", headers: headers
  end
end
```

**주의:** fixture 이름은 기존 테스트에서 grep 으로 확인. 없으면 test 내 `Repository.create!` 로 대체.

- [ ] **Step 2: Verify FAIL** — 현재는 `actor: "anonymous"` 로 기록됨.

```bash
bin/rails test test/controllers/v2/manifests_controller_test.rb -v
```

- [ ] **Step 3: Modify `app/controllers/v2/manifests_controller.rb`**

PUT (update) 핸들러에서:

```ruby
def update
  repo_name = params[:repository_name]
  payload = request.body.read

  manifest = ManifestProcessor.new.call(
    repo_name,
    params[:reference],
    request.content_type,
    payload,
    actor: current_user.email   # PR-1 에서 "anonymous" 였던 자리
  )

  response.headers["Docker-Content-Digest"] = manifest.digest
  response.headers["Location"] = v2_manifest_path(repository_name: repo_name, reference: manifest.digest)
  head :created
end
```

DELETE 핸들러에서 `TagEvent.create!(actor: ...)` 호출 시 `actor: current_user.email`.

- [ ] **Step 4: Verify PASS**

```bash
bin/rails test test/controllers/v2/manifests_controller_test.rb -v
```

- [ ] **Step 5: Full suite regression**

```bash
bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/v2/manifests_controller.rb test/controllers/v2/manifests_controller_test.rb
git commit -m "feat(registry): V2 manifests PUT/DELETE record actor = current_user.email"
```

---

### Task 2.6: `TagsController#destroy` — Web UI actor 실명화

**Files:**
- Modify: `app/controllers/tags_controller.rb` (Web UI 의 tag 삭제 액션)
- Modify: `test/controllers/tags_controller_test.rb`

- [ ] **Step 1: Locate and inspect current destroy**

```bash
rg -n "class TagsController|def destroy" app/controllers/tags_controller.rb
rg -n "actor:" app/controllers/tags_controller.rb
```

현재는 `actor: "anonymous"` 로 하드코딩되어 있을 가능성.

- [ ] **Step 2: Write failing test**

```ruby
test "authenticated destroy records TagEvent.actor = current_user.email" do
  sign_in_as(users(:tonny))
  tag = tags(:existing_tag)
  repo = tag.repository

  assert_difference -> { TagEvent.where(actor: "tonny@timberay.com", action: "delete").count }, +1 do
    delete repo_tag_path(repo, tag)   # 실제 route 명은 `rails routes | grep tags` 로 확인
  end
end
```

**주의:** `sign_in_as` 는 Stage 0 `test/test_helper.rb` 의 기존 helper. route 명은 환경에 따라 `repository_tag_path` 일 수도.

- [ ] **Step 3: Verify FAIL**

- [ ] **Step 4: Modify `TagsController#destroy`**

```ruby
def destroy
  tag = @repository.tags.find_by!(name: params[:id])
  TagEvent.create!(
    repository: @repository,
    tag_name: tag.name,
    action: "delete",
    previous_digest: tag.manifest.digest,
    actor: current_user&.email || "anonymous",
    occurred_at: Time.current
  )
  tag.destroy!
  redirect_to @repository, notice: "Tag deleted."
end
```

**주의:**
- `current_user` 는 Web session 기반 (Stage 0 에서 helper 로 제공). 비로그인 경로는 `nil` → `"anonymous"` fallback.
- Stage 2 에서 `authorize_for!(:delete)` 를 추가 예정 (현재는 단순 실명화).

- [ ] **Step 5: Verify PASS**

- [ ] **Step 6: Commit**

```bash
git add app/controllers/tags_controller.rb test/controllers/tags_controller_test.rb
git commit -m "feat(registry): TagsController#destroy — actor = current_user.email for Web UI"
```

---

### Task 2.7: `TagEvent#display_actor` helper

**Files:**
- Modify: `app/models/tag_event.rb`
- Create (or append): `test/models/tag_event_test.rb`
- Optional: `app/views/` / `app/components/` 내 `event.actor` 직접 출력 → `event.display_actor`

- [ ] **Step 1: Write failing test**

```ruby
require "test_helper"

class TagEventTest < ActiveSupport::TestCase
  test "display_actor returns email unchanged for email-looking actor" do
    event = TagEvent.new(actor: "tonny@timberay.com")
    assert_equal "tonny@timberay.com", event.display_actor
  end

  test "display_actor wraps legacy 'anonymous' as system tag" do
    event = TagEvent.new(actor: "anonymous")
    assert_equal "<system: anonymous>", event.display_actor
  end

  test "display_actor strips 'system:' prefix" do
    event = TagEvent.new(actor: "system:import")
    assert_equal "<system: import>", event.display_actor
  end

  test "display_actor passes through retention-policy as system" do
    event = TagEvent.new(actor: "retention-policy")
    assert_equal "<system: retention-policy>", event.display_actor
  end

  test "display_actor handles nil" do
    event = TagEvent.new(actor: nil)
    assert_equal "<system: >", event.display_actor
  end
end
```

- [ ] **Step 2: Verify FAIL**

- [ ] **Step 3: Modify `app/models/tag_event.rb`**

```ruby
class TagEvent < ApplicationRecord
  belongs_to :repository

  validates :tag_name, presence: true
  validates :action, presence: true, inclusion: { in: %w[create update delete] }
  validates :occurred_at, presence: true

  def display_actor
    return actor if actor.to_s.include?("@")
    "<system: #{actor.to_s.delete_prefix('system:')}>"
  end
end
```

- [ ] **Step 4: Replace `event.actor` in views with `event.display_actor`**

```bash
rg -n "(?:tag_event|event|tag_events|history)\.actor\b" app/views app/helpers app/components
```

각 라인에서 `event.display_actor` 로 교체. view/component 테스트 있으면 보강.

- [ ] **Step 5: Verify PASS + Full suite**

```bash
bin/rails test test/models/tag_event_test.rb -v
bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/models/tag_event.rb test/models/tag_event_test.rb app/views app/helpers app/components
git commit -m "feat(registry): TagEvent#display_actor — email passthrough + system: prefix"
```

---

### Task 2.8: Critical Gap #3 — `anonymous_pull_regression_test.rb`

**Files:**
- Create: `test/integration/anonymous_pull_regression_test.rb`
- Modify: `test/fixtures/repositories.yml` / `manifests.yml` / `tags.yml` / `blobs.yml` (필요 시 `public_*` 추가)
- Create: `test/fixtures/files/empty.txt`

- [ ] **Step 1: Add fixtures required by the regression test**

`test/fixtures/repositories.yml` 에 (없으면):

```yaml
public_repo:
  name: "public-repo"
  created_at: <%= 1.day.ago %>
  updated_at: <%= 1.day.ago %>
```

`manifests.yml`, `tags.yml`, `blobs.yml` 에 대응 레코드 (`public_v1`, `public_v1_tag`, `public_blob`). 기존 fixture 스키마 참조.

```bash
touch /home/tonny/projects/open-repo/test/fixtures/files/empty.txt
```

- [ ] **Step 2: Write regression test** (tech design §7.3 기반, Basic scheme 로 challenge 검증)

```ruby
require "test_helper"

class AnonymousPullRegressionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    @repo     = repositories(:public_repo)
    @manifest = manifests(:public_v1)
    @blob     = blobs(:public_blob)
    @tag      = tags(:public_v1_tag)
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

  test "PUT /v2/:name/manifests/:ref without token 401 + Basic challenge" do
    put "/v2/#{@repo.name}/manifests/newtag",
        params: {}.to_json,
        headers: { "Content-Type" => "application/vnd.docker.distribution.manifest.v2+json" }
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
  end

  test "POST /v2/:name/blobs/uploads without token 401 + Basic challenge" do
    post "/v2/#{@repo.name}/blobs/uploads"
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
  end

  test "DELETE /v2/:name/manifests/:ref without token 401" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_response :unauthorized
  end

  test "when anonymous_pull_enabled=false, GET manifests requires token" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/#{@repo.name}/manifests/#{@tag.name}"
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
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

**주의:**
- `BlobStore.stub_any_instance` 없으면 Mocha / Minitest::Mock 대체 또는 기존 `blobs_controller_test.rb` 의 stub 패턴 재사용.
- `PullEvent` 모델이 존재하지 않으면 해당 테스트 skip + TODO. 확인: `bin/rails runner 'p PullEvent rescue p :none'`.

- [ ] **Step 3: Verify green** — Task 2.4 의 authenticate_v2_basic! + anonymous_pull_allowed? 덕분에 fixture 만 있으면 대부분 green.

```bash
bin/rails test test/integration/anonymous_pull_regression_test.rb -v
```

- [ ] **Step 4: Commit**

```bash
git add test/integration/anonymous_pull_regression_test.rb test/fixtures/repositories.yml test/fixtures/manifests.yml test/fixtures/tags.yml test/fixtures/blobs.yml test/fixtures/files/empty.txt
git commit -m "test(registry): anonymous_pull_regression — Critical Gap #3 (11 scenarios, Basic scheme)"
```

---

### Task 2.9: `docker_basic_auth_test.rb` integration

**Files:**
- Create: `test/integration/docker_basic_auth_test.rb`

- [ ] **Step 1: Write integration scenarios** (tech design §6.5)

```ruby
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
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_REVOKED_RAW)
    }
    put "/v2/myimage/manifests/v1", params: "{}", headers: headers
    assert_response :unauthorized
  end

  test "anonymous pull (anonymous_pull_enabled=true) → 200 without Authorization" do
    seed_image_for("myimage", "v1")   # 기존 helper 또는 fixture seed
    get "/v2/myimage/manifests/v1"
    assert_response :ok
  end
end
```

**주의:** `minimal_manifest_payload` / `seed_image_for` 는 기존 test_helper 또는 이 파일 내에 helper 로 정의. 없으면 minimal JSON literal.

- [ ] **Step 2: Verify green**

```bash
bin/rails test test/integration/docker_basic_auth_test.rb -v
```

- [ ] **Step 3: Commit**

```bash
git add test/integration/docker_basic_auth_test.rb
git commit -m "test(registry): docker_basic_auth — challenge + PAT + TagEvent actor 실명 (4 scenarios)"
```

---

### Task 2.10: `ProcessTarImportJob` — `actor_email:` kwarg + `service:` DI + Imports controller 전달

**Files:**
- Modify: `app/jobs/process_tar_import_job.rb`
- Modify: `app/controllers/imports_controller.rb` (호출자 grep 결과)
- Rewrite: `test/jobs/process_tar_import_job_test.rb` (Task 1.3 의 `define_singleton_method` stub 제거 → DI 기반 테스트)
- Modify: `test/controllers/imports_controller_test.rb`

**Design note (2026-04-23, PR-1 Task 1.3 회고):** 이 프로젝트는 Minitest 6.0.4 를 사용하여 `Minitest::Mock` / `Object.stub` 이 **제거된 상태**. Task 1.3 implementer 가 `define_singleton_method` + `ensure`-restore 기반 수동 stub helper 로 우회했지만, code quality reviewer 가 (1) worker 내 parallel test leakage 리스크, (2) PR-2 전파 시 복리 증가를 지적 (Important). 해결책으로 **`ProcessTarImportJob` 에 injectable service collaborator (`service:` kwarg, default `ImageImportService.new`) 도입**. 테스트는 fake service 를 kwarg 로 주입 — stubbing machinery 전부 삭제. 이 task 는 `actor_email:` 도입과 DI refactor 를 같은 커밋에 묶음 (두 변경 모두 `perform` signature + test 전면 rewrite 이므로 cohesive).

- [ ] **Step 1: Rewrite `test/jobs/process_tar_import_job_test.rb`** — Task 1.3 의 stub helper 전면 제거, DI 기반 4개 테스트

```ruby
require "test_helper"

class ProcessTarImportJobTest < ActiveSupport::TestCase
  # Captures args/kwargs from ProcessTarImportJob → service.call for assertion.
  class RecordingService
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(*args, **kwargs)
      @calls << { args: args, kwargs: kwargs }
      nil
    end
  end

  setup do
    @tar_path = Rails.root.join("tmp/test-import-#{SecureRandom.hex(4)}.tar").to_s
    File.write(@tar_path, "dummy-tar-content")
    @import = Import.create!(
      tar_path: @tar_path,
      repository_name: "import-job-test-repo",
      tag_name: "v1",
      status: "pending",
      progress: 0
    )
  end

  teardown do
    FileUtils.rm_f(@tar_path) if @tar_path
  end

  test "perform with actor_email: forwards email to service as actor" do
    service = RecordingService.new
    ProcessTarImportJob.new.perform(@import.id,
                                     actor_email: "tonny@timberay.com",
                                     service: service)
    assert_equal 1, service.calls.length
    kwargs = service.calls.first[:kwargs]
    assert_equal "tonny@timberay.com", kwargs[:actor]
    assert_equal @import.repository_name, kwargs[:repository_name]
    assert_equal @import.tag_name, kwargs[:tag_name]
  end

  test "perform with nil actor_email falls back to 'system:import'" do
    service = RecordingService.new
    ProcessTarImportJob.new.perform(@import.id,
                                     actor_email: nil,
                                     service: service)
    assert_equal "system:import", service.calls.first[:kwargs][:actor]
  end

  test "perform marks import completed on success" do
    service = RecordingService.new
    ProcessTarImportJob.new.perform(@import.id, service: service)
    @import.reload
    assert_equal "completed", @import.status
    assert_equal 100, @import.progress
  end

  test "perform marks import failed and re-raises on service exception" do
    raising_service = Class.new do
      def call(*, **)
        raise StandardError, "boom"
      end
    end.new

    assert_raises(StandardError) do
      ProcessTarImportJob.new.perform(@import.id, service: raising_service)
    end
    @import.reload
    assert_equal "failed", @import.status
    assert_equal "boom", @import.error_message
  end
end
```

**주의:**
- `RecordingService` / raising class 모두 `test/jobs/process_tar_import_job_test.rb` 내부 namespaced — 다른 테스트에 leak 없음.
- Task 1.3 에서 import 하던 `FileUtils.rm_f(@tar_path) if @tar_path` (nil 가드) 유지.
- **Failure branch 테스트 추가** (Task 1.3 code quality review I-3 지적 반영) — 이는 `actor_email:` 도입과 무관하지만 DI 덕분에 cheap 하게 커버 가능.

- [ ] **Step 2: Verify FAIL**

```bash
bin/rails test test/jobs/process_tar_import_job_test.rb -v
```

Expected: 4 FAIL. `ArgumentError: unknown keyword: :service` (현재 `perform` signature 가 `service:` 를 받지 않음) + 다른 kwarg `actor_email:` 도 unknown.

- [ ] **Step 3: Modify `app/jobs/process_tar_import_job.rb`**

```ruby
class ProcessTarImportJob < ApplicationJob
  queue_as :default

  def perform(import_id, actor_email: nil, service: ImageImportService.new)
    import = Import.find(import_id)
    import.update!(status: "processing", progress: 10)

    begin
      service.call(
        import.tar_path,
        actor: actor_email.presence || "system:import",
        repository_name: import.repository_name,
        tag_name: import.tag_name
      )
      import.update!(status: "completed", progress: 100)
    rescue => e
      import.update!(status: "failed", error_message: e.message)
      raise
    end
  end
end
```

Key changes:
- `actor_email:` kwarg (default `nil`) — Plan task originally scoped this
- `service:` kwarg (default `ImageImportService.new`) — **DI refactor**, replaces the ambient `ImageImportService.new.call(...)` literal
- `ImageImportService.new.call(...)` → `service.call(...)` (now injectable)
- `actor:` 값은 `actor_email.presence || "system:import"`

**Important:** `service: ImageImportService.new` default is evaluated **per perform call** (like any kwarg default), so each job run gets a fresh instance — matches pre-DI semantics exactly.

- [ ] **Step 4: Verify targeted PASS**

```bash
bin/rails test test/jobs/process_tar_import_job_test.rb -v
```

Expected: 4 PASS.

- [ ] **Step 5: Locate Imports controller caller + modify**

```bash
rg -n "ProcessTarImportJob.perform_later" app/
```

수정:

```ruby
ProcessTarImportJob.perform_later(
  @import.id,
  actor_email: current_user&.primary_identity&.email
)
```

**주의:** `service:` kwarg 는 테스트 전용 — production `perform_later` 호출 시 **전달하지 않음**. default (`ImageImportService.new`) 로 fallback. ActiveJob 은 kwarg 를 GlobalID 로 직렬화하지 못하는 객체 (`ImageImportService.new` 인스턴스) 를 받으면 실패하므로, production 에서 `service:` 를 전달하면 런타임 오류 → **테스트만 전달하도록 규율 엄수**.

- [ ] **Step 6: Write failing test for Imports controller enqueue**

```ruby
test "enqueues ProcessTarImportJob with actor_email = current_user email" do
  sign_in_as(users(:tonny))
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear

  post imports_path, params: { import: { tar_path: "/tmp/x.tar" } }

  job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j| j[:job] == ProcessTarImportJob }
  assert job, "ProcessTarImportJob not enqueued"
  kwargs = job[:args].last
  assert_equal "tonny@timberay.com", kwargs["actor_email"]
end
```

- [ ] **Step 7: Verify PASS + Full suite**

```bash
bin/rails test test/jobs/process_tar_import_job_test.rb test/controllers/imports_controller_test.rb -v
bin/rails test
```

Expected: 모두 green. Stage 1 full suite 는 Task 2.9 시점 대비 +4 runs (Task 1.3 의 기존 2 + 새 4 = net +2 since rewrite replaces Task 1.3 tests). 정확한 숫자는 직접 확인.

- [ ] **Step 8: Commit**

```bash
git add app/jobs/process_tar_import_job.rb app/controllers/imports_controller.rb test/jobs/process_tar_import_job_test.rb test/controllers/imports_controller_test.rb
git commit -m "feat(registry): ProcessTarImportJob — service: DI + actor_email: propagation"
```

---

### Task 2.11: `Settings::TokensController` CRUD + routes + views

**Files:**
- Create: `app/controllers/settings/tokens_controller.rb`
- Create: `app/views/settings/tokens/index.html.erb`
- Create: `app/views/settings/tokens/_form.html.erb`
- Create: `app/views/settings/tokens/_token_row.html.erb`
- Modify: `config/routes.rb`
- Create: `test/controllers/settings/tokens_controller_test.rb`

- [ ] **Step 1: Add route**

`config/routes.rb` 의 Stage 0 `/auth/*` 아래에:

```ruby
namespace :settings do
  resources :tokens, only: [ :index, :create, :destroy ]
end
```

- [ ] **Step 2: Write failing test — index + create + destroy**

```ruby
require "test_helper"

class Settings::TokensControllerTest < ActionDispatch::IntegrationTest
  include TokenFixtures

  # --- index ---

  test "GET /settings/tokens 302 without signed-in user" do
    get settings_tokens_path
    assert_redirected_to "/auth/google_oauth2"
  end

  test "GET /settings/tokens lists active + revoked tokens for current identity" do
    sign_in_as(users(:tonny))
    get settings_tokens_path
    assert_response :ok
    assert_select "td", text: "laptop"
  end

  test "never leaks other users' tokens" do
    sign_in_as(users(:admin))
    get settings_tokens_path
    assert_select "td", text: "laptop", count: 0
  end

  # --- create ---

  test "POST /settings/tokens creates PAT and flashes raw token once" do
    sign_in_as(users(:tonny))
    assert_difference -> { PersonalAccessToken.count }, +1 do
      post settings_tokens_path, params: {
        personal_access_token: { name: "new-laptop", kind: "cli", expires_in_days: "30" }
      }
    end
    assert_redirected_to settings_tokens_path
    follow_redirect!
    assert_match(/\Aoprk_/, flash[:raw_token].to_s)
    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_equal users(:tonny).primary_identity, pat.identity
    assert_equal "new-laptop", pat.name
    assert_equal "cli", pat.kind
    assert_in_delta 30.days.from_now, pat.expires_at, 1.minute
  end

  test "POST /settings/tokens with kind=ci + blank expires_in_days → never expires" do
    sign_in_as(users(:tonny))
    post settings_tokens_path, params: {
      personal_access_token: { name: "ci-box", kind: "ci", expires_in_days: "" }
    }
    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_nil pat.expires_at
    assert_equal "ci", pat.kind
  end

  test "POST /settings/tokens with duplicate name for same identity fails" do
    sign_in_as(users(:tonny))
    assert_no_difference -> { PersonalAccessToken.count } do
      post settings_tokens_path, params: {
        personal_access_token: { name: "laptop", kind: "cli", expires_in_days: "30" }
      }
    end
    assert_response :unprocessable_entity
  end

  # --- destroy (revoke) ---

  test "DELETE /settings/tokens/:id revokes PAT of current user" do
    sign_in_as(users(:tonny))
    pat = personal_access_tokens(:tonny_cli_active)
    assert_changes -> { pat.reload.revoked_at } do
      delete settings_token_path(pat)
    end
    assert_redirected_to settings_tokens_path
  end

  test "DELETE cannot revoke other user's token (404)" do
    sign_in_as(users(:admin))
    pat = personal_access_tokens(:tonny_cli_active)
    assert_no_changes -> { pat.reload.revoked_at } do
      delete settings_token_path(pat)
    end
    assert_response :not_found
  end

  test "Revoked PAT can no longer push to V2 (end-to-end)" do
    sign_in_as(users(:tonny))
    pat = personal_access_tokens(:tonny_cli_active)
    delete settings_token_path(pat)
    reset!

    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_CLI_RAW)
    }
    put "/v2/myimage/manifests/v1", params: "{}", headers: headers
    assert_response :unauthorized
  end
end
```

- [ ] **Step 3: Verify FAIL**

- [ ] **Step 4: Create `app/controllers/settings/tokens_controller.rb`**

```ruby
module Settings
  class TokensController < ApplicationController
    before_action :ensure_current_user

    def index
      @tokens = current_identity.personal_access_tokens.order(created_at: :desc)
    end

    def create
      raw = PersonalAccessToken.generate_raw
      pat = current_identity.personal_access_tokens.new(
        name: pat_params[:name],
        kind: pat_params[:kind].presence || "cli",
        token_digest: Digest::SHA256.hexdigest(raw),
        expires_at: parse_expires_in(pat_params[:expires_in_days])
      )
      if pat.save
        flash[:raw_token] = raw
        redirect_to settings_tokens_path
      else
        @tokens = current_identity.personal_access_tokens.order(created_at: :desc)
        @error = pat.errors.full_messages.to_sentence
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      pat = current_identity.personal_access_tokens.find_by(id: params[:id])
      if pat.nil?
        head :not_found
        return
      end
      pat.revoke!
      redirect_to settings_tokens_path, notice: "Token revoked."
    end

    private

    def ensure_current_user
      redirect_to "/auth/google_oauth2" unless signed_in?
    end

    def current_identity
      current_user.primary_identity
    end

    def pat_params
      params.expect(personal_access_token: [ :name, :kind, :expires_in_days ])
    end

    def parse_expires_in(days_str)
      return nil if days_str.blank?
      days = Integer(days_str, exception: false)
      return nil if days.nil? || days <= 0
      days.days.from_now
    end
  end
end
```

**주의:** `current_identity.personal_access_tokens.find_by(id: ..)` — 타 사용자 PAT id 시도 시 `RecordNotFound` 대신 `head :not_found` (정보 누출 최소).

- [ ] **Step 5: Create views**

`app/views/settings/tokens/index.html.erb`:

```erb
<% content_for(:title, "Personal Access Tokens") %>

<section class="px-4 md:px-6 py-6 max-w-2xl mx-auto">
  <h1 class="text-xl font-semibold mb-4">Personal Access Tokens</h1>
  <p class="text-slate-500 text-sm mb-6">
    Used by Docker CLI: <code>docker login &lt;registry-host&gt; -u &lt;your email&gt; -p &lt;token&gt;</code>.
  </p>

  <% if flash[:raw_token].present? %>
    <div class="mb-6 rounded bg-amber-50 border border-amber-200 p-4">
      <p class="font-medium text-amber-900">Copy this token now — you will not see it again:</p>
      <pre class="mt-2 p-2 bg-white border font-mono text-sm break-all"><%= flash[:raw_token] %></pre>
    </div>
  <% end %>

  <%= render "form" %>

  <h2 class="mt-8 mb-2 text-lg font-semibold">Existing tokens</h2>
  <table class="w-full text-sm">
    <thead>
      <tr class="text-left border-b">
        <th class="py-2">Name</th>
        <th>Kind</th>
        <th>Expires</th>
        <th>Last used</th>
        <th>Status</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <% @tokens.each do |token| %>
        <%= render "token_row", token: token %>
      <% end %>
    </tbody>
  </table>
</section>
```

`_form.html.erb`:

```erb
<%= form_with url: settings_tokens_path, method: :post, local: true, data: { turbo: false } do |f| %>
  <div class="flex flex-wrap gap-3 items-end">
    <div class="flex-1 min-w-[160px]">
      <label class="block text-sm font-medium mb-1">Name</label>
      <%= f.text_field "personal_access_token[name]", required: true,
                       class: "w-full border rounded px-2 py-1 text-sm" %>
    </div>
    <div>
      <label class="block text-sm font-medium mb-1">Kind</label>
      <%= f.select "personal_access_token[kind]",
                   [ [ "CLI (default, 90-day)", "cli" ], [ "CI (may never expire)", "ci" ] ],
                   {}, class: "border rounded px-2 py-1 text-sm" %>
    </div>
    <div>
      <label class="block text-sm font-medium mb-1">Expires in days</label>
      <%= f.number_field "personal_access_token[expires_in_days]", value: 90, min: 0,
                         class: "w-24 border rounded px-2 py-1 text-sm" %>
    </div>
    <div>
      <%= f.submit "Generate token", class: "bg-slate-900 text-white rounded px-3 py-1.5 text-sm" %>
    </div>
  </div>
  <% if @error.present? %>
    <p class="mt-2 text-sm text-red-600"><%= @error %></p>
  <% end %>
<% end %>
```

`_token_row.html.erb`:

```erb
<tr class="border-b">
  <td class="py-2"><%= token.name %></td>
  <td><%= token.kind %></td>
  <td><%= token.expires_at ? l(token.expires_at.to_date) : "never" %></td>
  <td><%= token.last_used_at ? time_ago_in_words(token.last_used_at) + " ago" : "—" %></td>
  <td>
    <% if token.revoked_at %>
      <span class="text-red-600">Revoked</span>
    <% elsif token.expires_at && token.expires_at.past? %>
      <span class="text-slate-500">Expired</span>
    <% else %>
      <span class="text-green-700">Active</span>
    <% end %>
  </td>
  <td>
    <% unless token.revoked_at %>
      <%= button_to "Revoke", settings_token_path(token), method: :delete,
                    class: "text-sm text-red-600 hover:underline",
                    data: { confirm: "Revoke '#{token.name}'? Docker logins using this token will fail." } %>
    <% end %>
  </td>
</tr>
```

- [ ] **Step 6: Verify PASS**

```bash
bin/rails test test/controllers/settings/tokens_controller_test.rb -v
```

Expected: 8 PASS.

- [ ] **Step 7: Full suite regression**

```bash
bin/rails test
```

- [ ] **Step 8: Commit**

```bash
git add app/controllers/settings/tokens_controller.rb app/views/settings/tokens/ config/routes.rb test/controllers/settings/tokens_controller_test.rb
git commit -m "feat(registry): Settings::TokensController CRUD — index + create (one-shot flash) + destroy (revoke)"
```

---

### Task 2.12: Navigation link + System test

**Files:**
- Modify: `app/components/nav_component.html.erb` (또는 `app/views/layouts/_nav.html.erb` — grep 으로 현재 위치 확인)
- Modify: component test
- Create: `test/system/settings_tokens_test.rb`

- [ ] **Step 1: Locate nav**

```bash
rg -n "Sign (in|out)|sign_out_path|/auth/google_oauth2" app/components app/views/layouts
```

- [ ] **Step 2: Write failing component test**

```ruby
test "shows Tokens link when signed in" do
  user = users(:tonny)
  render_inline(NavComponent.new(current_user: user))
  assert_selector "a[href='/settings/tokens']", text: "Tokens"
end

test "hides Tokens link when not signed in" do
  render_inline(NavComponent.new(current_user: nil))
  assert_no_selector "a", text: "Tokens"
end
```

- [ ] **Step 3: Add link to nav**

```erb
<% if current_user %>
  <%= link_to "Tokens", settings_tokens_path,
              class: "text-sm text-slate-600 hover:text-slate-900" %>
<% end %>
```

- [ ] **Step 4: Write failing system test**

`test/system/settings_tokens_test.rb`:

```ruby
require "application_system_test_case"

class SettingsTokensTest < ApplicationSystemTestCase
  setup do
    @user = users(:tonny)
    sign_in_as(@user)
  end

  test "create token → raw shown once → revoke" do
    visit settings_tokens_path

    fill_in "personal_access_token[name]", with: "laptop-zeta"
    select "CLI (default, 90-day)", from: "personal_access_token[kind]"
    fill_in "personal_access_token[expires_in_days]", with: "7"
    click_on "Generate token"

    assert_text "Copy this token now"
    raw_token = page.find("pre").text
    assert_match(/\Aoprk_/, raw_token)

    assert_text "laptop-zeta"

    within("tr", text: "laptop-zeta") do
      accept_confirm do
        click_on "Revoke"
      end
    end

    assert_text "Revoked"
  end
end
```

**주의:** `sign_in_as` system-test 헬퍼 — Stage 0 `test/system/auth_login_test.rb` 패턴 재사용. `ApplicationSystemTestCase` 가 `/testing/sign_in` 경유 setup 지원. 없으면 OmniAuth mock 기반 로그인으로 대체.

- [ ] **Step 5: Verify PASS**

```bash
bin/rails test test/components/nav_component_test.rb -v
bin/rails test:system test/system/settings_tokens_test.rb -v
```

- [ ] **Step 6: Commit**

```bash
git add app/components/nav_component.html.erb test/components/nav_component_test.rb test/system/settings_tokens_test.rb
git commit -m "feat(registry): nav — Tokens link for signed-in users + system test"
```

---

### Task 2.13: rack-attack V2 protected throttle + CI hard gate + PR-2 pre-flight

**Files:**
- Modify: `config/initializers/rack_attack.rb`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Locate existing rack-attack config**

```bash
cat config/initializers/rack_attack.rb 2>/dev/null | head -50
```

기존에 `/auth/google_oauth2` 등 throttle 가 있을 것. 그 아래에 V2 protected path throttle 추가.

- [ ] **Step 2: Add V2 protected throttle**

```ruby
Rack::Attack.throttle("v2_protected_by_ip", limit: 30, period: 1.minute) do |req|
  if req.path.start_with?("/v2/") && !(req.get? || req.head?)
    req.ip
  end
end
```

**주의:** `limit: 30 per minute per IP` — 사내 CI 병렬 push 시 초과 가능. 실 트래픽 기준은 staging soak 단계에서 조정. pull (GET/HEAD) 는 throttle 대상 아님 (anonymous 유지).

- [ ] **Step 3: Write failing test (또는 integration) — 선택**

간단한 smoke (31회 연속 POST 시도 마지막이 429):

```ruby
test "V2 protected path throttled at >30 req/min/ip" do
  30.times do
    post "/v2/myimage/blobs/uploads"  # all 401 but count toward throttle
  end
  post "/v2/myimage/blobs/uploads"
  # rack-attack test 모드가 다를 수 있음 — skip 가능
end
```

실제 rack-attack test 는 Redis 의존 / test 모드 설정 복잡. **선택적.**

- [ ] **Step 4: Modify `.github/workflows/ci.yml`**

```bash
rg -n "bin/rails test" /home/tonny/projects/open-repo/.github/workflows/
```

기존 test step 뒤에 추가:

```yaml
      - name: Critical gap tests (hard gate)
        run: |
          bin/rails test \
            test/integration/anonymous_pull_regression_test.rb \
            test/integration/docker_basic_auth_test.rb
        env:
          RAILS_ENV: test
```

**주의:** `retention_ownership_interaction`, `first_pusher_race` 는 Stage 2. 추가하지 않음.

- [ ] **Step 5: PR-2 pre-flight full suite**

```bash
bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman --no-pager
```

모두 green.

- [ ] **Step 6: Manual dev smoke**

```bash
bin/rails server &

# 1) 로그인: http://localhost:3000/auth/google_oauth2
# 2) /settings/tokens 에서 PAT 생성 ("dev-smoke"), raw 복사
# 3) curl 로 challenge 확인:
curl -i -X PUT http://localhost:3000/v2/myimage/manifests/v1
# expect: 401, WWW-Authenticate: Basic realm="Registry"

# 4) Basic auth 로 재시도 (빈 manifest 는 아래에서 400/422 나도 OK — auth 성공 확인 용도)
AUTH=$(printf 'tonny@timberay.com:oprk_...' | base64 -w0)
curl -i -X PUT http://localhost:3000/v2/myimage/manifests/v1 \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" \
  -d '{}'
# expect: 401 이 아닌 것 (400/422 OK — auth 통과 증거)

# 5) Revoke "dev-smoke", 같은 curl 재시도 → 401 복귀
```

- [ ] **Step 7: Commit + Push + PR open**

```bash
git add config/initializers/rack_attack.rb .github/workflows/ci.yml
git commit -m "ci(registry): V2 protected throttle + critical gap hard gate"

git push -u origin feature/registry-auth-stage1-pr2
gh pr create --title "feat(registry): Stage 1 PR-2 — PAT Basic auth + V2 auth gate + actor 실명화 + Settings UI" --body "$(cat <<'EOF'
## Summary
- `PersonalAccessToken` model (`.active`, `authenticate_raw`, `generate_raw`, `revoke!`)
- `Auth::PatAuthenticator` service (email + raw_token → user/pat)
- `V2::BaseController#authenticate_v2_basic!` before_action + anonymous pull whitelist + `render_v2_challenge` (Basic scheme)
- `V2::ManifestsController` + `TagsController#destroy` record `TagEvent.actor = current_user.email`
- `TagEvent#display_actor` helper (`<system: anonymous>` for legacy rows)
- `ProcessTarImportJob#perform(id, actor_email:)` + Imports controller 전달, fallback `"system:import"`
- `Settings::TokensController` CRUD (index / create with one-shot raw flash / destroy revoke)
- Nav "Tokens" link for signed-in users + system test
- rack-attack throttle on V2 protected paths (30/min/IP)
- Critical Gap #3 `anonymous_pull_regression_test` (11 scenarios, Basic scheme)
- CI hard gate: `anonymous_pull_regression` + `docker_basic_auth`

## Acceptance (Stage 1 PR-2)
- [x] V2 push/delete 는 PAT Basic auth 필수 (anonymous push 차단)
- [x] V2 pull 은 `REGISTRY_ANONYMOUS_PULL=true` 조건에서 익명 허용
- [x] `TagEvent.actor` 에 실명 email 기록 (V2 + Web UI + Import job)
- [x] Settings UI 에서 PAT 발급/폐기, raw token 은 1회만 노출
- [x] Revoked PAT 은 즉시 push 차단
- [x] Critical Gap #3 11 scenarios GREEN
- [x] CI hard gate passes
- [x] `bin/rails test` + `bin/rails test:system` + `bin/rubocop` + `bin/brakeman` green

## Stage 1 complete after merge
- [ ] Staging canary (Phase 3 체크리스트)

🤖 Generated with Claude Code
EOF
)"
```

- [ ] **Step 8: Wait for merge, sync main**

```bash
git checkout main && git pull origin main
```

---

## Phase 3 — Staging canary + 배포 체크리스트

### Task 3.1: Staging 배포 pre-flight (tech design §8.2 Stage 1 체크리스트)

- [ ] **Step 1: staging ENV 주입**

devops 와 협의:

```bash
# staging
REGISTRY_ADMIN_EMAIL=devops@timberay.com
REGISTRY_ANONYMOUS_PULL=true
```

이전 plan 의 `REGISTRY_JWT_ISSUER` / `REGISTRY_JWT_AUDIENCE` 및 `config/credentials/staging.yml.enc` 의 `jwt:` 블록은 **불필요** (D9).

- [ ] **Step 2: Database migration dry-run**

```bash
kamal app exec -d staging 'bin/rails db:migrate:status'
# expect: create_personal_access_tokens 가 "down" 상태
kamal app exec -d staging 'bin/rails db:migrate'
# expect: "up" 전환
kamal app exec -d staging 'bin/rails runner "p PersonalAccessToken.count"'
# expect: 0
```

- [ ] **Step 3: Staging smoke — Web UI + PAT 생성**

```bash
# 1) staging Web UI 에서 admin 로그인
# 2) /settings/tokens 에서 PAT 생성 ("staging-smoke"), raw 복사
```

- [ ] **Step 4: Staging Docker CLI smoke (devops 환경에서)**

```bash
# devops workstation
docker login registry.staging.timberay.local -u $STAGING_ADMIN -p $STAGING_PAT
docker pull hello-world
docker tag hello-world registry.staging.timberay.local/staging-smoke:v1
docker push registry.staging.timberay.local/staging-smoke:v1
docker pull registry.staging.timberay.local/staging-smoke:v1
```

Expected: 4 command 모두 성공.

- [ ] **Step 5: TagEvent.actor 실명 확인 (staging DB)**

```bash
kamal app exec -d staging 'bin/rails runner "p TagEvent.order(created_at: :desc).limit(5).pluck(:actor, :action, :occurred_at)"'
```

Expected: 가장 최근 이벤트 `actor` 가 실 이메일. 오래된 이벤트는 `"anonymous"` 유지.

- [ ] **Step 6: Anonymous pull regression (staging)**

```bash
# 토큰 없이 pull
docker pull registry.staging.timberay.local/staging-smoke:v1  # 성공 (anonymous pull)

# anonymous push 시도
echo '{}' | curl -i -X PUT \
  -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" \
  -d '{}' \
  https://registry.staging.timberay.local/v2/staging-smoke/manifests/anon \
  2>&1 | grep -i "401\|unauthorized"
# expect: "401" + WWW-Authenticate: Basic realm="Registry"
```

- [ ] **Step 7: Rack-attack throttle 확인**

```bash
# 35 연속 POST (30 초과)
for i in $(seq 1 35); do
  curl -s -o /dev/null -w "%{http_code}\n" -X POST \
    https://registry.staging.timberay.local/v2/dummy/blobs/uploads
done
# expect: 마지막 몇 개는 429
```

- [ ] **Step 8: 1일 soak**

24시간 staging 에 유지. 아래 지표 모니터링:

- V2 push 경로 200/201 응답률 > 95%
- `V2::BaseController#authenticate_v2_basic!` 401 비율 baseline +10% 이하
- `TagEvent.where(actor: "anonymous").where("created_at > ?", 배포시점)` 가 Stage 1 배포 이후 신규 없음 (기대값: 0)

- [ ] **Step 9: Production 배포 및 15분 canary**

```bash
kamal deploy
# 배포 후 15분 모니터링 (tech design §8.3 rollback decision tree)
```

- [ ] **Step 10: CI / K8s ImagePullSecret PAT 교체**

Stage 1 배포 전 사전 공지대로 모든 CI 파이프라인 / K8s 배포 매니페스트 의 Docker credential 을 PAT 로 교체. 미교체 시 배포 직후 K8s ImagePullBackOff.

---

### Task 3.2: Rollback 준비 확인 (tech design §8.3)

Production 장애 시 다음 시나리오별 대응 문서를 PR-2 PR 설명에 링크:

- **C. PAT 검증 버그 (digest 비교 / email 매칭)** → `kamal rollback` → Stage 0 상태 (anonymous push 복귀, audit 일시 gap)
- **D. actor kwarg 누락 배포** → PR-2 의 behavioral 커밋만 선택 revert → `actor: "anonymous"` 일시 복귀 (기능 복구)
- **E. `REGISTRY_ANONYMOUS_PULL` 조건 분기 버그로 모든 pull 이 401** → ENV 값 확인 or 긴급 hotfix PR. K8s ImagePullBackOff 즉각 영향 → canary 15분 내 탐지 필수.

결정권자: 배포 담당자 단독. Post-mortem 은 24h 이내.

---

## Stage 1 Completion Criteria

| 항목 | 확인 방법 |
|---|---|
| 2 PR 모두 main merge | `gh pr list --base main --state merged --search "Stage 1"` |
| `bin/rails test` green | `bin/rails test` |
| `bin/rails test:system` green | `bin/rails test:system` |
| Critical gap hard gate green | CI 로그 |
| Staging 1일 soak pass | V2 push 지표 > 95% |
| Production canary 15분 pass | kamal 배포 후 모니터링 로그 |
| CI / K8s PAT 교체 완료 | devops 확인 |
| `TagEvent.actor` 실명 기록 중 | 실시간 DB 확인 |
| Slack 공지 발송 | "Stage 1 배포 순간 모든 push/delete 가 PAT 필수" |

모두 green 이면 Stage 2 plan 작성 (`/superpowers:writing-plans` 재호출, tech design §1.3 / §2.5 / §2.6 / §4 Stage 2 / §7.1 / §7.2 기반).

---

## Execution notes

- 각 Task 의 Step 1–N 은 **엄격한 Red → Green → Refactor → Commit** 순서. Step 을 건너뛰지 말 것.
- **Structural vs behavioral 커밋 분리** (CLAUDE.md Tidy First) — 한 커밋에 둘 섞지 말 것. PR-1 은 structural only, PR-2 의 각 Task 는 자체적으로 RGR 사이클 완결.
- `bin/rails test` 는 각 Task 끝마다 full suite. `bin/rails test <file>` 는 부분 검증.
- 실패한 commit 은 `git commit --amend` 금지 (CLAUDE.md). 새 커밋으로 수정.
- 커밋 메시지: `feat(registry)` / `refactor(registry)` / `test(registry)` / `chore(registry)` / `ci(registry)`. Korean 금지 (CLAUDE.md).
- Rubocop 위반 시 `bin/rubocop -a` 후 re-stage + 새 커밋.
- Pre-commit hook 실패 시 implementer 가 직접 fix 후 재시도 (사용자에게 묻지 말 것 — QUALITY.md §Pre-commit Failure Recovery).

**Stage 1 PR 순차 규칙:** PR-2 는 PR-1 이 main 에 머지된 후 분기. 병렬 작업 금지 (`actor:` kwarg 의 structural/behavioral 분리를 depend 하기 때문).
