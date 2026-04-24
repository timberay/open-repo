# Registry Auth Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repository ownership 모델 도입 (`owner_identity_id`), `RepositoryMember` 테이블 추가, `RepositoryAuthorization` concern 으로 V2/Web 컨트롤러에 쓰기/삭제 권한 게이트 적용. First-pusher-owner(GitHub 스타일) 구현 및 retention job 과의 decoupling 검증.

**Architecture:**
- 세 개의 마이그레이션(`owner_identity_id`, `repository_members`, `actor_identity_id`) 을 PR-1(structural) 에 묶어 행동 변화 없이 스키마 먼저 착지.
- `RepositoryAuthorization` concern 을 `V2::BaseController`(API) 와 `ApplicationController`(Base) 양쪽에 include. rescue_from 매핑은 컨텍스트별로 다름.
- `Repository#writable_by?` / `#deletable_by?` / `#transfer_ownership_to!` 로 권한 로직을 모델에 캡슐화.
- `V2::BlobUploadsController#ensure_repository!` 가 first-pusher 패턴으로 `owner_identity_id` 주입.
- `TagEvent#belongs_to :actor_identity` + `action: "ownership_transfer"` validation 확장.
- PR-1 컨트롤러에 권한 게이트 없음. PR-2 에서 일괄 활성화.

**Tech Stack:** Rails 8.1, Minitest, SQLite, concurrent-ruby (CyclicBarrier), Hotwire, ViewComponent 없음(ERB partial).

**Source spec:** `docs/superpowers/specs/2026-04-23-registry-auth-tech-design.md` §1.3, §1.4, §2.1(`Auth::ForbiddenAction`), §2.5(`RepositoryAuthorization`), §2.6(Repository 권한 메서드), §4.5(Stage 2 `actor_identity_id`), §6.1(test layout), §7.1(Critical Gap #1), §7.2(Critical Gap #2), §7.4(CI gate), §8.2 Stage 2 체크리스트, §8.3 Stage 2 rollback.

**Branching strategy:**
- `feature/registry-auth-stage2-pr1` — Phase 1 commits. `main`(9ddb481) 에서 분기.
- `feature/registry-auth-stage2-pr2` — PR-1 머지 후 분기.
- 각 PR 은 독립 green CI 가능해야 함. 병렬 금지.

---

## Completion Status (PR-1, 2026-04-24)

**PR-1:** 6 commits on `feature/registry-auth-stage2-pr1`, full suite 438 runs / 0 failures. Awaiting CI green + merge.
**PR-2:** not started.

**Scope deviations actually shipped vs. original plan text:**

1. **Task 1.2 — `owner_identity_id` NOT NULL deferred to PR-2.** The original migration ended with `change_column_null :repositories, :owner_identity_id, false`, which would break existing callers (`ManifestProcessor`, `V2::BlobUploadsController`, 23 tests) that create repositories without an owner — forcing behavioral patches into PR-1 and violating Tidy First. The column stays `null: true` in PR-1; a new migration will flip it to NOT NULL in PR-2 **after** Task 2.5 wires first-pusher-owner so every new repo gets an owner at creation. The backfill block is guarded by `Repository.where(owner_identity_id: nil).exists?` so empty DBs (fresh test schema load, CI) do not need `REGISTRY_ADMIN_EMAIL`.
2. **Task 1.2 — migration `down` fixed.** The plan's `remove_reference :repositories, :owner_identity, foreign_key: true` fails because Rails infers the FK target from the column name (`owner_identities`) but the real target is `identities`. Down method uses `foreign_key: { to_table: :identities }` so rollback actually works.
3. **Task 1.4 — `belongs_to :owner_identity, optional: true`.** Direct consequence of (1). With the column nullable and existing tests creating repos without owners (`repo_for_protection`, `enforcement_repo` in `test/models/repository_test.rb`), the association must accept nil to keep the PR-1 suite green without touching existing tests. PR-2 will tighten this alongside the NOT NULL constraint.
4. **Task execution order — 1.5 before 1.4 (swapped).** Task 1.4's `transfer_ownership_to!` creates a `TagEvent` with `action: "ownership_transfer"` + `actor_identity_id:`, both of which are enabled by Task 1.5. Running 1.5 first avoided writing tests that could not be red-to-green inside a single task commit.

**Commits on branch (oldest → newest):**
- `fad4faf` feat(registry): Auth::ForbiddenAction — Stage 2 authz error class
- `fb750c0` feat(registry): Stage 2 migrations — owner_identity (nullable), repository_members, actor_identity
- `11bba93` feat(registry): RepositoryMember model — role validation + uniqueness
- `de609aa` feat(registry): TagEvent — belongs_to actor_identity (optional) + ownership_transfer action
- `afa20ab` feat(registry): Repository — owner_identity + writable_by?/deletable_by?/transfer_ownership_to!
- `ba084ed` feat(registry): RepositoryAuthorization concern — authorize_for!(action)

**PR-2 action items surfaced by these deviations:**
- Add a new migration after Task 2.5: `ChangeOwnerIdentityToNotNullOnRepositories` (`change_column_null :repositories, :owner_identity_id, false`).
- Drop `optional: true` from `Repository.belongs_to :owner_identity` in the same commit as that migration.

---

## Completion Status (PR-2, 2026-04-24)

**PR-2:** 10 commits on `feature/registry-auth-stage2-pr2`, full suite 457 runs / 1081 assertions / 0 failures / 0 errors / 1 skip. Awaiting CI green + merge.

**Scope deviations actually shipped vs. original plan text:**

1. **Task 2.3 — commit scope 2 → 4 files.** In addition to `app/controllers/v2/manifests_controller.rb` + `test/controllers/v2/manifests_controller_test.rb`, the `before_action :set_repository_for_authz` gate forced test-side adaptation in two other files that pushed to a still-absent `"test-repo"` via `basic_auth_for`: `test/controllers/v2/base_controller_test.rb` (TagProtected setup) and `test/integration/docker_basic_auth_test.rb` (happy-path push). Both added `owner_identity: identities(:tonny_google)` or pre-created the repo so tonny owns it; no production code changes outside the manifests controller. Also corrected a typo in the plan's test block: `TagEvent.order(:created_at)` → `order(:occurred_at)` (tag_events has no `created_at`).
2. **Task 2.5 — race-loser 403 bug (discovered by Task 2.8).** The original `ensure_repository!` called `authorize_for!(:write)` inside the `rescue ActiveRecord::RecordNotUnique` branch. That made the concurrent-first-push LOSER a 403 (they hit the rescue, then failed authz because the winner now owns the repo). This contradicted Task 2.8's Scenario 1 `[202, 202]` expectation. Resolved with a separate `fix(registry):` commit that drops the authz call from the race branch — the race-loser's blob upload is harmless (orphan sweeper handles it) and any subsequent manifest PUT still goes through the manifest-level authz gate. Not a behavior change to non-racing traffic.
3. **Task 2.6 — deleted an obsolete test.** `test "unsigned destroy falls back to actor: 'anonymous'"` was removed. Its premise (anonymous delete with `actor: "anonymous"` fallback) is incompatible with the new `authorize_for!(:delete)` gate, which requires authentication. Controller now uses `current_user.primary_identity.email` directly, no nil-fallback branch.
4. **NOT NULL + `optional: true` removal (flagged for PR-1 → PR-2) DEFERRED again.** ~20 callsites still create repos without `owner_identity` (primarily `test/models/repository_test.rb`, `test/services/manifest_processor_test.rb`, `test/services/dependency_analyzer_test.rb`, and a few controller tests that cover orthogonal concerns like search, protection, maintainer). Each needs an `owner_identity:` keyword added. The invariant is semantically safe right now — with first-pusher-owner live (Task 2.5), every new production repo is owned at creation; legacy nil-owner repos are effectively read-only because `writable_by?` / `deletable_by?` both return false when `owner_identity_id` is nil and there are no members. Making the column NOT NULL is hygiene, not security, so it can live on a follow-up PR that focuses purely on test cleanup + migration.

**Commits on branch (oldest → newest):**
- `d4a1179` feat(registry): V2::BaseController — include RepositoryAuthorization + rescue_from ForbiddenAction
- `1652f49` feat(registry): ApplicationController + RepositoriesController — authz enforcement on destroy
- `85652ab` feat(registry): V2::ManifestsController — authorize_for! + actor_identity_id threading
- `c055ae9` feat(registry): V2::BlobsController#destroy — authorize_for!(:delete)
- `0262a92` feat(registry): V2::BlobUploadsController — first-pusher-owner + authorize_for!(:write)
- `441413a` feat(registry): TagsController#destroy — authorize_for!(:delete) + actor_identity_id
- `d9a1e3a` test(registry): retention_ownership_interaction — Critical Gap #1 (Stage 2)
- `1ecf9c4` fix(registry): ensure_repository! — race-loser gets graceful blob-upload pass
- `f0f31d4` test(registry): first_pusher_race — Critical Gap #2 (Stage 2)
- `e5546cc` ci(registry): add Stage 2 critical gap tests to CI hard gate

**Follow-up PR (post-Stage-2):**
- `ChangeOwnerIdentityToNotNullOnRepositories` migration + drop `optional: true` from `Repository.belongs_to :owner_identity` + update all `Repository.create!` callsites in tests to supply `owner_identity`. Purely hygiene; no security or behavior impact.

---

## PR 분할 근거

| PR | 성격 | 내용 |
|---|---|---|
| **PR-1** | structural | 3 마이그레이션(owner_identity_id + backfill, repository_members, actor_identity_id) + `Auth::ForbiddenAction` 추가 + `RepositoryMember` 모델 + `RepositoryAuthorization` concern 정의 + `Repository#writable_by?/deletable_by?/transfer_ownership_to!` + `TagEvent` `belongs_to :actor_identity` + `ownership_transfer` validation. **컨트롤러에 권한 게이트 없음 — behavior 불변.** |
| **PR-2** | behavioral | V2/Web 컨트롤러에 `authorize_for!` before_action 추가 + first-pusher-owner 구현 + `actor_identity_id` ThreadEvent 주입 + Critical Gap #1/#2 회귀 테스트 + CI gate 업데이트 |

**1 PR vs 3 PR 비교:**

| 옵션 | 장점 | 단점 |
|---|---|---|
| 1 PR | 커밋 수 적음 | Tidy First 위반. 스키마 + 행동이 같은 PR. review diff 복잡 |
| **2 PR (채택)** | structural/behavioral 완전 분리. PR-1 단독 green. review 명료 | PR 2개 관리 필요 |
| 3 PR | 세분화 가능 | PR-1 머지 전에 PR-2 작업 불가. 오버엔지니어링 |

---

## Prerequisites

### P1. Stage 1 main 머지 확인

```bash
git log main --oneline | head -5
# 기대: 9ddb481 docs(readme): document PAT auth ... 가 최상단
```

### P2. `REGISTRY_ADMIN_EMAIL` 설정 확인

```bash
echo "${REGISTRY_ADMIN_EMAIL:-UNSET}"
# 기대: tonny@timberay.com 또는 admin@timberay.com (마이그레이션 backfill 에 사용됨)
```

미설정 시 `.env` 또는 shell profile 에 추가:
```bash
export REGISTRY_ADMIN_EMAIL=admin@timberay.com
```

`staging/prod` 환경 변수는 devops 와 별도 협의. 마이그레이션은 `ENV.fetch("REGISTRY_ADMIN_EMAIL")` 로 값이 없으면 `KeyError` 로 명시적 실패 — 실수 방지.

### P3. `concurrent-ruby` gem 확인 (Critical Gap #2 test 에 필요)

```bash
bundle exec ruby -e "require 'concurrent'; puts Concurrent::CyclicBarrier"
# 기대: Concurrent::CyclicBarrier — Rails 기본 dep 이라 이미 있음
```

---

## Environment Notes (Critical — 구현자 필독)

새 세션에서 이 플랜을 실행하는 에이전트가 같은 실수를 반복하지 않도록 Stage 1 구현에서 발견한 제약사항을 아래에 정리한다.

1. **Minitest 6.0.4 — 스텁 불가**: `stub_any_instance` / `Minitest::Mock` / `Object.stub` 없음. Mocha 도 미설치. tech design §7.1 의 `RepositoryAuthorization.stub_any_instance(...)` 호출은 동작하지 않는다. 대안: retention job 은 `current_user` 가 없으므로 `authorize_for!` 가 잘못 호출되면 `Auth::Unauthenticated` 를 raise 함. 테스트는 job 을 실행하고 "no raise" 를 assert 하는 간접 검증 패턴 사용.

2. **`sign_in_as` 헬퍼 없음**: `post "/testing/sign_in", params: { user_id: users(:X).id }` 패턴 사용.

3. **NavComponent 없음**: 네비게이션은 `app/views/shared/_auth_nav.html.erb` ERB partial.

4. **`test/system/` 없음**: `ApplicationSystemTestCase` / Selenium 없음. 시스템 테스트 대신 통합 테스트 사용.

5. **fixtures 제한**: `repositories.yml`, `manifests.yml`, `tags.yml`, `blobs.yml` **없음**. 테스트에서 인라인 `Repository.create!` + `SecureRandom.hex(4)` repo-name suffix 패턴으로 병렬 테스트 격리.

6. **`config/credentials.yml.enc`** 는 Stage 0 아티팩트 미스테이지. 손대지 않음.

7. **Rails 8.1 params**: `params.expect(foo: [...])` 선호 (Stage 2 에 새 controller 없으므로 직접 적용 없음).

8. **Docker V2 헤더 대소문자**: `Docker-Distribution-API-Version: registry/2.0` (API 대문자). 이미 Stage 1 에서 통일됨. 유지.

9. **Turbo confirm**: Web UI 파괴적 버튼은 `data: { turbo_confirm: "..." }` (not `data: { confirm: "..." }`).

10. **`basic_auth_for` 헬퍼**: V2 통합 테스트에서 `basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")` 형태로 사용. tech design 의 `bearer_headers_for` 는 JWT 폐기로 없음.

11. **`assert_in_delta`**: 시간 비교는 `assert_in_delta Time.current, record.timestamp, 5.seconds` 형태.

12. **`self.use_transactional_tests = false`**: Critical Gap #2(first_pusher_race) 테스트에 필요. 해당 파일에서만 선언. teardown 에서 `Repository.where(name: repo_name).destroy_all` 으로 수동 정리.

13. **`admin_pat` fixture 필요**: Stage 2 테스트에서 admin 사용자로 V2 push 를 시도할 경우가 있음. admin PAT fixture 를 `test/fixtures/personal_access_tokens.yml` 에 추가해야 함.

---

## File Structure

### PR-1 (Structural)

| 파일 | 역할 |
|---|---|
| `db/migrate/YYYYMMDDHHMMSS_add_owner_identity_to_repositories.rb` | `owner_identity_id` 컬럼 + backfill + NOT NULL 제약 |
| `db/migrate/YYYYMMDDHHMMSS_create_repository_members.rb` | `repository_members` 테이블 |
| `db/migrate/YYYYMMDDHHMMSS_add_actor_identity_to_tag_events.rb` | `actor_identity_id` 컬럼 (nullable) |
| `app/errors/auth.rb` | `Auth::ForbiddenAction` 추가 |
| `app/models/repository_member.rb` | `RepositoryMember` 모델 |
| `app/models/repository.rb` | `belongs_to :owner_identity` + associations + 권한 메서드 3개 |
| `app/models/tag_event.rb` | `belongs_to :actor_identity` + `ownership_transfer` validation |
| `app/controllers/concerns/repository_authorization.rb` | `authorize_for!` concern |
| `test/fixtures/personal_access_tokens.yml` | `admin_cli_active` fixture 추가 |
| `test/fixtures/repository_members.yml` | 신규 fixtures 파일 |
| `test/models/repository_member_test.rb` | RepositoryMember 단위 테스트 |
| `test/models/repository_test.rb` | 권한 메서드 테스트 섹션 추가 |
| `test/models/tag_event_test.rb` | `actor_identity` + `ownership_transfer` 테스트 추가 |
| `test/controllers/concerns/repository_authorization_test.rb` | concern 단위 테스트 |

### PR-2 (Behavioral)

| 파일 | 역할 |
|---|---|
| `app/controllers/v2/base_controller.rb` | `include RepositoryAuthorization` + `rescue_from` 매핑 |
| `app/controllers/application_controller.rb` | `include RepositoryAuthorization` + `rescue_from` 매핑 |
| `app/controllers/v2/blob_uploads_controller.rb` | `ensure_repository!` first-pusher-owner + `authorize_for!(:write)` |
| `app/controllers/v2/manifests_controller.rb` | `authorize_for!(:write/:delete)` + `actor_identity_id:` 주입 |
| `app/controllers/v2/blobs_controller.rb` | `authorize_for!(:delete)` |
| `app/controllers/tags_controller.rb` | `authorize_for!(:delete)` + `actor_identity_id:` 주입 |
| `app/controllers/repositories_controller.rb` | `authorize_for!(:delete)` on destroy |
| `test/controllers/v2/blob_uploads_controller_test.rb` | first-pusher-owner 테스트 추가 |
| `test/controllers/v2/manifests_controller_test.rb` | authz + `actor_identity_id` 테스트 추가 |
| `test/controllers/v2/blobs_controller_test.rb` | destroy authz 테스트 추가 |
| `test/controllers/tags_controller_test.rb` | destroy authz 테스트 추가 |
| `test/controllers/repositories_controller_test.rb` | destroy authz 테스트 추가 |
| `test/integration/retention_ownership_interaction_test.rb` | Critical Gap #1 |
| `test/integration/first_pusher_race_test.rb` | Critical Gap #2 |
| `.github/workflows/ci.yml` | CI hard gate 업데이트 (gap #1/#2 추가) |

---

## Phase 1 — PR-1: Structural (Migrations + Models + Concern)

### Task 1.1: `Auth::ForbiddenAction` 에러 클래스 추가

**Files:**
- Modify: `app/errors/auth.rb`
- Modify: `test/models/concerns/auth/` — 기존 없으면 해당 경로 대신 별도 위치

**해설:** Stage 2 의 모든 권한 거부는 이 예외 하나를 rescue 한다. `repository` + `action` 을 carries 하므로 컨트롤러에서 에러 메시지 구성에 사용.

- [ ] **Step 1: 실패 테스트 작성**

Create `test/models/auth_forbidden_action_test.rb`:

```ruby
require "test_helper"

class AuthForbiddenActionTest < ActiveSupport::TestCase
  test "ForbiddenAction carries repository and action" do
    repo = Repository.create!(name: "forbidden-test-#{SecureRandom.hex(4)}")
    err = Auth::ForbiddenAction.new(repository: repo, action: :write)
    assert_equal repo, err.repository
    assert_equal :write, err.action
    assert_match(/forbidden/, err.message)
    assert_match(/write/, err.message)
    assert_match(repo.name, err.message)
  end

  test "ForbiddenAction is a subclass of Auth::Error" do
    assert Auth::ForbiddenAction < Auth::Error
  end
end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/models/auth_forbidden_action_test.rb -v
```

Expected: 2 FAIL — `uninitialized constant Auth::ForbiddenAction`.

- [ ] **Step 3: `auth.rb` 에 `ForbiddenAction` 추가**

```ruby
# app/errors/auth.rb
module Auth
  class Error < StandardError; end

  # Stage 0: OAuth callback flow
  class InvalidProfile < Error; end
  class EmailMismatch  < Error; end
  class ProviderOutage < Error; end

  # Stage 1: PAT HTTP Basic auth (Registry V2)
  class Unauthenticated < Error; end # no/malformed Authorization header
  class PatInvalid      < Error; end # PAT not found / revoked / expired / email mismatch

  # Stage 2: authorization
  class ForbiddenAction < Error
    attr_reader :repository, :action

    def initialize(repository:, action:)
      @repository = repository
      @action     = action
      super("forbidden: cannot #{action} on repository '#{repository.name}'")
    end
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/models/auth_forbidden_action_test.rb -v
```

Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add app/errors/auth.rb test/models/auth_forbidden_action_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): Auth::ForbiddenAction — Stage 2 authz error class

Carries repository + action for controller-level rescue_from wiring.
Subclasses Auth::Error for consistent error hierarchy.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.2: Stage 2 마이그레이션 3개

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_owner_identity_to_repositories.rb`
- Create: `db/migrate/YYYYMMDDHHMMSS_create_repository_members.rb`
- Create: `db/migrate/YYYYMMDDHHMMSS_add_actor_identity_to_tag_events.rb`

**해설:** 3 파일을 순서대로 생성. 첫 마이그레이션에서 `REGISTRY_ADMIN_EMAIL` ENV 로 기존 repo 를 backfill 한 뒤 NOT NULL 제약. 기존 repo 가 없으면 backfill 은 no-op.

- [ ] **Step 1: 마이그레이션 파일 생성**

```bash
bin/rails generate migration AddOwnerIdentityToRepositories
bin/rails generate migration CreateRepositoryMembers
bin/rails generate migration AddActorIdentityToTagEvents
```

- [ ] **Step 2: `add_owner_identity_to_repositories` 내용 작성**

`db/migrate/YYYYMMDDHHMMSS_add_owner_identity_to_repositories.rb` (타임스탬프는 generate 시 자동 부여):

```ruby
class AddOwnerIdentityToRepositories < ActiveRecord::Migration[8.1]
  def up
    add_reference :repositories, :owner_identity,
                  foreign_key: { to_table: :identities, on_delete: :restrict },
                  null: true  # backfill 전까지 nullable

    admin_email    = ENV.fetch("REGISTRY_ADMIN_EMAIL")
    admin_user     = User.find_by!(email: admin_email)
    admin_identity_id = admin_user.primary_identity_id

    # 기존 repo 가 없으면 update_all 은 0 rows — no-op
    Repository.where(owner_identity_id: nil)
              .update_all(owner_identity_id: admin_identity_id)

    change_column_null :repositories, :owner_identity_id, false
  end

  def down
    remove_reference :repositories, :owner_identity, foreign_key: true
  end
end
```

- [ ] **Step 3: `create_repository_members` 내용 작성**

```ruby
class CreateRepositoryMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :repository_members do |t|
      t.references :repository, null: false, foreign_key: { on_delete: :cascade }
      t.references :identity,   null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false  # "writer" | "admin"
      t.datetime :created_at, null: false
    end

    add_index :repository_members, [:repository_id, :identity_id], unique: true
    add_index :repository_members, [:identity_id, :role]
  end
end
```

- [ ] **Step 4: `add_actor_identity_to_tag_events` 내용 작성**

```ruby
class AddActorIdentityToTagEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :tag_events, :actor_identity,
                  foreign_key: { to_table: :identities, on_delete: :nullify },
                  null: true
    # Legacy 행은 actor_identity_id = NULL.
    # TagEvent#display_actor 가 actor 문자열로 fallback 렌더.
  end
end
```

- [ ] **Step 5: 마이그레이션 dry-run (test DB)**

```bash
bin/rails db:migrate RAILS_ENV=test
bin/rails db:schema:dump RAILS_ENV=test
grep -E "owner_identity_id|repository_members|actor_identity_id" db/schema.rb
```

Expected: 세 컬럼/테이블 모두 schema.rb 에 나타남.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "$(cat <<'EOF'
feat(registry): Stage 2 migrations — owner_identity, repository_members, actor_identity

3 migrations: owner_identity_id (with admin backfill + NOT NULL), repository_members
table, actor_identity_id on tag_events (nullable, on_delete: nullify).
FK on_delete policies per tech design §1.4.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.3: `RepositoryMember` 모델 + fixtures

**Files:**
- Create: `app/models/repository_member.rb`
- Modify: `test/fixtures/personal_access_tokens.yml` (admin PAT 추가)
- Create: `test/fixtures/repository_members.yml`
- Create: `test/models/repository_member_test.rb`

**해설:** `RepositoryMember` 는 role validation 과 unique index 를 갖는 간단한 모델. fixtures 에 admin PAT 추가 (Stage 2 test 에서 admin 이 V2 push 해야 하는 케이스 대비).

- [ ] **Step 1: 실패 테스트 작성**

Create `test/models/repository_member_test.rb`:

```ruby
require "test_helper"

class RepositoryMemberTest < ActiveSupport::TestCase
  def repo
    @repo ||= Repository.create!(
      name: "member-test-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
  end

  test "valid with writer role" do
    member = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )
    assert member.valid?
  end

  test "valid with admin role" do
    member = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "admin"
    )
    assert member.valid?
  end

  test "invalid with unknown role" do
    member = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "superuser"
    )
    refute member.valid?
    assert_includes member.errors[:role], "is not included in the list"
  end

  test "uniqueness: cannot add same identity twice to same repo" do
    RepositoryMember.create!(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )
    duplicate = RepositoryMember.new(
      repository: repo,
      identity: identities(:admin_google),
      role: "admin"
    )
    refute duplicate.valid?
    assert_includes duplicate.errors[:identity_id], "has already been taken"
  end

  test "belongs_to :repository" do
    assert_equal :belongs_to, RepositoryMember.reflect_on_association(:repository).macro
  end

  test "belongs_to :identity" do
    assert_equal :belongs_to, RepositoryMember.reflect_on_association(:identity).macro
  end
end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/models/repository_member_test.rb -v
```

Expected: 6 FAIL — `uninitialized constant RepositoryMember`.

- [ ] **Step 3: 모델 생성**

Create `app/models/repository_member.rb`:

```ruby
class RepositoryMember < ApplicationRecord
  belongs_to :repository
  belongs_to :identity

  validates :role, inclusion: { in: %w[writer admin] }
  validates :identity_id, uniqueness: { scope: :repository_id }
end
```

- [ ] **Step 4: `personal_access_tokens.yml` 에 admin PAT 추가**

`test/fixtures/personal_access_tokens.yml` 에 아래 항목 append:

```yaml
admin_cli_active:
  identity: admin_google
  name: "admin-laptop"
  token_digest: <%= Digest::SHA256.hexdigest("oprk_test_admin_cli_raw") %>
  kind: cli
  expires_at: <%= 89.days.from_now %>
  created_at: <%= 1.day.ago %>
  updated_at: <%= 1.day.ago %>
```

- [ ] **Step 5: `TokenFixtures` 에 `ADMIN_CLI_RAW` 추가**

`test/support/token_fixtures.rb`:

```ruby
module TokenFixtures
  TONNY_CLI_RAW  = "oprk_test_tonny_cli_raw".freeze
  TONNY_CI_RAW   = "oprk_test_tonny_ci_raw".freeze
  TONNY_REVOKED_RAW = "oprk_test_tonny_revoked_raw".freeze
  TONNY_EXPIRED_RAW = "oprk_test_tonny_expired_raw".freeze
  ADMIN_CLI_RAW  = "oprk_test_admin_cli_raw".freeze
end
```

- [ ] **Step 6: `repository_members.yml` fixture 생성**

Create `test/fixtures/repository_members.yml`:

```yaml
# Stage 2 테스트용 — tonny가 소유한 repo의 admin_google 이 writer 멤버
# 실제 repo fixture 없음. 테스트에서 인라인 create! 사용.
# (현재 이 파일은 빈 fixtures — 필요 시 테스트에서 인라인 생성)
```

- [ ] **Step 7: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/models/repository_member_test.rb -v
```

Expected: 6 PASS.

- [ ] **Step 8: Commit**

```bash
git add app/models/repository_member.rb \
        test/models/repository_member_test.rb \
        test/fixtures/personal_access_tokens.yml \
        test/fixtures/repository_members.yml \
        test/support/token_fixtures.rb
git commit -m "$(cat <<'EOF'
feat(registry): RepositoryMember model — role validation + uniqueness

writer/admin roles, unique on [repository_id, identity_id].
Adds admin_cli_active PAT fixture for Stage 2 authz tests.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.4: `Repository` 모델 — ownership associations + 권한 메서드

**Files:**
- Modify: `app/models/repository.rb`
- Modify: `test/models/repository_test.rb`

**해설:** `writable_by?`, `deletable_by?`, `transfer_ownership_to!` 를 추가. `belongs_to :owner_identity` 와 `has_many :repository_members` 도 선언. TDD: 권한 메서드 테스트를 먼저 작성.

- [ ] **Step 1: 실패 테스트 작성**

`test/models/repository_test.rb` 끝에 아래 섹션 추가:

```ruby
  # ---------------------------------------------------------------------------
  # Stage 2: ownership associations + authorization methods
  # ---------------------------------------------------------------------------

  def owner_identity
    identities(:tonny_google)
  end

  def other_identity
    identities(:admin_google)
  end

  def owned_repo
    @owned_repo ||= Repository.create!(
      name: "owned-repo-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
  end

  test "belongs_to :owner_identity" do
    assert_equal :belongs_to, Repository.reflect_on_association(:owner_identity).macro
  end

  test "has_many :repository_members" do
    assert_equal :has_many, Repository.reflect_on_association(:repository_members).macro
  end

  test "writable_by? returns true for owner" do
    assert owned_repo.writable_by?(owner_identity)
  end

  test "writable_by? returns false for nil identity" do
    refute owned_repo.writable_by?(nil)
  end

  test "writable_by? returns false for stranger with no membership" do
    refute owned_repo.writable_by?(other_identity)
  end

  test "writable_by? returns true for writer member" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "writer")
    assert owned_repo.writable_by?(other_identity)
  end

  test "writable_by? returns true for admin member" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "admin")
    assert owned_repo.writable_by?(other_identity)
  end

  test "deletable_by? returns true for owner" do
    assert owned_repo.deletable_by?(owner_identity)
  end

  test "deletable_by? returns false for nil identity" do
    refute owned_repo.deletable_by?(nil)
  end

  test "deletable_by? returns false for writer member (not admin)" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "writer")
    refute owned_repo.deletable_by?(other_identity)
  end

  test "deletable_by? returns true for admin member" do
    RepositoryMember.create!(repository: owned_repo, identity: other_identity, role: "admin")
    assert owned_repo.deletable_by?(other_identity)
  end

  test "transfer_ownership_to! changes owner_identity_id" do
    repo = owned_repo
    repo.transfer_ownership_to!(other_identity, by: users(:tonny))
    repo.reload
    assert_equal other_identity.id, repo.owner_identity_id
  end

  test "transfer_ownership_to! adds previous owner as admin member" do
    repo = owned_repo
    repo.transfer_ownership_to!(other_identity, by: users(:tonny))
    assert RepositoryMember.exists?(repository: repo, identity: owner_identity, role: "admin")
  end

  test "transfer_ownership_to! creates ownership_transfer TagEvent" do
    repo = owned_repo
    assert_difference -> { TagEvent.where(action: "ownership_transfer").count }, +1 do
      repo.transfer_ownership_to!(other_identity, by: users(:tonny))
    end
    event = TagEvent.where(action: "ownership_transfer").last
    assert_equal users(:tonny).primary_identity.email, event.actor
    assert_equal users(:tonny).primary_identity_id, event.actor_identity_id
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/models/repository_test.rb -v 2>&1 | tail -20
```

Expected: multiple FAIL — `undefined method 'writable_by?'` / `owner_identity` association 없음.

- [ ] **Step 3: `repository.rb` 업데이트**

```ruby
class Repository < ApplicationRecord
  belongs_to :owner_identity, class_name: "Identity"
  has_many :repository_members, dependent: :destroy
  has_many :member_identities, through: :repository_members, source: :identity
  has_many :tags, dependent: :destroy
  has_many :manifests, dependent: :destroy
  has_many :tag_events, dependent: :destroy
  has_many :blob_uploads, dependent: :destroy

  SEMVER_PATTERN = /\Av?\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/

  enum :tag_protection_policy,
       { none: "none", semver: "semver", all_except_latest: "all_except_latest", custom_regex: "custom_regex" },
       default: :none, prefix: :protection

  validates :name, presence: true, uniqueness: true
  validates :tag_protection_pattern, presence: true, if: :protection_custom_regex?
  validate :tag_protection_pattern_is_valid_regex, if: :protection_custom_regex?

  before_save :clear_tag_protection_pattern_unless_custom_regex

  # ---------------------------------------------------------------------------
  # Authorization methods (Stage 2)
  # ---------------------------------------------------------------------------

  # @param identity [Identity, nil]
  # @return [Boolean]
  def writable_by?(identity)
    return false if identity.nil?
    return true if owner_identity_id == identity.id
    repository_members.exists?(identity_id: identity.id, role: %w[writer admin])
  end

  # @param identity [Identity, nil]
  # @return [Boolean]
  def deletable_by?(identity)
    return false if identity.nil?
    return true if owner_identity_id == identity.id
    repository_members.exists?(identity_id: identity.id, role: "admin")
  end

  # Atomically transfers ownership and records an audit TagEvent.
  #
  # @param new_owner_identity [Identity]
  # @param by [User] the user performing the transfer (used for actor attribution)
  def transfer_ownership_to!(new_owner_identity, by:)
    transaction do
      previous_owner_id = owner_identity_id
      update!(owner_identity_id: new_owner_identity.id)
      repository_members
        .find_or_create_by!(identity_id: previous_owner_id) { |m| m.role = "admin" }
      TagEvent.create!(
        repository: self,
        tag_name: "-",
        action: "ownership_transfer",
        actor: by.primary_identity.email,
        actor_identity_id: by.primary_identity_id,
        occurred_at: Time.current
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Tag protection
  # ---------------------------------------------------------------------------

  def tag_protected?(tag_name)
    case tag_protection_policy
    when "none"              then false
    when "semver"            then tag_name.match?(SEMVER_PATTERN)
    when "all_except_latest" then tag_name != "latest"
    when "custom_regex"      then !!(protection_regex && tag_name.match?(protection_regex))
    end
  end

  def enforce_tag_protection!(tag_name, new_digest: nil, existing_tag: :unset)
    return unless tag_protected?(tag_name)

    if new_digest
      current = existing_tag.equal?(:unset) ? tags.find_by(name: tag_name) : existing_tag
      return if current && current.manifest.digest == new_digest
    end

    raise Registry::TagProtected.new(tag: tag_name, policy: tag_protection_policy)
  end

  private

  def protection_regex
    return nil if tag_protection_pattern.blank?
    @protection_regex ||= Regexp.new(tag_protection_pattern)
  rescue RegexpError
    nil
  end

  def tag_protection_pattern_is_valid_regex
    return if tag_protection_pattern.blank?
    Regexp.new(tag_protection_pattern)
  rescue RegexpError => e
    errors.add(:tag_protection_pattern, "is not a valid regex: #{e.message}")
  end

  def clear_tag_protection_pattern_unless_custom_regex
    self.tag_protection_pattern = nil unless protection_custom_regex?
    @protection_regex = nil if tag_protection_policy_changed? || tag_protection_pattern_changed?
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/models/repository_test.rb -v 2>&1 | tail -20
```

Expected: all PASS (기존 + 새로 추가된 테스트).

- [ ] **Step 5: Commit**

```bash
git add app/models/repository.rb test/models/repository_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): Repository — owner_identity + writable_by?/deletable_by?/transfer_ownership_to!

Stage 2 authorization methods. Owner always permitted; members checked by role.
transfer_ownership_to! is atomic (transaction) with TagEvent audit trail.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.5: `TagEvent` — `belongs_to :actor_identity` + `ownership_transfer` validation

**Files:**
- Modify: `app/models/tag_event.rb`
- Modify: `test/models/tag_event_test.rb`

**해설:** `actor_identity` 는 optional (기존 legacy 행은 NULL). `display_actor` 는 `actor_identity` 가 있으면 그 user email 을 우선 사용, 없으면 기존 문자열 기반 로직. `"ownership_transfer"` 를 action 허용 목록에 추가.

- [ ] **Step 1: 실패 테스트 작성**

`test/models/tag_event_test.rb` 에 아래 테스트 추가:

```ruby
  test "action inclusion allows ownership_transfer" do
    event = TagEvent.new(
      repository: repository,
      tag_name: "-",
      action: "ownership_transfer",
      actor: "tonny@timberay.com",
      occurred_at: Time.current
    )
    assert event.valid?, event.errors.full_messages.inspect
  end

  test "belongs_to :actor_identity is optional" do
    event = TagEvent.new(
      repository: repository,
      tag_name: "v1",
      action: "delete",
      actor: "retention-policy",
      occurred_at: Time.current
    )
    # actor_identity_id = nil — should still be valid
    assert event.valid?, event.errors.full_messages.inspect
  end

  test "display_actor prefers actor_identity email when present" do
    identity = identities(:tonny_google)
    event = TagEvent.new(actor: "some-old-string", actor_identity: identity)
    assert_equal identity.email, event.display_actor
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/models/tag_event_test.rb -v
```

Expected: 3 FAIL — `ownership_transfer` validation 실패, `actor_identity` association 없음.

- [ ] **Step 3: `tag_event.rb` 업데이트**

```ruby
class TagEvent < ApplicationRecord
  belongs_to :repository
  belongs_to :actor_identity, class_name: "Identity", optional: true

  validates :tag_name, presence: true
  validates :action, presence: true,
            inclusion: { in: %w[create update delete ownership_transfer] }
  validates :occurred_at, presence: true

  # Render actor for display. Prefers actor_identity.email when FK is present
  # (Stage 2 rows). Falls back to string-based heuristic for legacy rows.
  def display_actor
    return actor_identity.email if actor_identity.present?
    return actor if actor.to_s.include?("@")
    "<system: #{actor.to_s.delete_prefix('system:')}>"
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/models/tag_event_test.rb -v
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/tag_event.rb test/models/tag_event_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): TagEvent — belongs_to actor_identity (optional) + ownership_transfer action

Stage 2: actor_identity FK (nullable, on_delete nullify).
display_actor prefers identity email over legacy string fallback.
Extends action validation to include ownership_transfer.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.6: `RepositoryAuthorization` concern

**Files:**
- Create: `app/controllers/concerns/repository_authorization.rb`
- Create: `test/controllers/concerns/repository_authorization_test.rb`

**해설:** concern 은 `authorize_for!` 만 정의하고 `current_user` 는 호출자 컨트롤러에 의존. `include RepositoryAuthorization` 만으로 V2(API) 와 Web(Base) 양쪽에서 동작하도록 설계. rescue_from 매핑은 각 base controller 에서 별도 정의 (PR-2 에서 추가).

테스트는 stub controller 패턴 사용:

- [ ] **Step 1: 실패 테스트 작성**

Create `test/controllers/concerns/repository_authorization_test.rb`:

```ruby
require "test_helper"

# Stub controller that includes the concern so we can unit-test authorize_for!
# without wiring a real route.
class StubAuthzController
  include RepositoryAuthorization

  attr_accessor :current_user, :repository

  def initialize(user: nil, repo: nil)
    @current_user = user
    @repository   = repo
  end
end

class RepositoryAuthorizationTest < ActiveSupport::TestCase
  def owner
    @owner ||= users(:tonny)
  end

  def other_user
    @other_user ||= users(:admin)
  end

  def repo
    @repo ||= Repository.create!(
      name: "authz-test-#{SecureRandom.hex(4)}",
      owner_identity: owner.primary_identity
    )
  end

  def ctrl(user: owner, repository: repo)
    StubAuthzController.new(user: user, repo: repository)
  end

  test "authorize_for!(:write) does not raise for owner" do
    assert_nothing_raised { ctrl.authorize_for!(:write) }
  end

  test "authorize_for!(:write) raises ForbiddenAction for non-member" do
    c = ctrl(user: other_user)
    err = assert_raises(Auth::ForbiddenAction) { c.authorize_for!(:write) }
    assert_equal :write, err.action
    assert_equal repo, err.repository
  end

  test "authorize_for!(:delete) does not raise for owner" do
    assert_nothing_raised { ctrl.authorize_for!(:delete) }
  end

  test "authorize_for!(:delete) raises ForbiddenAction for writer member" do
    RepositoryMember.create!(
      repository: repo,
      identity: other_user.primary_identity,
      role: "writer"
    )
    c = ctrl(user: other_user)
    assert_raises(Auth::ForbiddenAction) { c.authorize_for!(:delete) }
  end

  test "authorize_for!(:delete) does not raise for admin member" do
    RepositoryMember.create!(
      repository: repo,
      identity: other_user.primary_identity,
      role: "admin"
    )
    c = ctrl(user: other_user)
    assert_nothing_raised { c.authorize_for!(:delete) }
  end

  test "authorize_for! raises Unauthenticated when current_user is nil" do
    c = ctrl(user: nil)
    assert_raises(Auth::Unauthenticated) { c.authorize_for!(:write) }
  end

  test "authorize_for!(:read) always returns without raising" do
    c = ctrl(user: other_user)
    assert_nothing_raised { c.authorize_for!(:read) }
  end
end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/controllers/concerns/repository_authorization_test.rb -v
```

Expected: multiple FAIL — `uninitialized constant RepositoryAuthorization`.

- [ ] **Step 3: concern 생성**

Create `app/controllers/concerns/repository_authorization.rb`:

```ruby
module RepositoryAuthorization
  extend ActiveSupport::Concern

  # Authorizes current_user to perform `action` on @repository.
  #
  # @param action [:read, :write, :delete]
  # @raise [Auth::Unauthenticated] if current_user is nil
  # @raise [Auth::ForbiddenAction]  if action is denied
  #
  # Note: @repository must be assigned before calling this method.
  # Note: rescue_from mappings are defined in each base controller (V2/Web).
  def authorize_for!(action)
    raise Auth::Unauthenticated if current_user.nil?

    identity = current_user.primary_identity

    allowed = case action
              when :read   then true  # Stage 3: repo visibility gate
              when :write  then @repository.writable_by?(identity)
              when :delete then @repository.deletable_by?(identity)
              end

    return if allowed

    raise Auth::ForbiddenAction.new(repository: @repository, action: action)
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/controllers/concerns/repository_authorization_test.rb -v
```

Expected: 7 PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/repository_authorization.rb \
        test/controllers/concerns/repository_authorization_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): RepositoryAuthorization concern — authorize_for!(action)

Includable in both ActionController::API and ActionController::Base.
rescue_from wiring deferred to PR-2 (behavioral). Stage 3: :read gate.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.7: PR-1 전체 테스트 통과 + 최종 확인

**Files:**
- No new files. 전체 suite 확인.

- [ ] **Step 1: 전체 테스트 실행**

```bash
bin/rails test -v 2>&1 | tail -30
```

Expected: 기존 suite + PR-1 신규 테스트 모두 PASS. 0 failures.

- [ ] **Step 2: PR-1 브랜치 push**

```bash
git push -u origin feature/registry-auth-stage2-pr1
```

PR-1 은 여기까지. PR 생성 후 CI green 확인.

---

## Phase 2 — PR-2: Behavioral (Authz Enforcement + First-Pusher + Critical Gaps)

PR-1 머지 후 `main` 에서 `feature/registry-auth-stage2-pr2` 분기.

```bash
git checkout main && git pull
git checkout -b feature/registry-auth-stage2-pr2
```

---

### Task 2.1: `V2::BaseController` — `RepositoryAuthorization` include + rescue_from

**Files:**
- Modify: `app/controllers/v2/base_controller.rb`
- Modify: `test/controllers/v2/base_controller_test.rb`

**해설:** V2 base 에 concern include + `Auth::ForbiddenAction` rescue_from 추가. 이 시점에서는 아직 어떤 action 에도 `before_action -> { authorize_for! }` 없음 (controller 별로 추가). rescue_from 만 먼저 배선.

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/v2/base_controller_test.rb` 에 아래 추가:

```ruby
  test "Auth::ForbiddenAction renders 403 JSON with DENIED code" do
    # 직접 raise 를 시뮬레이션 — 아직 실제 before_action 없으나 rescue_from 동작 확인
    repo = Repository.create!(
      name: "v2-base-forbidden-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    # anonymous (no auth) → 401 은 이미 있음. 403 은 별도 케이스
    # 이 테스트는 concern + rescue_from 이 연결되면 통과
    skip "rescue_from wired in this task — tested via ManifestsController in Task 2.2"
  end
```

실제 통합 테스트는 Task 2.2 에서. 이 단계는 rescue_from 배선 commit.

- [ ] **Step 2: `v2/base_controller.rb` 업데이트**

```ruby
class V2::BaseController < ActionController::API
  include RepositoryAuthorization

  before_action :set_registry_headers
  before_action :authenticate_v2_basic!, unless: :anonymous_pull_allowed?

  attr_reader :current_user, :current_pat

  rescue_from Registry::BlobUnknown,       with: ->(e) { render_error("BLOB_UNKNOWN", e.message, 404) }
  rescue_from Registry::BlobUploadUnknown, with: ->(e) { render_error("BLOB_UPLOAD_UNKNOWN", e.message, 404) }
  rescue_from Registry::ManifestUnknown,   with: ->(e) { render_error("MANIFEST_UNKNOWN", e.message, 404) }
  rescue_from Registry::ManifestInvalid,   with: ->(e) { render_error("MANIFEST_INVALID", e.message, 400) }
  rescue_from Registry::NameUnknown,       with: ->(e) { render_error("NAME_UNKNOWN", e.message, 404) }
  rescue_from Registry::DigestMismatch,    with: ->(e) { render_error("DIGEST_INVALID", e.message, 400) }
  rescue_from Registry::Unsupported,       with: ->(e) { render_error("UNSUPPORTED", e.message, 415) }
  rescue_from Registry::TagProtected,      with: ->(e) { render_error("DENIED", e.message, 409, detail: e.detail) }
  rescue_from Auth::Unauthenticated,       with: ->(_e) { render_v2_challenge }
  rescue_from Auth::ForbiddenAction, with: ->(e) {
    render_error(
      "DENIED",
      "insufficient_scope: #{e.action} privilege required on repository '#{e.repository.name}'",
      403,
      detail: { action: e.action.to_s, repository: e.repository.name }
    )
  }

  def index
    render json: {}
  end

  private

  ANONYMOUS_PULL_ENDPOINTS = [
    %w[base index],
    %w[catalog index],
    %w[tags index],
    %w[manifests show],
    %w[blobs show]
  ].freeze

  def anonymous_pull_allowed?
    return false unless Rails.configuration.x.registry.anonymous_pull_enabled
    return false unless request.get? || request.head?
    ANONYMOUS_PULL_ENDPOINTS.include?([ controller_name, action_name ])
  end

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

  def render_v2_challenge
    response.headers["WWW-Authenticate"]                = %(Basic realm="Registry")
    response.headers["Docker-Distribution-API-Version"] = "registry/2.0"
    render json: {
      errors: [ { code: "UNAUTHORIZED", message: "authentication required", detail: nil } ]
    }, status: :unauthorized
  end

  def set_registry_headers
    response.headers["Docker-Distribution-API-Version"] = "registry/2.0"
  end

  def render_error(code, message, status, detail: {})
    render json: { errors: [ { code: code, message: message, detail: detail } ] }, status: status
  end

  def repo_name
    params[:ns].present? ? "#{params[:ns]}/#{params[:name]}" : params[:name]
  end

  def find_repository!
    Repository.find_by!(name: repo_name)
  rescue ActiveRecord::RecordNotFound
    raise Registry::NameUnknown, "repository '#{repo_name}' not found"
  end
end
```

- [ ] **Step 3: 기존 테스트 통과 확인**

```bash
bin/rails test test/controllers/v2/base_controller_test.rb -v
```

Expected: all PASS (rescue_from 추가가 기존 동작 깨지 않음).

- [ ] **Step 4: Commit**

```bash
git add app/controllers/v2/base_controller.rb \
        test/controllers/v2/base_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): V2::BaseController — include RepositoryAuthorization + rescue_from ForbiddenAction

ForbiddenAction → 403 DENIED with action/repository detail.
Unauthenticated → existing render_v2_challenge path.
No before_action gates yet — wired per-controller in subsequent tasks.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.2: `ApplicationController` — `RepositoryAuthorization` include + rescue_from

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `test/controllers/repositories_controller_test.rb`

**해설:** Web UI base 에도 concern include. `Auth::ForbiddenAction` → redirect with alert. `Auth::Unauthenticated` → Google OAuth redirect.

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/repositories_controller_test.rb` 에 아래 추가:

```ruby
  # ---------------------------------------------------------------------------
  # Stage 2: destroy authz
  # ---------------------------------------------------------------------------

  test "DELETE /repositories/:name by non-owner returns 302 redirect with alert" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "destroy-authz-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )

    # admin user (not owner) tries to delete
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    delete "/repositories/#{repo.name}"

    assert_redirected_to repository_path(repo.name)
    assert_match(/permission/, flash[:alert])
  end

  test "DELETE /repositories/:name by owner succeeds" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "destroy-owner-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )

    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    delete "/repositories/#{repo.name}"

    assert_redirected_to root_path
    refute Repository.exists?(name: repo.name)
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/controllers/repositories_controller_test.rb -v 2>&1 | tail -20
```

Expected: 2 FAIL — no authz gate yet on destroy.

- [ ] **Step 3: `application_controller.rb` 업데이트**

```ruby
class ApplicationController < ActionController::Base
  include RepositoryAuthorization

  allow_browser versions: :modern

  helper_method :current_user, :signed_in?

  rescue_from Auth::Unauthenticated, with: -> { redirect_to "/auth/google_oauth2" }
  rescue_from Auth::ForbiddenAction, with: ->(e) {
    redirect_to repository_path(e.repository.name),
                alert: "You don't have permission to #{e.action} in '#{e.repository.name}'."
  }

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user =
      if session[:user_id]
        User.find_by(id: session[:user_id]).tap do |u|
          session.delete(:user_id) if u.nil?
        end
      end
  end

  def signed_in?
    current_user.present?
  end
end
```

- [ ] **Step 4: `repositories_controller.rb` destroy 에 authz 추가**

`app/controllers/repositories_controller.rb` の `destroy` 메서드 앞에 before_action 추가:

```ruby
class RepositoriesController < ApplicationController
  before_action :set_repository_for_authz, only: [:destroy]

  # ... 기존 index/show/update 메서드 유지 ...

  def destroy
    repository = Repository.find_by!(name: params[:name])

    repository.manifests.includes(layers: :blob).find_each do |manifest|
      manifest.layers.each { |layer| layer.blob.decrement!(:references_count) }
    end

    repository.destroy!
    redirect_to root_path, notice: "Repository '#{repository.name}' deleted."
  end

  private

  def set_repository_for_authz
    @repository = Repository.find_by!(name: params[:name])
    authorize_for!(:delete)
  end

  def repository_params
    params.expect(repository: [ :description, :maintainer, :tag_protection_policy, :tag_protection_pattern ])
  end
end
```

- [ ] **Step 5: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/controllers/repositories_controller_test.rb -v 2>&1 | tail -20
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/application_controller.rb \
        app/controllers/repositories_controller.rb \
        test/controllers/repositories_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): ApplicationController + RepositoriesController — authz enforcement on destroy

RepositoryAuthorization included in ApplicationController base.
ForbiddenAction → redirect with alert; Unauthenticated → OAuth redirect.
RepositoriesController#destroy requires :delete permission.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.3: `V2::ManifestsController` — authz + `actor_identity_id` threading

**Files:**
- Modify: `app/controllers/v2/manifests_controller.rb`
- Modify: `test/controllers/v2/manifests_controller_test.rb`

**해설:** `update` 에 `:write` gate, `destroy` 에 `:delete` gate. `@repository` 를 set 해주는 before_action 도 추가. `destroy` 에서 `actor_identity_id: current_user.primary_identity_id` 주입.

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/v2/manifests_controller_test.rb` 에 아래 추가:

```ruby
  # ---------------------------------------------------------------------------
  # Stage 2: authorization
  # ---------------------------------------------------------------------------

  test "PUT /v2/:name/manifests/:ref by non-member returns 403" do
    # admin user is not owner/member of tonny's repo
    repo = Repository.create!(
      name: "authz-mfst-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com"))
    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "PUT /v2/:name/manifests/:ref by owner returns 201" do
    # tonny creates their own repo and pushes — already covered by existing tests
    # but explicitly assert owner is allowed when owner_identity is set
    repo = Repository.create!(
      name: "authz-owner-push-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    assert_response 201
  end

  test "DELETE /v2/:name/manifests/:ref by non-member returns 403" do
    repo = Repository.create!(
      name: "authz-del-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    # seed a manifest
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    digest = response.headers["Docker-Content-Digest"]

    delete "/v2/#{repo.name}/manifests/#{digest}",
           headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 403
  end

  test "DELETE /v2/:name/manifests/:ref records actor_identity_id" do
    repo = Repository.create!(
      name: "authz-actid-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    digest = response.headers["Docker-Content-Digest"]

    delete "/v2/#{repo.name}/manifests/#{digest}", headers: basic_auth_for
    assert_response 202

    event = TagEvent.order(:created_at).last
    assert_equal identities(:tonny_google).id, event.actor_identity_id
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/controllers/v2/manifests_controller_test.rb -v 2>&1 | grep -E "FAIL|Error" | head -10
```

Expected: 4 FAIL/Error — no authz gate.

- [ ] **Step 3: `manifests_controller.rb` 업데이트**

```ruby
class V2::ManifestsController < V2::BaseController
  SUPPORTED_MEDIA_TYPES = [
    "application/vnd.docker.distribution.manifest.v2+json"
  ].freeze

  before_action :set_repository_for_authz, only: [ :update, :destroy ]

  def show
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

    response.headers["Docker-Content-Digest"] = manifest.digest
    response.headers["Content-Type"] = manifest.media_type
    response.headers["Content-Length"] = manifest.size.to_s

    if request.head?
      head :ok
    else
      record_pull_event(manifest)
      render json: manifest.payload, content_type: manifest.media_type
    end
  end

  def update
    unless SUPPORTED_MEDIA_TYPES.include?(request.content_type)
      raise Registry::Unsupported,
        "Unsupported manifest media type: #{request.content_type}. " \
        "This registry supports single-platform V2 Schema 2 manifests only. " \
        "Use: docker build --platform linux/amd64 -t <image> ."
    end

    payload = request.raw_post
    manifest = ManifestProcessor.new.call(
      repo_name,
      params[:reference],
      request.content_type,
      payload,
      actor: current_user.email
    )

    response.headers["Docker-Content-Digest"] = manifest.digest
    response.headers["Location"] = "/v2/#{repo_name}/manifests/#{manifest.digest}"
    head :created
  end

  def destroy
    manifest = find_manifest!(@repository, params[:reference])

    manifest.tags.each { |tag| @repository.enforce_tag_protection!(tag.name) }

    manifest.tags.each do |tag|
      TagEvent.create!(
        repository: @repository,
        tag_name: tag.name,
        action: "delete",
        previous_digest: manifest.digest,
        actor: current_user.email,
        actor_identity_id: current_user.primary_identity_id,
        occurred_at: Time.current
      )
    end

    manifest.tags.destroy_all

    manifest.layers.each do |layer|
      layer.blob.decrement!(:references_count)
    end

    manifest.destroy!
    head :accepted
  end

  private

  def set_repository_for_authz
    @repository = find_repository!
    case action_name
    when "update"  then authorize_for!(:write)
    when "destroy" then authorize_for!(:delete)
    end
  end

  def find_manifest!(repository, reference)
    if reference.start_with?("sha256:")
      repository.manifests.find_by!(digest: reference)
    else
      tag = repository.tags.find_by!(name: reference)
      tag.manifest
    end
  rescue ActiveRecord::RecordNotFound
    raise Registry::ManifestUnknown, "manifest '#{reference}' not found"
  end

  def record_pull_event(manifest)
    manifest.increment!(:pull_count)
    manifest.update_column(:last_pulled_at, Time.current)

    tag_name = params[:reference].start_with?("sha256:") ? nil : params[:reference]
    PullEvent.create!(
      manifest: manifest,
      repository: manifest.repository,
      tag_name: tag_name,
      user_agent: request.user_agent,
      remote_ip: request.remote_ip,
      occurred_at: Time.current
    )
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/controllers/v2/manifests_controller_test.rb -v 2>&1 | tail -20
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/v2/manifests_controller.rb \
        test/controllers/v2/manifests_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): V2::ManifestsController — authorize_for! + actor_identity_id threading

update: requires :write; destroy: requires :delete.
destroy now records actor_identity_id on TagEvent (Stage 2 FK).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.4: `V2::BlobsController` — `authorize_for!(:delete)`

**Files:**
- Modify: `app/controllers/v2/blobs_controller.rb`
- Modify: `test/controllers/v2/blobs_controller_test.rb`

**해설:** tech design D6 — `BlobsController#destroy` 는 admin-only. `@repository` 가 blob destroy 의 namespace 역할이므로 before_action 으로 set + `:delete` authorize.

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/v2/blobs_controller_test.rb` 에 아래 추가:

```ruby
  # ---------------------------------------------------------------------------
  # Stage 2: destroy authz
  # ---------------------------------------------------------------------------

  test "DELETE /v2/:name/blobs/:digest by non-owner returns 403" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "blob-del-authz-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    # Upload a blob first using tonny
    blob_content = "blob for authz test"
    digest = DigestCalculator.compute(blob_content)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(blob_content))
    Blob.create!(digest: digest, size: blob_content.bytesize)

    delete "/v2/#{repo.name}/blobs/#{digest}",
           headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "DELETE /v2/:name/blobs/:digest by owner returns 202" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "blob-del-owner-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    blob_content = "owner blob"
    digest = DigestCalculator.compute(blob_content)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(blob_content))
    Blob.create!(digest: digest, size: blob_content.bytesize)

    delete "/v2/#{repo.name}/blobs/#{digest}", headers: basic_auth_for
    assert_response 202
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/controllers/v2/blobs_controller_test.rb -v 2>&1 | grep -E "FAIL|Error" | head -5
```

Expected: 2 FAIL — no authz gate on destroy.

- [ ] **Step 3: `blobs_controller.rb` 업데이트**

```ruby
class V2::BlobsController < V2::BaseController
  before_action :set_repository_for_delete_authz, only: [:destroy]

  def show
    find_repository!
    blob = Blob.find_by!(digest: params[:digest])
    blob_store = BlobStore.new

    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found" unless blob_store.exists?(params[:digest])

    response.headers["Docker-Content-Digest"] = blob.digest
    response.headers["Content-Length"] = blob.size.to_s
    response.headers["Content-Type"] = blob.content_type || "application/octet-stream"

    if request.head?
      head :ok
    else
      send_file blob_store.path_for(blob.digest), type: "application/octet-stream", disposition: "inline"
    end
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found"
  end

  def destroy
    blob = Blob.find_by!(digest: params[:digest])
    BlobStore.new.delete(blob.digest)
    blob.destroy!
    head :accepted
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found"
  end

  private

  def set_repository_for_delete_authz
    @repository = find_repository!
    authorize_for!(:delete)
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/controllers/v2/blobs_controller_test.rb -v 2>&1 | tail -10
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/v2/blobs_controller.rb \
        test/controllers/v2/blobs_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): V2::BlobsController#destroy — authorize_for!(:delete)

Admin/owner-only blob deletion per tech design D6.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.5: `V2::BlobUploadsController` — first-pusher-owner + `authorize_for!(:write)`

**Files:**
- Modify: `app/controllers/v2/blob_uploads_controller.rb`
- Modify: `test/controllers/v2/blob_uploads_controller_test.rb`

**해설:** `ensure_repository!` 를 first-pusher 패턴으로 교체. `find_or_create_by!` 에서 `owner_identity_id` 주입. `ActiveRecord::RecordNotUnique` 시 단 한 번 retry (레이스 컨디션 처리). create 이후에도 기존 repo 의 write 권한 체크.

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/v2/blob_uploads_controller_test.rb` 에 아래 추가:

```ruby
  # ---------------------------------------------------------------------------
  # Stage 2: first-pusher-owner + write authz
  # ---------------------------------------------------------------------------

  test "POST /v2/:name/blobs/uploads creates repo with current_user as owner" do
    repo_name = "fp-owner-#{SecureRandom.hex(4)}"
    refute Repository.exists?(name: repo_name)

    post "/v2/#{repo_name}/blobs/uploads", headers: basic_auth_for
    assert_response 202

    repo = Repository.find_by!(name: repo_name)
    assert_equal identities(:tonny_google).id, repo.owner_identity_id
  end

  test "POST /v2/:name/blobs/uploads by non-member of existing repo returns 403" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "fp-nonmember-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )

    post "/v2/#{repo.name}/blobs/uploads",
         headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "POST /v2/:name/blobs/uploads by writer member of existing repo returns 202" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "fp-writer-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    RepositoryMember.create!(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )

    post "/v2/#{repo.name}/blobs/uploads",
         headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 202
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/controllers/v2/blob_uploads_controller_test.rb -v 2>&1 | grep -E "FAIL|Error" | head -10
```

Expected: 3 FAIL — `ensure_repository!` 에 `owner_identity_id` 없고 authz 없음.

- [ ] **Step 3: `blob_uploads_controller.rb` 업데이트**

`ensure_repository!` 메서드를 교체:

```ruby
class V2::BlobUploadsController < V2::BaseController
  def create
    ensure_repository!

    if params[:mount].present? && params[:from].present?
      handle_blob_mount
    elsif params[:digest].present?
      handle_monolithic_upload
    else
      handle_start_upload
    end
  end

  def update
    upload = find_upload!
    blob_store.append_upload(upload.uuid, request.body)
    upload.update!(byte_offset: blob_store.upload_size(upload.uuid))

    response.headers["Location"] = upload_url(upload)
    response.headers["Docker-Upload-UUID"] = upload.uuid
    response.headers["Range"] = "0-#{upload.byte_offset - 1}"
    head :accepted
  end

  def complete
    upload = find_upload!
    digest = params[:digest]

    if request.body.size > 0
      blob_store.append_upload(upload.uuid, request.body)
    end

    blob_store.finalize_upload(upload.uuid, digest)

    Blob.create_or_find_by!(digest: digest) do |b|
      b.size = blob_store.size(digest)
      b.content_type = "application/octet-stream"
    end

    upload.destroy!

    response.headers["Docker-Content-Digest"] = digest
    response.headers["Location"] = "/v2/#{repo_name}/blobs/#{digest}"
    head :created
  end

  def destroy
    upload = find_upload!
    blob_store.cancel_upload(upload.uuid)
    upload.destroy!
    head :no_content
  end

  private

  # First-pusher-owner pattern (tech design D2).
  # If the repository does not exist, the authenticated user becomes owner.
  # If it exists, write permission is checked.
  # Handles SQLite unique-constraint race with a single retry.
  def ensure_repository!
    identity_id = current_user.primary_identity_id
    @repository = Repository.find_or_create_by!(name: repo_name) do |r|
      r.owner_identity_id = identity_id
    end
    # Existing repo: verify write access
    authorize_for!(:write) unless @repository.owner_identity_id == identity_id
  rescue ActiveRecord::RecordNotUnique
    @repository = Repository.find_by!(name: repo_name)
    authorize_for!(:write)
  end

  def find_upload!
    BlobUpload.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUploadUnknown, "upload '#{params[:uuid]}' not found"
  end

  def handle_start_upload
    uuid = SecureRandom.uuid
    blob_store.create_upload(uuid)
    upload = @repository.blob_uploads.create!(uuid: uuid)

    response.headers["Location"] = upload_url(upload)
    response.headers["Docker-Upload-UUID"] = uuid
    response.headers["Range"] = "0-0"
    head :accepted
  end

  def handle_monolithic_upload
    digest = params[:digest]
    uuid = SecureRandom.uuid
    blob_store.create_upload(uuid)
    blob_store.append_upload(uuid, request.body)
    blob_store.finalize_upload(uuid, digest)

    Blob.create_or_find_by!(digest: digest) do |b|
      b.size = blob_store.size(digest)
      b.content_type = "application/octet-stream"
    end

    response.headers["Docker-Content-Digest"] = digest
    response.headers["Location"] = "/v2/#{repo_name}/blobs/#{digest}"
    head :created
  end

  def handle_blob_mount
    blob = Blob.find_by(digest: params[:mount])

    if blob && blob_store.exists?(params[:mount])
      ensure_repository!
      blob.increment!(:references_count)

      response.headers["Docker-Content-Digest"] = params[:mount]
      response.headers["Location"] = "/v2/#{repo_name}/blobs/#{params[:mount]}"
      head :created
    else
      handle_start_upload
    end
  end

  def upload_url(upload)
    "/v2/#{repo_name}/blobs/uploads/#{upload.uuid}"
  end

  def blob_store
    @blob_store ||= BlobStore.new
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/controllers/v2/blob_uploads_controller_test.rb -v 2>&1 | tail -10
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/v2/blob_uploads_controller.rb \
        test/controllers/v2/blob_uploads_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): V2::BlobUploadsController — first-pusher-owner + authorize_for!(:write)

ensure_repository! assigns owner_identity_id on first push (D2).
Existing repo: write authorization checked. RecordNotUnique race: single retry.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.6: `TagsController` — `authorize_for!(:delete)` + `actor_identity_id`

**Files:**
- Modify: `app/controllers/tags_controller.rb`
- Modify: `test/controllers/tags_controller_test.rb`

**해설:** Web UI tag delete 에 권한 게이트 + `actor_identity_id` 주입. Web UI 는 세션 기반이므로 `current_user` 가 없으면 OAuth redirect.

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/tags_controller_test.rb` 에 아래 추가:

```ruby
  # ---------------------------------------------------------------------------
  # Stage 2: destroy authz + actor_identity_id
  # ---------------------------------------------------------------------------

  test "DELETE tag by non-owner/non-member redirects with alert" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "tags-authz-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    tag = manifest.tags.create!(repository: repo, name: "v1")

    # admin user (not owner)
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    delete "/repositories/#{repo.name}/tags/#{tag.name}"

    assert_redirected_to repository_path(repo.name)
    assert_match(/permission/, flash[:alert])
    assert Tag.exists?(id: tag.id), "tag should still exist"
  end

  test "DELETE tag by owner records actor_identity_id on TagEvent" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "tags-actid-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    tag = manifest.tags.create!(repository: repo, name: "v1")

    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    delete "/repositories/#{repo.name}/tags/#{tag.name}"

    assert_redirected_to repository_path(repo.name)
    event = TagEvent.order(:occurred_at).last
    assert_equal identities(:tonny_google).id, event.actor_identity_id
  end
```

- [ ] **Step 2: 테스트 실행 (Red 확인)**

```bash
bin/rails test test/controllers/tags_controller_test.rb -v 2>&1 | grep -E "FAIL|Error" | head -5
```

Expected: 2 FAIL.

- [ ] **Step 3: `tags_controller.rb` 업데이트**

```ruby
class TagsController < ApplicationController
  before_action :set_repository
  before_action :set_tag, only: [ :show, :destroy, :history ]
  before_action :authorize_delete!, only: [:destroy]

  def show
    @manifest = @tag.manifest
    @layers = @manifest.layers.includes(:blob).order(:position)
  end

  def destroy
    @repository.enforce_tag_protection!(@tag.name)

    TagEvent.create!(
      repository: @repository,
      tag_name: @tag.name,
      action: "delete",
      previous_digest: @tag.manifest.digest,
      actor: current_user.primary_identity.email,
      actor_identity_id: current_user.primary_identity_id,
      occurred_at: Time.current
    )
    @tag.destroy!
    redirect_to repository_path(@repository.name), notice: "Tag '#{@tag.name}' deleted."
  rescue Registry::TagProtected => e
    redirect_to repository_path(@repository.name),
      alert: "Tag '#{@tag.name}' is protected by policy '#{e.detail[:policy]}'. Change the repository's tag protection policy to delete it."
  end

  def history
    @events = TagEvent.where(repository: @repository, tag_name: @tag.name).order(occurred_at: :desc)
  end

  private

  def set_repository
    @repository = Repository.find_by!(name: params[:repository_name])
  end

  def set_tag
    @tag = @repository.tags.find_by!(name: params[:name])
  end

  def authorize_delete!
    authorize_for!(:delete)
  end
end
```

- [ ] **Step 4: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/controllers/tags_controller_test.rb -v 2>&1 | tail -10
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/tags_controller.rb \
        test/controllers/tags_controller_test.rb
git commit -m "$(cat <<'EOF'
feat(registry): TagsController#destroy — authorize_for!(:delete) + actor_identity_id

Stage 2: delete requires owner or admin membership.
TagEvent records actor_identity_id FK for identity-linked audit trail.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.7: Critical Gap #1 — `retention_ownership_interaction` 테스트

**Files:**
- Create: `test/integration/retention_ownership_interaction_test.rb`

**해설:** tech design §7.1 의 3 시나리오. 시나리오 3 은 `stub_any_instance` 불가(Minitest 6.0.4 제약) 이므로 간접 검증 패턴으로 대체: retention job 이 `current_user = nil` 상태로 실행되기 때문에 `authorize_for!` 를 잘못 호출하면 `Auth::Unauthenticated` 를 raise. 테스트는 job 실행 후 raise 없음을 assert.

- [ ] **Step 1: 테스트 파일 작성 (Red + Green 동시 — job 은 이미 authorize_for! 없음)**

Create `test/integration/retention_ownership_interaction_test.rb`:

```ruby
require "test_helper"

class RetentionOwnershipInteractionTest < ActionDispatch::IntegrationTest
  setup do
    ENV["RETENTION_ENABLED"]            = "true"
    ENV["RETENTION_DAYS_WITHOUT_PULL"]  = "90"
    ENV["RETENTION_MIN_PULL_COUNT"]     = "5"
    ENV["RETENTION_PROTECT_LATEST"]     = "true"
  end

  teardown do
    %w[RETENTION_ENABLED RETENTION_DAYS_WITHOUT_PULL
       RETENTION_MIN_PULL_COUNT RETENTION_PROTECT_LATEST].each { |k| ENV.delete(k) }
  end

  # Scenario 1: retention deletes stale tag on another-user-owned repo without raising
  test "retention deletes owned-by-other stale tag without raising" do
    other_identity = identities(:admin_google)
    repo = Repository.create!(
      name: "retention-other-#{SecureRandom.hex(4)}",
      owner_identity: other_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:stale#{SecureRandom.hex(28)}",
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

  # Scenario 2: retention skips tag protected by semver policy
  test "retention skips tag protected by policy even if owner-identity is set" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "retention-protected-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "semver"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:vstale#{SecureRandom.hex(27)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "v1.0.0")

    assert_no_difference -> { repo.tags.count } do
      EnforceRetentionPolicyJob.perform_now
    end
    refute TagEvent.exists?(repository: repo, tag_name: "v1.0.0", action: "delete")
  end

  # Scenario 3: retention job does NOT call authorize_for!
  # Indirect assertion: job runs without current_user (current_user = nil in job context).
  # If authorize_for! were called, it would raise Auth::Unauthenticated.
  # We assert the job completes and produces the expected TagEvent — no exception.
  test "retention job runs without current_user and produces TagEvent without raising" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "retention-noauth-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    manifest = repo.manifests.create!(
      digest: "sha256:noauth#{SecureRandom.hex(27)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2, pull_count: 0, last_pulled_at: 120.days.ago
    )
    manifest.tags.create!(repository: repo, name: "stale-tag")

    # assert_nothing_raised: if authorize_for! leaked, Auth::Unauthenticated would raise here
    assert_nothing_raised do
      assert_difference -> { TagEvent.where(actor: "retention-policy").count }, +1 do
        EnforceRetentionPolicyJob.perform_now
      end
    end

    event = TagEvent.order(:occurred_at).last
    assert_equal "retention-policy", event.actor
    assert_nil event.actor_identity_id,
               "retention events must not carry actor_identity_id (no user context)"
  end
end
```

- [ ] **Step 2: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/integration/retention_ownership_interaction_test.rb -v
```

Expected: 3 PASS — job 은 이미 `authorize_for!` 없고 `actor_identity_id` 없음.

- [ ] **Step 3: Commit**

```bash
git add test/integration/retention_ownership_interaction_test.rb
git commit -m "$(cat <<'EOF'
test(registry): retention_ownership_interaction — Critical Gap #1 (Stage 2)

3 scenarios: stale-tag deletion, semver protection skip, no-auth assertion
(indirect: authorize_for! leak would raise Auth::Unauthenticated in job context).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.8: Critical Gap #2 — `first_pusher_race` 테스트

**Files:**
- Create: `test/integration/first_pusher_race_test.rb`

**해설:** tech design §7.2 의 3 시나리오. `bearer_headers_for` 대신 `basic_auth_for` 사용. `self.use_transactional_tests = false` 로 SQLite WAL unique race 재현. teardown 에서 수동 정리. Scenario 3(non-owner push → 403) 은 non-transactional 이어야 실제 DB 상태 반영됨.

- [ ] **Step 1: 테스트 파일 작성**

Create `test/integration/first_pusher_race_test.rb`:

```ruby
require "test_helper"

class FirstPusherRaceTest < ActionDispatch::IntegrationTest
  # Disable transactional tests so concurrent threads see each other's writes.
  # Each test is responsible for manual teardown.
  self.use_transactional_tests = false

  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  # Scenario 1: concurrent first-push — exactly one owner, both 202
  test "concurrent first-push: exactly one owner" do
    repo_name = "race-repo-#{SecureRandom.hex(4)}"
    refute Repository.exists?(name: repo_name)

    tonny_hdrs = basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")
    admin_hdrs = basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")

    barrier   = Concurrent::CyclicBarrier.new(2)
    statuses  = {}
    threads   = [
      [ "tonny", tonny_hdrs ],
      [ "admin", admin_hdrs ]
    ].map do |(label, hdrs)|
      Thread.new do
        barrier.wait  # synchronize both threads to start simultaneously
        post "/v2/#{repo_name}/blobs/uploads", headers: hdrs
        statuses[label] = response.status
      end
    end
    threads.each(&:join)

    assert_equal [202, 202], statuses.values.sort, "both pushers should receive 202"
    assert_equal 1, Repository.where(name: repo_name).count,
                 "exactly one repository should be created"

    repo = Repository.find_by!(name: repo_name)
    tonny_id = identities(:tonny_google).id
    admin_id = identities(:admin_google).id
    assert_includes [ tonny_id, admin_id ], repo.owner_identity_id,
                    "owner must be one of the two racers"
  ensure
    Repository.where(name: repo_name).destroy_all if defined?(repo_name)
    BlobUpload.joins(:repository)
              .where(repositories: { name: repo_name }).destroy_all rescue nil
  end

  # Scenario 2: push to existing repo by non-member returns 403
  test "push to existing repo does NOT reassign owner_identity_id" do
    owner_identity = identities(:tonny_google)
    repo_name = "pre-existing-#{SecureRandom.hex(4)}"
    repo = Repository.create!(
      name: repo_name,
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )

    admin_hdrs = basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    post "/v2/#{repo.name}/blobs/uploads", headers: admin_hdrs

    assert_equal 403, response.status
    repo.reload
    assert_equal owner_identity.id, repo.owner_identity_id,
                 "owner_identity_id must not change"
  ensure
    Repository.where(name: repo_name).destroy_all if defined?(repo_name)
  end

  # Scenario 3: writer member can push to existing repo
  test "writer member push to existing repo returns 202" do
    owner_identity = identities(:tonny_google)
    repo_name = "member-push-#{SecureRandom.hex(4)}"
    repo = Repository.create!(
      name: repo_name,
      owner_identity: owner_identity,
      tag_protection_policy: "none"
    )
    RepositoryMember.create!(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )

    admin_hdrs = basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    post "/v2/#{repo.name}/blobs/uploads", headers: admin_hdrs

    assert_equal 202, response.status
  ensure
    RepositoryMember.where(repository: repo).destroy_all rescue nil
    Repository.where(name: repo_name).destroy_all if defined?(repo_name)
  end
end
```

- [ ] **Step 2: 테스트 실행 (Green 확인)**

```bash
bin/rails test test/integration/first_pusher_race_test.rb -v
```

Expected: 3 PASS. 레이스 시나리오는 SQLite WAL 모드에서 `RecordNotUnique` 를 재현해야 통과. 가끔 race 가 일어나지 않아도 테스트는 PASS (both 202 가 보장됨).

- [ ] **Step 3: Commit**

```bash
git add test/integration/first_pusher_race_test.rb
git commit -m "$(cat <<'EOF'
test(registry): first_pusher_race — Critical Gap #2 (Stage 2)

3 scenarios: concurrent first-push (CyclicBarrier), non-member blocked,
writer member allowed. use_transactional_tests=false for SQLite race exposure.
Uses basic_auth_for helper (not bearer_headers_for — JWT removed in D9).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.9: CI hard gate 업데이트

**Files:**
- Modify: `.github/workflows/ci.yml`

**해설:** tech design §7.4. 기존 `anonymous_pull_regression_test.rb` 에 stage 2 새 파일 2개 추가. 세 파일 모두 merge 블로커.

- [ ] **Step 1: CI 파일 확인**

```bash
cat .github/workflows/ci.yml | grep -A 10 "critical gap"
```

Stage 1 에서 추가된 critical gap 게이트 확인.

- [ ] **Step 2: CI 파일 수정**

기존 `bin/rails test ... anonymous_pull_regression_test.rb` 를 3개 파일로 확장:

```yaml
      - name: Run critical gap tests
        run: |
          bin/rails test \
            test/integration/retention_ownership_interaction_test.rb \
            test/integration/first_pusher_race_test.rb \
            test/integration/anonymous_pull_regression_test.rb
        env:
          RAILS_ENV: test
          REGISTRY_ADMIN_EMAIL: admin@timberay.com
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci(registry): add Stage 2 critical gap tests to CI hard gate

retention_ownership_interaction + first_pusher_race added alongside
existing anonymous_pull_regression. All 3 must pass before merge.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.10: PR-2 전체 테스트 통과 + 최종 확인

**Files:**
- No new files.

- [ ] **Step 1: 전체 suite 실행**

```bash
bin/rails test -v 2>&1 | tail -30
```

Expected: 전체 suite (PR-1 + PR-2 신규 포함) 0 failures.

- [ ] **Step 2: Critical gap 테스트 독립 실행 (CI 게이트 로컬 재현)**

```bash
REGISTRY_ADMIN_EMAIL=admin@timberay.com \
bin/rails test \
  test/integration/retention_ownership_interaction_test.rb \
  test/integration/first_pusher_race_test.rb \
  test/integration/anonymous_pull_regression_test.rb -v
```

Expected: 전체 PASS (총 ~14 assertions across 3 files).

- [ ] **Step 3: PR-2 브랜치 push**

```bash
git push -u origin feature/registry-auth-stage2-pr2
```

PR 생성 후 CI green 확인.

---

## Phase 3 — Staging Canary

PR-2 main 머지 후.

### Task 3.1: Staging canary 체크리스트

```
□ Stage 1 main 머지 + 3~5일 soak 확인
□ staging db:migrate STEP=3 dry-run
   - 기존 repo 개수만큼 owner = admin@timberay.com 으로 세팅 확인
   - repository_members 테이블 비어 있음 확인
   - tag_events.actor_identity_id = NULL (레거시 행)
□ staging: docker login + push → owner_identity_id 세팅 확인 (rails console)
   Repository.find_by(name: "my-image").owner_identity.email
□ staging: admin 이 아닌 유저가 tonny 소유 repo push → 403 확인
   curl -u other@timberay.com:<pat> -X POST https://<staging>/v2/<repo>/blobs/uploads
□ staging: TagsController destroy → actor_identity_id 기록 확인
□ staging: retention job manual trigger → TagEvent.actor_identity_id IS NULL 확인
□ Ownership transfer (console): repo.transfer_ownership_to!(new_identity, by: admin_user)
□ 크리티컬 갭 테스트 3건 CI GREEN
□ 배포 공지: "Stage 2 배포 순간 권한 체크 활성. 기본적으로 모든 repo 는 admin 소유."
```

### Task 3.2: Rollback 준비 (참고)

```bash
# Stage 2 PR-2 만 revert (authz 끄기 — DB 스키마 유지)
# git revert <pr2-merge-commit> --no-edit

# 권한 오검증으로 대량 차단 시:
# 1. kamal rollback (앱만, 스키마 유지)
# 2. owner/member 추가 후 재배포

# owner_identity_id 오기록 즉시 복구:
# rails console
# repo = Repository.find_by!(name: "my-image")
# correct_identity = Identity.find_by!(email: "real-owner@timberay.com")
# repo.update!(owner_identity_id: correct_identity.id)
```

---

## Stage 2 Completion Criteria

| 항목 | 검증 방법 |
|---|---|
| `repositories.owner_identity_id NOT NULL` | `bin/rails db:schema:dump \| grep owner_identity_id` |
| `repository_members` 테이블 존재 + 인덱스 | schema.rb 확인 |
| `tag_events.actor_identity_id` nullable FK | schema.rb 확인 |
| `Auth::ForbiddenAction` class 존재 + spec | `bin/rails test test/models/auth_forbidden_action_test.rb` |
| `RepositoryMember` validations | `bin/rails test test/models/repository_member_test.rb` |
| `Repository#writable_by?/deletable_by?/transfer_ownership_to!` | `bin/rails test test/models/repository_test.rb` |
| `TagEvent#belongs_to :actor_identity` + `ownership_transfer` | `bin/rails test test/models/tag_event_test.rb` |
| `RepositoryAuthorization` concern | `bin/rails test test/controllers/concerns/repository_authorization_test.rb` |
| V2 push by non-member → 403 | `bin/rails test test/controllers/v2/manifests_controller_test.rb` |
| V2 blob upload first-pusher-owner | `bin/rails test test/controllers/v2/blob_uploads_controller_test.rb` |
| V2 blob delete authz | `bin/rails test test/controllers/v2/blobs_controller_test.rb` |
| Web UI tag delete authz + actor_identity_id | `bin/rails test test/controllers/tags_controller_test.rb` |
| Web UI repo delete authz | `bin/rails test test/controllers/repositories_controller_test.rb` |
| Critical Gap #1 (retention) | `bin/rails test test/integration/retention_ownership_interaction_test.rb` |
| Critical Gap #2 (first-pusher race) | `bin/rails test test/integration/first_pusher_race_test.rb` |
| Critical Gap #3 (anonymous pull) | `bin/rails test test/integration/anonymous_pull_regression_test.rb` |
| Full suite 0 failures | `bin/rails test` |

---

## Spec Coverage Map

| Tech design 절 | 구현 task |
|---|---|
| §1.3 Stage 2 migrations (3 files) | Task 1.2 |
| §1.4 FK on_delete 정책 | Task 1.2 |
| §2.1 `Auth::ForbiddenAction` | Task 1.1 |
| §2.5 `RepositoryAuthorization` concern | Task 1.6 |
| §2.6 Repository 권한 메서드 | Task 1.4 |
| §4.5 Stage 2 `actor_identity_id` threading | Task 2.3 (manifests), 2.6 (tags) |
| §6.1 test layout — `repository_member_test.rb` | Task 1.3 |
| §6.1 test layout — `repository_authorization_test.rb` | Task 1.6 |
| §7.1 Critical Gap #1 (retention × ownership) | Task 2.7 |
| §7.2 Critical Gap #2 (first-pusher race) | Task 2.8 |
| §7.4 CI hard gate | Task 2.9 |
| §8.2 Stage 2 deploy checklist | Phase 3 Task 3.1 |
| §8.3 Stage 2 rollback | Phase 3 Task 3.2 |

---

## Execution Notes

Stage 1 plan 과 동일한 규칙 적용:

- **Tidy First**: PR-1 structural (마이그레이션 + 모델 + concern) 과 PR-2 behavioral (컨트롤러 게이트) 는 반드시 분리. 같은 PR 에 섞지 않음.
- **TDD 순서**: 각 task 는 Red → Green → Refactor → Commit 순서 준수.
- **소규모 커밋**: 테스트 통과 또는 리팩터 완료마다 즉시 커밋.
- **코드 블록은 완전**: 파일 전체 내용 제공 (diff 아님). 구현자가 grep 없이 붙여넣기 가능.
- **한국어 설명 + 영어 코드/커밋**: CLAUDE.md 규칙 준수.
- **pre-commit hook 실패 시**: 실패 원인 직접 수정 후 동일 커밋 재시도. 사용자에게 묻지 않음.
