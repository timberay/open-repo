# Registry Auth Stage 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stage 0 (OmniAuth 인프라) 를 production 에 안착시킨다. Google OAuth 1개 provider 로 Web UI 로그인 가능, `User` / `Identity` 스키마 확립, `SessionCreator` 의 Case A/B/C 동작. V2 API 경로는 본 plan 에서 건드리지 않음 (Stage 1 범위).

**Architecture:** 선행 블로커 Phase A — 기존 RSpec 35개 spec 을 Minitest 로 포팅 후 `rspec-rails` 제거. 그 후 Phase B — `omniauth` + `omniauth-google-oauth2` gem 도입, 스키마 3개 마이그레이션 (`users`, `identities`, FK 순환 해결), `Auth::ProviderProfile`/`Auth::GoogleAdapter`/`SessionCreator` 서비스, `Auth::LoginTracker` concern, `/auth/google_oauth2/callback` 콜백 컨트롤러, Web UI 로그인 버튼. 3 PR 분할: PR-1 structural (schema+models), PR-2 behavioral (auth services), PR-3 behavioral (controller+routes+UI).

**Tech Stack:** Rails 8.1, Minitest, SQLite, OmniAuth 2.x, omniauth-google-oauth2, omniauth-rails_csrf_protection, rack-attack, ViewComponent, Tailwind.

**Source spec:** `docs/superpowers/specs/2026-04-23-registry-auth-tech-design.md` §1.1, §2.1–§2.3, §5.2 (Google OAuth), §8.2 Stage 0 체크리스트.

**Branching strategy:**
- `chore/rspec-to-minitest` — Phase A 의 모든 커밋. main 직접 머지.
- `feature/registry-auth-stage0` — Phase B 의 모든 커밋. Phase A 머지 후 분기.

---

## Phase A — Blocker A: RSpec → Minitest 포팅

### Scope

35 spec files + `spec/rails_helper.rb` + `spec/spec_helper.rb` + `Gemfile` 의 `rspec-rails` gem + `Gemfile.lock` + `.github/workflows/ci.yml` (CI test command) + `CLAUDE.md`/`docs/standards/QUALITY.md` 의 RSpec 언급 정리.

### Porting 원칙 (canonical 패턴)

RSpec → Minitest 전환 패턴. 아래 패턴으로 모든 spec 파일을 포팅:

**a. 모델/서비스 spec → `test/models/` or `test/services/` 로 이동**

RSpec:
```ruby
# spec/models/example_spec.rb
require "rails_helper"

RSpec.describe Example, type: :model do
  describe "#method" do
    let(:subject) { Example.new(attr: value) }

    it "does X" do
      expect(subject.method).to eq(expected)
    end

    context "when Y" do
      before { subject.update!(other: z) }
      it "changes to Z" do
        expect(subject.method).to eq(other_expected)
      end
    end
  end
end
```

Minitest:
```ruby
# test/models/example_test.rb
require "test_helper"

class ExampleTest < ActiveSupport::TestCase
  def setup
    @example = Example.new(attr: value)
  end

  test "#method does X" do
    assert_equal expected, @example.method
  end

  test "#method when Y changes to Z" do
    @example.update!(other: z)
    assert_equal other_expected, @example.method
  end
end
```

**b. RSpec matcher → Minitest assertion 매핑**
- `expect(x).to eq(y)` → `assert_equal y, x`
- `expect(x).to be y` → `assert_same y, x`
- `expect(x).to be_truthy` → `assert x`
- `expect(x).to be_falsey` → `refute x` / `assert_nil x`
- `expect(x).to be_nil` → `assert_nil x`
- `expect(x).to be_present` → `assert x.present?`
- `expect { code }.to raise_error(Klass)` → `assert_raises(Klass) { code }`
- `expect { code }.to change(Model, :count).by(n)` → `assert_difference -> { Model.count }, n do; code; end`
- `expect { code }.not_to change(Model, :count)` → `assert_no_difference -> { Model.count } do; code; end`
- `expect(x).to match(regex)` → `assert_match regex, x`
- `expect(array).to include(item)` → `assert_includes array, item`
- `expect(x).to be_a(Class)` → `assert_kind_of Class, x`

**c. `let` / `subject` → `setup` + instance variables**
- `let(:x) { expr }` → `def x; @x ||= expr; end` (or eager `@x = expr` in `setup`)
- `subject { ... }` → 위와 동일하게 인스턴스 변수

**d. `describe` / `context` 블록 → test 이름 조합**
- 중첩된 `describe "#method" do context "when X" do it "does Y"` → `test "#method when X does Y" do`

**e. Request spec → `test/controllers/` or `test/integration/`**
- `spec/requests/` 는 보통 `ActionDispatch::IntegrationTest` 로 이동
- `get "/path", params: {}, headers: {}` 구문은 동일
- RSpec `expect(response).to have_http_status(:ok)` → `assert_response :ok`

**f. ViewComponent spec → `test/components/`**
- RSpec + `ViewComponent::TestHelpers` → Minitest + `ViewComponent::TestCase`
- `render_inline(Component.new(...))` 동일
- `expect(page).to have_css(...)` → `assert_selector ...` 또는 `assert page.has_css?(...)`

### Task A.0: 기존 테스트 그린 확인 (baseline)

**Files:**
- Read: `Gemfile`, `.github/workflows/ci.yml`

- [ ] **Step 1: baseline 테스트 실행 — 모두 green 이어야 시작 가능**

Run: `bundle exec rspec`
Expected: PASS (모든 기존 spec 통과). 실패하는 spec 이 있으면 먼저 고친 다음 포팅 착수.

- [ ] **Step 2: 현재 branch 가 main 에서 clean 상태인지 확인**

Run: `git status && git diff --stat main`
Expected: `nothing to commit, working tree clean`

- [ ] **Step 3: Phase A 브랜치 생성**

Run: `git checkout -b chore/rspec-to-minitest`

### Task A.1: `test/test_helper.rb` 작성 (기존 spec_helper + rails_helper 통합)

**Files:**
- Create: `test/test_helper.rb`
- Read: `spec/spec_helper.rb`, `spec/rails_helper.rb` (기존 설정 인수인계)

- [ ] **Step 1: `test/test_helper.rb` 전체 내용 작성**

Write the file with:

```ruby
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Disable external HTTP calls by default
WebMock.disable_net_connect!(allow_localhost: true)

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  fixtures :all
end
```

- [ ] **Step 2: file_fixture 경로 확인용 fixtures dir 생성**

Run: `mkdir -p test/fixtures/files`

- [ ] **Step 3: 단독 실행 가능한지 확인**

Run: `bin/rails test -h`
Expected: usage 표시, 에러 없음.

- [ ] **Step 4: Commit (structural)**

```bash
git add test/test_helper.rb test/fixtures/files/.keep
touch test/fixtures/files/.keep
git add test/fixtures/files/.keep
git commit -m "test: scaffold test_helper.rb for Minitest migration"
```

### Task A.2: 기존 spec fixtures 이동 (`spec/fixtures` → `test/fixtures`)

**Files:**
- Check: `spec/fixtures/` (존재하면 이동 대상)

- [ ] **Step 1: spec/fixtures 존재 확인**

Run: `ls spec/fixtures 2>/dev/null && echo 'exists' || echo 'absent'`

- [ ] **Step 2: 존재하면 `git mv` 로 이동; 없으면 skip**

If exists:
```bash
git mv spec/fixtures/*.yml test/fixtures/ 2>/dev/null || true
git mv spec/fixtures/files/* test/fixtures/files/ 2>/dev/null || true
```

- [ ] **Step 3: Commit (structural, no behavior)**

```bash
git status
git diff --stat --cached
git commit -m "test: relocate fixtures from spec/ to test/"
```
(변경이 없으면 이 커밋은 skip)

### Task A.3: 모델 spec 포팅 (8 files)

**Files:**
- Create: `test/models/{blob,blob_upload,layer,manifest,pull_event,repository,tag_event,tag}_test.rb`
- Delete: `spec/models/*_spec.rb` (파일 단위로 포팅 1개씩 검증 후 삭제)

- [ ] **Step 1: 1개 파일 canonical 포팅 (예: `repository_spec.rb` → `repository_test.rb`)**

Read `spec/models/repository_spec.rb` 전체. 위 "Porting 원칙" a/b/c/d 에 따라 `test/models/repository_test.rb` 로 변환. 모든 `describe`/`context` 를 test 이름에 포함.

- [ ] **Step 2: 포팅한 1개 파일만 실행 검증**

Run: `bin/rails test test/models/repository_test.rb -v`
Expected: PASS (모든 테스트 RSpec 때와 동일한 내용).

- [ ] **Step 3: 원본 spec 파일 삭제**

Run: `rm spec/models/repository_spec.rb`

- [ ] **Step 4: Commit**

```bash
git add test/models/repository_test.rb spec/models/repository_spec.rb
git commit -m "test: port repository_spec.rb to Minitest"
```

- [ ] **Step 5: 나머지 7 개 모델 spec 반복**

`spec/models/` 의 blob, blob_upload, layer, manifest, pull_event, tag_event, tag 각각에 대해 Step 1–4 반복. 각 파일 1 커밋.

- [ ] **Step 6: 모든 모델 테스트 통합 실행**

Run: `bin/rails test test/models/`
Expected: 모든 테스트 PASS.

- [ ] **Step 7: spec/models 디렉터리 제거 확인**

Run: `ls spec/models 2>/dev/null && echo 'leftover' || echo 'empty'`
Expected: `empty`

### Task A.4: 서비스 spec 포팅 (6 files)

**Files:**
- Create: `test/services/{blob_store,dependency_analyzer,digest_calculator,image_import_service,manifest_processor,tag_diff_service}_test.rb`
- Delete: `spec/services/*_spec.rb`

- [ ] **Step 1: 6개 spec 을 각각 포팅 + 실행 + 커밋 (Task A.3 패턴 반복)**

서비스 spec 은 대개 model-like TDD 라서 동일 패턴.

Run (final): `bin/rails test test/services/`
Expected: PASS.

Commits: `test: port <name>_spec.rb to Minitest` × 6.

### Task A.5: Job spec 포팅 (2 files)

**Files:**
- Create: `test/jobs/{cleanup_orphaned_blobs_job,enforce_retention_policy_job}_test.rb`
- Delete: `spec/jobs/*_spec.rb`

- [ ] **Step 1: 2개 spec 포팅. Job 테스트는 `ActiveJob::TestHelper` 사용**

각 파일 클래스를 `class ... < ActiveJob::TestCase` 로. `perform_now` 호출 방식 그대로.

Run: `bin/rails test test/jobs/`
Expected: PASS.

Commits: 2 개.

### Task A.6: 에러 + 헬퍼 spec 포팅 (2 files)

**Files:**
- Create: `test/errors/registry_test.rb`, `test/helpers/repositories_helper_test.rb`
- Delete: `spec/errors/registry_spec.rb`, `spec/helpers/repositories_helper_spec.rb`

- [ ] **Step 1: 2개 spec 포팅**

Helper test class: `class RepositoriesHelperTest < ActionView::TestCase`.
Error test class: `class RegistryErrorsTest < ActiveSupport::TestCase`.

Run: `bin/rails test test/errors test/helpers`
Expected: PASS.

Commits: 2 개.

### Task A.7: Request spec → `test/controllers/` 포팅 (7 files)

**Files:**
- Create: `test/controllers/{repositories,tags}_controller_test.rb`,
  `test/controllers/v2/{base,blob_uploads,blobs,catalog,manifests,tags}_controller_test.rb`
- Delete: `spec/requests/*_spec.rb` (including `spec/requests/v2/*_spec.rb`)

- [ ] **Step 1: request spec 을 integration test 로 변환**

RSpec `spec/requests/repositories_spec.rb` 내용 → Minitest `test/controllers/repositories_controller_test.rb` 의 `class ... < ActionDispatch::IntegrationTest`.

get/post/etc HTTP verb 호출 구문은 동일. `expect(response).to have_http_status(:ok)` → `assert_response :ok`.

7개 각각 포팅 + 실행 + 커밋.

Run (final): `bin/rails test test/controllers/`
Expected: PASS.

Commits: 7 개 (`test: port requests/<name>_spec.rb to Minitest`).

### Task A.8: ViewComponent spec 포팅 (7 files)

**Files:**
- Create: `test/components/{badge,button,card,digest,input,select,textarea}_component_test.rb`
- Delete: `spec/components/*_spec.rb`

- [ ] **Step 1: 포팅 — `class ... < ViewComponent::TestCase`**

```ruby
# test/components/badge_component_test.rb
require "test_helper"
require "view_component/test_case"

class BadgeComponentTest < ViewComponent::TestCase
  test "renders with default variant" do
    render_inline(BadgeComponent.new(text: "hello"))
    assert_selector "span", text: "hello"
  end
end
```

Capybara matchers (`assert_selector`, `page.has_css?`) 는 `ViewComponent::TestCase` 가 활성화해줌. 7개 각각 포팅.

Run: `bin/rails test test/components/`
Expected: PASS.

Commits: 7 개.

### Task A.9: View spec 포팅 (1 file)

**Files:**
- Create: `test/views/repositories/index_test.rb` (또는 system test 로 승격)
- Delete: `spec/views/repositories/index.html.tailwindcss_spec.rb`

- [ ] **Step 1: View spec 포팅 여부 판단**

View spec 이 단순 rendering smoke 이면 integration test 로 흡수. 복잡한 경우만 `test/views/` 유지.

```ruby
# test/views/repositories/index_test.rb (최소한)
require "test_helper"

class Repositories::IndexViewTest < ActionView::TestCase
  test "renders repository cards" do
    @repositories = [repositories(:one)]
    render template: "repositories/index"
    assert_select "div.repository-card", count: 1
  end
end
```

Run: `bin/rails test test/views/`
Expected: PASS.

Commit: 1 개.

### Task A.10: `rspec-rails` + 관련 gem 제거

**Files:**
- Modify: `Gemfile` (line 59 `gem "rspec-rails"` 제거)
- Modify: `Gemfile.lock` (bundle install 로 갱신)
- Delete: `spec/rails_helper.rb`, `spec/spec_helper.rb`, `spec/` 디렉터리 전체

- [ ] **Step 1: `Gemfile` 에서 rspec-rails 라인 제거**

Edit `Gemfile`: line 59 `gem "rspec-rails"` 삭제. `webmock` 라인은 유지 (Minitest 도 사용).

- [ ] **Step 2: `bundle install` 실행하여 Gemfile.lock 갱신**

Run: `bundle install`
Expected: rspec gem 5종 (rspec-core, rspec-expectations, rspec-mocks, rspec-rails, rspec-support) 제거.

- [ ] **Step 3: `spec/` 디렉터리 전체 삭제**

Run: `rm -rf spec/`

- [ ] **Step 4: 전체 테스트 실행하여 모든 것이 여전히 green 인지 확인**

Run: `bin/rails test`
Expected: 전 테스트 PASS, 개수가 원래 rspec 테스트 개수와 근사해야 함.

- [ ] **Step 5: `.rspec` 파일이 있으면 삭제**

Run: `rm -f .rspec`

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock
git add -A spec/ .rspec
git commit -m "chore: remove rspec-rails, spec/ directory now migrated"
```

### Task A.11: CI workflow 업데이트

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: 기존 CI 파일 내용 확인**

Run: `cat .github/workflows/ci.yml`

- [ ] **Step 2: 테스트 실행 커맨드 변경**

`bundle exec rspec` 또는 `bin/rspec` 등이 있으면 `bin/rails test` (and `bin/rails test:system` if system tests exist) 로 교체. 다른 job step (brakeman, rubocop, bundler-audit) 은 그대로 유지.

- [ ] **Step 3: 로컬에서 CI 동일 환경으로 테스트 1회 실행**

Run: `RAILS_ENV=test bin/rails db:test:prepare && bin/rails test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: switch test runner from rspec to bin/rails test"
```

### Task A.12: 문서 업데이트

**Files:**
- Modify: `CLAUDE.md` (RSpec 언급 제거), `docs/standards/QUALITY.md` (이미 Minitest 명시이나 혹시 RSpec 잔재 확인)

- [ ] **Step 1: grep 으로 RSpec 언급 찾기**

Run: `grep -rn "RSpec\|rspec" CLAUDE.md docs/ README.md 2>&1 | grep -v "not.*Minitest"`

- [ ] **Step 2: 발견된 곳 정리**

각 매치를 Minitest 로 교체하거나, "RSpec 에서 Minitest 로 이관 완료" 수준의 역사 기록으로 남김.

- [ ] **Step 3: TODOS.md 에서 [P0] Migrate RSpec specs to Minitest 항목 제거**

Edit `TODOS.md`: 해당 섹션 전체 삭제.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/standards/QUALITY.md TODOS.md README.md
git commit -m "docs: remove RSpec references, close [P0] RSpec migration TODO"
```

### Task A.13: Phase A 마감 — main 에 머지

**Files:**
- `chore/rspec-to-minitest` 브랜치 머지

- [ ] **Step 1: 전체 green 상태 최종 확인**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager`
Expected: 모두 PASS.

- [ ] **Step 2: push + PR 생성**

```bash
git push -u origin chore/rspec-to-minitest
```

Create PR via `gh pr create` with body 요약 (35 files 포팅 완료, gem 제거, CI 전환).

- [ ] **Step 3: main 머지 후 local main 업데이트**

```bash
git checkout main
git pull origin main
git branch -d chore/rspec-to-minitest
```

**Phase A 완료**. Phase B 착수 조건 충족.

---

## Phase B — Stage 0: OmniAuth 인프라

### PR-1 — Structural: Schema + 모델 (no user-facing behavior)

`feature/registry-auth-stage0` 브랜치의 첫 PR. 사용자 경험상 아무 변화 없음. 순수 스키마 + 모델 validation + concern.

### Task B.1: Feature 브랜치 생성

- [ ] **Step 1: main 최신 상태에서 브랜치 분기**

Run: `git checkout main && git pull && git checkout -b feature/registry-auth-stage0`

### Task B.2: Users 마이그레이션 + 기본 모델 (FK 는 추후 Task B.4)

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_users.rb` (timestamp = `rails g migration` 이 생성)
- Create: `app/models/user.rb`
- Create: `test/models/user_test.rb`
- Create: `test/fixtures/users.yml`

- [ ] **Step 1: 먼저 `User` 모델 존재 확인용 failing test 작성**

Write `test/models/user_test.rb`:

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin fixture has admin=true" do
    assert users(:admin).admin?
  end

  test "non-admin fixture has admin=false" do
    refute users(:tonny).admin?
  end

  test "email must be present" do
    u = User.new(admin: false)
    refute u.valid?
    assert_includes u.errors[:email], "can't be blank"
  end

  test "email must be unique" do
    User.create!(email: "dupe@x.com", admin: false)
    dup = User.new(email: "dupe@x.com", admin: false)
    refute dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end
end
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: FAIL. `uninitialized constant User` 또는 `table "users" does not exist`.

- [ ] **Step 3: 마이그레이션 생성**

Run: `bin/rails g migration CreateUsers`

Edit the generated file (path: `db/migrate/*_create_users.rb`):

```ruby
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :email,       null: false
      t.boolean  :admin,       null: false, default: false
      t.bigint   :primary_identity_id  # FK added after identities table exists
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
```

- [ ] **Step 4: 마이그레이션 실행**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: 마이그레이션 completed, `db/schema.rb` 에 `users` 테이블 추가됨.

- [ ] **Step 5: User 모델 작성**

Write `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
end
```

- [ ] **Step 6: Fixtures 작성**

Write `test/fixtures/users.yml`:

```yaml
admin:
  email: admin@timberay.com
  admin: true
  last_seen_at: <%= 1.minute.ago %>
  created_at: <%= 2.days.ago %>
  updated_at: <%= 1.minute.ago %>

tonny:
  email: tonny@timberay.com
  admin: false
  last_seen_at: <%= 5.minutes.ago %>
  created_at: <%= 1.day.ago %>
  updated_at: <%= 5.minutes.ago %>
```

- [ ] **Step 7: 테스트 실행 — 통과 확인**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: PASS (4 assertions).

- [ ] **Step 8: Commit (structural)**

```bash
git add db/migrate/*_create_users.rb db/schema.rb app/models/user.rb test/models/user_test.rb test/fixtures/users.yml
git commit -m "feat(auth): add users table and minimal User model"
```

### Task B.3: Identities 마이그레이션 + 모델

**Files:**
- Create: `db/migrate/*_create_identities.rb`
- Create: `app/models/identity.rb`
- Create: `test/models/identity_test.rb`
- Create: `test/fixtures/identities.yml`

- [ ] **Step 1: Failing test**

Write `test/models/identity_test.rb`:

```ruby
require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "belongs to user" do
    assert_instance_of User, identities(:tonny_google).user
  end

  test "provider and uid pair must be unique" do
    identity = Identity.new(
      user: users(:admin),
      provider: "google_oauth2",
      uid: identities(:tonny_google).uid,
      email: "x@y.z"
    )
    refute identity.valid?
  end

  test "presence validations" do
    i = Identity.new
    refute i.valid?
    %w[provider uid email].each { |f| assert_includes i.errors.attribute_names, f.to_sym }
  end

  test "email_verified is tri-state (nil allowed)" do
    i = Identity.new(
      user: users(:admin),
      provider: "google_oauth2",
      uid: "xxx",
      email: "x@y.z",
      email_verified: nil
    )
    assert i.valid?
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/models/identity_test.rb -v`
Expected: FAIL (`Identity` undefined / `identities` fixture undefined).

- [ ] **Step 3: Generate migration**

Run: `bin/rails g migration CreateIdentities`

Edit:

```ruby
class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.string   :provider,       null: false
      t.string   :uid,            null: false
      t.string   :email,          null: false
      t.boolean  :email_verified
      t.string   :name
      t.string   :avatar_url
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :identities, [:provider, :uid], unique: true
  end
end
```

- [ ] **Step 4: Run migration**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`
Expected: `identities` table 생성.

- [ ] **Step 5: Identity 모델 작성**

Write `app/models/identity.rb`:

```ruby
class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true
  validates :uid,      presence: true
  validates :email,    presence: true
  validates :uid, uniqueness: { scope: :provider }
end
```

- [ ] **Step 6: User 모델에 has_many 추가**

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_many :identities, dependent: :destroy

  validates :email, presence: true, uniqueness: true
end
```

- [ ] **Step 7: Fixtures 작성**

Write `test/fixtures/identities.yml`:

```yaml
admin_google:
  user: admin
  provider: google_oauth2
  uid: "admin-google-1"
  email: admin@timberay.com
  email_verified: true
  name: Admin User
  last_login_at: <%= 1.minute.ago %>
  created_at: <%= 2.days.ago %>
  updated_at: <%= 1.minute.ago %>

tonny_google:
  user: tonny
  provider: google_oauth2
  uid: "tonny-google-1"
  email: tonny@timberay.com
  email_verified: true
  name: Tonny Kim
  last_login_at: <%= 5.minutes.ago %>
  created_at: <%= 1.day.ago %>
  updated_at: <%= 5.minutes.ago %>
```

- [ ] **Step 8: Run — expect PASS**

Run: `bin/rails test test/models/identity_test.rb -v`
Expected: PASS (4+ assertions).

- [ ] **Step 9: 기존 User test 도 여전히 green 확인**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add db/migrate/*_create_identities.rb db/schema.rb app/models/identity.rb app/models/user.rb test/models/identity_test.rb test/fixtures/identities.yml
git commit -m "feat(auth): add identities table and Identity model"
```

### Task B.4: `users.primary_identity_id` FK 추가 + belongs_to

**Files:**
- Create: `db/migrate/*_add_primary_identity_fk_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`
- Modify: `test/fixtures/users.yml`

- [ ] **Step 1: Failing test — User#primary_identity 가 있어야 함**

Edit `test/models/user_test.rb` — add:

```ruby
test "primary_identity returns the associated identity" do
  assert_equal identities(:tonny_google), users(:tonny).primary_identity
end

test "primary_identity_id foreign key on_delete: restrict" do
  u = users(:tonny)
  i = u.primary_identity
  assert_raises ActiveRecord::InvalidForeignKey do
    i.destroy!
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: FAIL (primary_identity method undefined).

- [ ] **Step 3: Generate migration**

Run: `bin/rails g migration AddPrimaryIdentityFkToUsers`

Edit:

```ruby
class AddPrimaryIdentityFkToUsers < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :users, :identities, column: :primary_identity_id, on_delete: :restrict
    add_index :users, :primary_identity_id
  end
end
```

- [ ] **Step 4: Run migration**

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 5: User 모델 업데이트**

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_many :identities, dependent: :destroy
  belongs_to :primary_identity, class_name: "Identity", optional: true

  validates :email, presence: true, uniqueness: true
end
```

`optional: true` 이유: DB 레벨 NULLABLE 이라서 — 신규 유저 생성 후 첫 identity 가 아직 연결 안 된 단일 트랜잭션 내부 ~1ms 상태 허용.

- [ ] **Step 6: Fixtures 에 primary_identity 컬럼 추가**

Edit `test/fixtures/users.yml` — add `primary_identity:` 필드:

```yaml
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
```

- [ ] **Step 7: Run test — expect PASS**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: PASS. (FK restrict 테스트가 `ActiveRecord::InvalidForeignKey` 발생 확인.)

- [ ] **Step 8: Commit**

```bash
git add db/migrate/*_add_primary_identity_fk_to_users.rb db/schema.rb app/models/user.rb test/models/user_test.rb test/fixtures/users.yml
git commit -m "feat(auth): add users.primary_identity_id FK and belongs_to"
```

### Task B.5: `Auth::LoginTracker` concern 작성

**Files:**
- Create: `app/models/concerns/auth/login_tracker.rb`
- Modify: `app/models/user.rb`
- Create: `test/models/concerns/auth/login_tracker_test.rb`

- [ ] **Step 1: Failing test**

Write `test/models/concerns/auth/login_tracker_test.rb`:

```ruby
require "test_helper"

class Auth::LoginTrackerTest < ActiveSupport::TestCase
  test "track_login! sets primary_identity_id and last_seen_at and identity.last_login_at" do
    user = users(:tonny)
    other_identity = user.identities.create!(
      provider: "google_oauth2",
      uid: "second-google",
      email: user.email
    )

    freeze_time = Time.current
    Time.stub :current, freeze_time do
      user.track_login!(other_identity)
    end

    user.reload
    other_identity.reload
    assert_equal other_identity.id, user.primary_identity_id
    assert_in_delta freeze_time, user.last_seen_at, 1.second
    assert_in_delta freeze_time, other_identity.last_login_at, 1.second
  end

  test "track_login! is atomic — rollback on identity save failure" do
    user = users(:tonny)
    original_primary = user.primary_identity_id

    bad_identity = Identity.new  # unsaved, validations will fail
    assert_raises(ActiveRecord::RecordInvalid) do
      user.track_login!(bad_identity)
    end

    user.reload
    assert_equal original_primary, user.primary_identity_id
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/models/concerns/auth/login_tracker_test.rb -v`
Expected: FAIL (`track_login!` undefined).

- [ ] **Step 3: Write concern**

Write `app/models/concerns/auth/login_tracker.rb`:

```ruby
module Auth
  module LoginTracker
    extend ActiveSupport::Concern

    # Called from SessionCreator after resolving Case A/B/C.
    # Single transaction: identity.last_login_at + user.primary_identity_id + user.last_seen_at.
    def track_login!(identity)
      transaction do
        identity.update!(last_login_at: Time.current)
        update!(primary_identity_id: identity.id, last_seen_at: Time.current)
      end
      self
    end
  end
end
```

- [ ] **Step 4: Include in User**

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  include Auth::LoginTracker

  has_many :identities, dependent: :destroy
  belongs_to :primary_identity, class_name: "Identity", optional: true

  validates :email, presence: true, uniqueness: true
end
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rails test test/models/concerns/auth/login_tracker_test.rb test/models/user_test.rb -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/concerns/auth/login_tracker.rb app/models/user.rb test/models/concerns/auth/login_tracker_test.rb
git commit -m "feat(auth): add Auth::LoginTracker concern for User"
```

### Task B.6: `REGISTRY_ADMIN_EMAIL` 부트스트랩 헬퍼 (User.admin?)

**Files:**
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1: Failing test — User 생성 시 admin_email 일치하면 admin=true**

Edit `test/models/user_test.rb` — add:

```ruby
test "User.admin_email? returns true for REGISTRY_ADMIN_EMAIL" do
  Rails.configuration.x.registry.admin_email = "admin@timberay.com"
  assert User.admin_email?("admin@timberay.com")
  refute User.admin_email?("someone-else@timberay.com")
end

test "User.admin_email? returns false when admin_email unset" do
  Rails.configuration.x.registry.admin_email = nil
  refute User.admin_email?("admin@timberay.com")
end
```

- [ ] **Step 2: 설정 placeholder 작성 — `config/initializers/registry.rb` 확장**

기존 initializer 없으면 최소한으로 추가 (Stage 1 에서 확장). Write or update `config/initializers/registry.rb`:

```ruby
Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
end
```

- [ ] **Step 3: Run — expect FAIL**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: FAIL (`admin_email?` undefined).

- [ ] **Step 4: Implement**

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  include Auth::LoginTracker

  has_many :identities, dependent: :destroy
  belongs_to :primary_identity, class_name: "Identity", optional: true

  validates :email, presence: true, uniqueness: true

  def self.admin_email?(email)
    configured = Rails.configuration.x.registry.admin_email
    return false if configured.blank?
    configured.to_s.casecmp(email.to_s).zero?
  end
end
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb config/initializers/registry.rb
git commit -m "feat(auth): User.admin_email? helper reads REGISTRY_ADMIN_EMAIL"
```

### Task B.7: PR-1 push + PR 생성

- [ ] **Step 1: 최종 전체 테스트**

Run: `bin/rails test`
Expected: PASS. 새 테스트 수가 증가했음을 확인.

- [ ] **Step 2: rubocop + brakeman green 확인**

Run: `bin/rubocop && bin/brakeman --no-pager`
Expected: PASS.

- [ ] **Step 3: Push + PR**

```bash
git push -u origin feature/registry-auth-stage0
gh pr create --base main --title "feat(auth): Stage 0 PR-1 schema and models" --body "$(cat <<'EOF'
## Summary
- `users` + `identities` 스키마 신설 (3 마이그레이션)
- `User` (with `Auth::LoginTracker` concern) + `Identity` 모델
- `User.admin_email?` bootstrap helper + `config.x.registry.admin_email`

## Test plan
- [x] `bin/rails test` — 모든 기존 + 신규 테스트 PASS
- [x] `bin/rubocop` + `bin/brakeman` green

Phase B Stage 0 plan 의 PR-1 (structural). PR-2 는 services, PR-3 는 controller+UI.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: 머지 대기 후 로컬 브랜치 유지**

PR-1 머지 전에 PR-2/PR-3 도 쌓을 수 있음. 실제 merge 순서는 stack 형태 유지.

### PR-2 — Behavioral: OmniAuth gem 도입 + Auth 서비스 계층

### Task B.8: Gem 추가 + bundle install

**Files:**
- Modify: `Gemfile`
- Modify: `Gemfile.lock`

- [ ] **Step 1: Gemfile 에 gem 추가**

Edit `Gemfile` — add to the main section (after `bcrypt` 라인):

```ruby
gem "omniauth", "~> 2.1"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "jwt"
gem "rack-attack"
```

- [ ] **Step 2: bundle install**

Run: `bundle install`
Expected: 신규 5 gem + 의존성 설치.

- [ ] **Step 3: 테스트 전체 여전히 green 확인**

Run: `bin/rails test`
Expected: PASS (gem 추가만으로는 아무것도 변경되지 않음).

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add omniauth, jwt, rack-attack gems"
```

### Task B.9: Auth 에러 계층 작성

**Files:**
- Create: `app/errors/auth.rb`
- Create: `test/errors/auth_test.rb`

- [ ] **Step 1: Failing test**

Write `test/errors/auth_test.rb`:

```ruby
require "test_helper"

class AuthErrorsTest < ActiveSupport::TestCase
  test "Auth::Error is the root" do
    assert_kind_of StandardError, Auth::Error.new
  end

  test "Stage 0 error classes inherit from Auth::Error" do
    [Auth::InvalidProfile, Auth::EmailMismatch, Auth::ProviderOutage].each do |k|
      assert k.ancestors.include?(Auth::Error), "#{k} must inherit Auth::Error"
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/errors/auth_test.rb -v`
Expected: FAIL (`Auth` namespace undefined).

- [ ] **Step 3: Write `app/errors/auth.rb`**

```ruby
module Auth
  class Error < StandardError; end

  # Stage 0: OAuth callback flow
  class InvalidProfile < Error; end
  class EmailMismatch  < Error; end
  class ProviderOutage < Error; end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/errors/auth_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/errors/auth.rb test/errors/auth_test.rb
git commit -m "feat(auth): add Auth::Error hierarchy for Stage 0"
```

### Task B.10: `Auth::ProviderProfile` VO

**Files:**
- Create: `app/services/auth/provider_profile.rb`
- Create: `test/services/auth/provider_profile_test.rb`

- [ ] **Step 1: Failing test**

Write `test/services/auth/provider_profile_test.rb`:

```ruby
require "test_helper"

class Auth::ProviderProfileTest < ActiveSupport::TestCase
  test "stores provider, uid, email, email_verified, name, avatar_url" do
    p = Auth::ProviderProfile.new(
      provider: "google_oauth2",
      uid: "xxx",
      email: "a@b.c",
      email_verified: true,
      name: "A",
      avatar_url: nil
    )
    assert_equal "google_oauth2", p.provider
    assert_equal "a@b.c", p.email
    assert_nil p.avatar_url
  end

  test "is frozen (Data)" do
    p = Auth::ProviderProfile.new(
      provider: "x", uid: "y", email: "z@w", email_verified: nil, name: nil, avatar_url: nil
    )
    assert p.frozen?
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/services/auth/provider_profile_test.rb -v`

- [ ] **Step 3: Write**

```ruby
# app/services/auth/provider_profile.rb
module Auth
  # Value object — normalized OAuth profile across providers.
  ProviderProfile = Data.define(:provider, :uid, :email, :email_verified, :name, :avatar_url)
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/services/auth/provider_profile_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/auth/provider_profile.rb test/services/auth/provider_profile_test.rb
git commit -m "feat(auth): add Auth::ProviderProfile value object"
```

### Task B.11: `Auth::GoogleAdapter#to_profile`

**Files:**
- Create: `app/services/auth/google_adapter.rb`
- Create: `test/services/auth/google_adapter_test.rb`

- [ ] **Step 1: Failing test**

Write `test/services/auth/google_adapter_test.rb`:

```ruby
require "test_helper"

class Auth::GoogleAdapterTest < ActiveSupport::TestCase
  def valid_auth_hash
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-123",
      info: { email: "tonny@timberay.com", name: "Tonny Kim", image: "https://lh3.example/pic.jpg" },
      extra: { raw_info: { email_verified: true } }
    )
  end

  test "returns ProviderProfile from valid auth_hash" do
    profile = Auth::GoogleAdapter.new.to_profile(valid_auth_hash)
    assert_instance_of Auth::ProviderProfile, profile
    assert_equal "google_oauth2", profile.provider
    assert_equal "google-uid-123", profile.uid
    assert_equal "tonny@timberay.com", profile.email
    assert_equal true, profile.email_verified
    assert_equal "Tonny Kim", profile.name
    assert_equal "https://lh3.example/pic.jpg", profile.avatar_url
  end

  test "raises Auth::InvalidProfile when email is blank" do
    h = valid_auth_hash
    h.info.email = ""
    assert_raises(Auth::InvalidProfile) { Auth::GoogleAdapter.new.to_profile(h) }
  end

  test "raises Auth::InvalidProfile when uid is blank" do
    h = valid_auth_hash
    h.uid = ""
    assert_raises(Auth::InvalidProfile) { Auth::GoogleAdapter.new.to_profile(h) }
  end

  test "email_verified defaults to nil when provider doesn't report" do
    h = valid_auth_hash
    h.extra.raw_info = {}
    profile = Auth::GoogleAdapter.new.to_profile(h)
    assert_nil profile.email_verified
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/services/auth/google_adapter_test.rb -v`

- [ ] **Step 3: Write**

```ruby
# app/services/auth/google_adapter.rb
module Auth
  class GoogleAdapter
    # @param auth_hash [OmniAuth::AuthHash]
    # @return [Auth::ProviderProfile]
    # @raise [Auth::InvalidProfile]
    def to_profile(auth_hash)
      uid = auth_hash.uid.to_s
      email = auth_hash.info&.email.to_s

      raise Auth::InvalidProfile, "missing uid"   if uid.blank?
      raise Auth::InvalidProfile, "missing email" if email.blank?

      verified_raw = auth_hash.dig("extra", "raw_info", "email_verified") ||
                     auth_hash.dig(:extra, :raw_info, :email_verified)
      email_verified =
        case verified_raw
        when true, "true"   then true
        when false, "false" then false
        else nil
        end

      ProviderProfile.new(
        provider: auth_hash.provider,
        uid: uid,
        email: email.downcase,
        email_verified: email_verified,
        name: auth_hash.info&.name,
        avatar_url: auth_hash.info&.image
      )
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/services/auth/google_adapter_test.rb -v`
Expected: PASS (4 assertions).

- [ ] **Step 5: Commit**

```bash
git add app/services/auth/google_adapter.rb test/services/auth/google_adapter_test.rb
git commit -m "feat(auth): add Auth::GoogleAdapter#to_profile"
```

### Task B.12: `SessionCreator` — Case A (existing identity)

**Files:**
- Create: `app/services/session_creator.rb`
- Create: `test/services/session_creator_test.rb`

- [ ] **Step 1: Failing test — Case A 만**

Write `test/services/session_creator_test.rb`:

```ruby
require "test_helper"

class SessionCreatorTest < ActiveSupport::TestCase
  def profile_for(identity:, overrides: {})
    Auth::ProviderProfile.new(
      provider: identity.provider,
      uid: identity.uid,
      email: identity.email,
      email_verified: true,
      name: identity.name || "Test",
      avatar_url: nil,
      **overrides
    )
  end

  test "Case A — existing (provider, uid) → returns existing user, updates last_login_at" do
    existing = identities(:tonny_google)
    profile = profile_for(identity: existing)

    user = SessionCreator.new.call(profile)

    assert_equal existing.user, user
    existing.reload
    assert_in_delta Time.current, existing.last_login_at, 5.seconds
    user.reload
    assert_equal existing.id, user.primary_identity_id
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/services/session_creator_test.rb -v`

- [ ] **Step 3: Minimal implementation for Case A**

Write `app/services/session_creator.rb`:

```ruby
class SessionCreator
  # @param profile [Auth::ProviderProfile]
  # @return [User]
  # @raise [Auth::InvalidProfile], [Auth::EmailMismatch]
  def call(profile)
    raise Auth::InvalidProfile, "profile email blank" if profile.email.blank?

    User.transaction do
      identity = Identity.find_by(provider: profile.provider, uid: profile.uid)
      user =
        if identity
          # Case A
          identity.user
        else
          raise NotImplementedError, "Case B/C — next task"
        end

      user.track_login!(identity)
      user
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/services/session_creator_test.rb -v`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add app/services/session_creator.rb test/services/session_creator_test.rb
git commit -m "feat(auth): SessionCreator handles Case A (existing identity)"
```

### Task B.13: `SessionCreator` — Case B (email 매치 + email_verified)

**Files:**
- Modify: `app/services/session_creator.rb`
- Modify: `test/services/session_creator_test.rb`

- [ ] **Step 1: Failing test — Case B**

Edit `test/services/session_creator_test.rb` — add:

```ruby
test "Case B — email matches existing user, verified → attaches new identity" do
  user = users(:tonny)
  profile = Auth::ProviderProfile.new(
    provider: "google_oauth2",
    uid: "different-google-uid",     # new identity for this user
    email: user.email,
    email_verified: true,
    name: "Tonny Kim",
    avatar_url: nil
  )

  assert_difference -> { user.identities.count }, +1 do
    result = SessionCreator.new.call(profile)
    assert_equal user, result
  end

  new_identity = user.identities.find_by!(uid: "different-google-uid")
  user.reload
  assert_equal new_identity.id, user.primary_identity_id
end

test "Case B — email_verified=false raises EmailMismatch" do
  user = users(:tonny)
  profile = Auth::ProviderProfile.new(
    provider: "google_oauth2",
    uid: "untrusted-uid",
    email: user.email,
    email_verified: false,
    name: "X",
    avatar_url: nil
  )
  assert_raises(Auth::EmailMismatch) { SessionCreator.new.call(profile) }
end

test "Case B — email_verified=nil raises EmailMismatch (strict)" do
  user = users(:tonny)
  profile = Auth::ProviderProfile.new(
    provider: "google_oauth2",
    uid: "untrusted-nil-uid",
    email: user.email,
    email_verified: nil,
    name: "X",
    avatar_url: nil
  )
  assert_raises(Auth::EmailMismatch) { SessionCreator.new.call(profile) }
end
```

- [ ] **Step 2: Run — expect FAIL (NotImplementedError 가 뜨거나 raise_error 안 맞음)**

- [ ] **Step 3: Expand SessionCreator**

Edit `app/services/session_creator.rb`:

```ruby
class SessionCreator
  def call(profile)
    raise Auth::InvalidProfile, "profile email blank" if profile.email.blank?

    User.transaction do
      identity = Identity.find_by(provider: profile.provider, uid: profile.uid)
      user =
        if identity
          # Case A
          identity.user
        elsif (matched = User.find_by(email: profile.email))
          # Case B — email matches existing user
          unless profile.email_verified == true
            raise Auth::EmailMismatch,
                  "provider did not verify email=#{profile.email}"
          end
          identity = matched.identities.create!(
            provider: profile.provider,
            uid: profile.uid,
            email: profile.email,
            email_verified: profile.email_verified,
            name: profile.name,
            avatar_url: profile.avatar_url
          )
          matched
        else
          raise NotImplementedError, "Case C — next task"
        end

      user.track_login!(identity)
      user
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/services/session_creator_test.rb -v`
Expected: 4 assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/session_creator.rb test/services/session_creator_test.rb
git commit -m "feat(auth): SessionCreator Case B (verified email link)"
```

### Task B.14: `SessionCreator` — Case C (new user)

**Files:**
- Modify: `app/services/session_creator.rb`
- Modify: `test/services/session_creator_test.rb`

- [ ] **Step 1: Failing test — Case C + admin bootstrap**

Edit `test/services/session_creator_test.rb` — add:

```ruby
test "Case C — new email creates User + Identity" do
  profile = Auth::ProviderProfile.new(
    provider: "google_oauth2",
    uid: "brand-new-uid",
    email: "newbie@timberay.com",
    email_verified: true,
    name: "New Bie",
    avatar_url: nil
  )

  assert_difference -> { User.count }, +1 do
    assert_difference -> { Identity.count }, +1 do
      user = SessionCreator.new.call(profile)
      assert_equal "newbie@timberay.com", user.email
      assert_equal user.identities.first.id, user.primary_identity_id
      refute user.admin?
    end
  end
end

test "Case C — REGISTRY_ADMIN_EMAIL match grants admin=true" do
  Rails.configuration.x.registry.admin_email = "boss@timberay.com"
  profile = Auth::ProviderProfile.new(
    provider: "google_oauth2",
    uid: "boss-uid",
    email: "boss@timberay.com",
    email_verified: true,
    name: "The Boss",
    avatar_url: nil
  )

  user = SessionCreator.new.call(profile)
  assert user.admin?
end

test "InvalidProfile raised for blank email" do
  profile = Auth::ProviderProfile.new(
    provider: "google_oauth2", uid: "x", email: "",
    email_verified: true, name: nil, avatar_url: nil
  )
  assert_raises(Auth::InvalidProfile) { SessionCreator.new.call(profile) }
end
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Complete SessionCreator**

Edit `app/services/session_creator.rb`:

```ruby
class SessionCreator
  def call(profile)
    raise Auth::InvalidProfile, "profile email blank" if profile.email.blank?

    User.transaction do
      identity = Identity.find_by(provider: profile.provider, uid: profile.uid)
      user =
        if identity
          identity.user
        elsif (matched = User.find_by(email: profile.email))
          unless profile.email_verified == true
            raise Auth::EmailMismatch,
                  "provider did not verify email=#{profile.email}"
          end
          identity = matched.identities.create!(
            provider: profile.provider,
            uid: profile.uid,
            email: profile.email,
            email_verified: profile.email_verified,
            name: profile.name,
            avatar_url: profile.avatar_url
          )
          matched
        else
          new_user = User.create!(
            email: profile.email,
            admin: User.admin_email?(profile.email)
          )
          identity = new_user.identities.create!(
            provider: profile.provider,
            uid: profile.uid,
            email: profile.email,
            email_verified: profile.email_verified,
            name: profile.name,
            avatar_url: profile.avatar_url
          )
          new_user
        end

      user.track_login!(identity)
      user
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/services/session_creator_test.rb -v`
Expected: 모든 A/B/C 테스트 (7+) PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/session_creator.rb test/services/session_creator_test.rb
git commit -m "feat(auth): SessionCreator Case C (new user creation)"
```

### Task B.15: PR-2 push + PR 생성

- [ ] **Step 1: 전체 테스트**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager`
Expected: PASS.

- [ ] **Step 2: Push**

```bash
git push
```

- [ ] **Step 3: PR 생성 — base: main (stack) or feature/registry-auth-stage0 (if stacking)**

For linear merge strategy, base to main and reference PR-1:

```bash
gh pr create --base main --title "feat(auth): Stage 0 PR-2 OmniAuth services + Auth errors" --body "$(cat <<'EOF'
## Summary
- omniauth / omniauth-google-oauth2 / omniauth-rails_csrf_protection / jwt / rack-attack gems
- `Auth::Error` hierarchy (`InvalidProfile`, `EmailMismatch`, `ProviderOutage`)
- `Auth::ProviderProfile` VO
- `Auth::GoogleAdapter#to_profile`
- `SessionCreator` handles Case A/B/C + admin bootstrap

## Test plan
- [x] `bin/rails test` — 전 테스트 PASS
- [x] SessionCreator: 7 assertions (A/B/C + admin + blank email)
- [x] GoogleAdapter: 4 assertions
- [x] `bin/rubocop` + `bin/brakeman` green

Phase B Stage 0 plan 의 PR-2 (behavioral, service layer). PR-3 는 controller + routes + UI.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### PR-3 — Behavioral: Controller + Routes + UI + rack-attack

### Task B.16: OmniAuth initializer + routes

**Files:**
- Create: `config/initializers/omniauth.rb`
- Modify: `config/routes.rb`
- Modify: `config/initializers/registry.rb`

- [ ] **Step 1: Initializer 작성**

Write `config/initializers/omniauth.rb`:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           Rails.application.credentials.dig(:google_oauth, :client_id),
           Rails.application.credentials.dig(:google_oauth, :client_secret),
           {
             scope: "email,profile",
             prompt: "select_account",
             image_aspect_ratio: "square",
             image_size: 50,
             access_type: "online"
           }
end

OmniAuth.config.allowed_request_methods = [:post]
OmniAuth.config.silence_get_warning = false

OmniAuth.config.on_failure = ->(env) {
  env["action_dispatch.request.path_parameters"] = { controller: "auth/sessions", action: "failure" }
  Auth::SessionsController.action(:failure).call(env)
}
```

- [ ] **Step 2: Routes 추가**

Edit `config/routes.rb` — before `root "repositories#index"` 줄:

```ruby
# OmniAuth (Stage 0 — Google only)
get    "/auth/:provider/callback", to: "auth/sessions#create",  as: :auth_callback
get    "/auth/failure",            to: "auth/sessions#failure", as: :auth_failure
delete "/auth/sign_out",           to: "auth/sessions#destroy", as: :sign_out

# Test-only signin helper
if Rails.env.test?
  post "/testing/sign_in", to: "testing#sign_in"
end
```

(나머지 라우트는 그대로.)

- [ ] **Step 3: config/initializers/registry.rb 확장 (Stage 0 부분)**

Edit `config/initializers/registry.rb`:

```ruby
Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
  # Stage 1 필드는 여기 추가 예정
end
```

- [ ] **Step 4: Smoke — 서버 부트**

Run: `bin/rails routes | grep auth`
Expected: `/auth/:provider/callback` 등이 나열됨.

- [ ] **Step 5: Commit**

```bash
git add config/initializers/omniauth.rb config/routes.rb config/initializers/registry.rb
git commit -m "feat(auth): wire OmniAuth Google provider + /auth/* routes"
```

### Task B.17: `Auth::SessionsController` + `TestingController`

**Files:**
- Create: `app/controllers/auth/sessions_controller.rb`
- Create: `app/controllers/testing_controller.rb`
- Create: `test/controllers/auth/sessions_controller_test.rb`

- [ ] **Step 1: Failing integration test**

Write `test/controllers/auth/sessions_controller_test.rb`:

```ruby
require "test_helper"

class Auth::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_google(email:, uid:, verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: "Test User" },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  test "GET /auth/google_oauth2/callback with valid auth → session created, redirect to root" do
    mock_google(email: "tonny@timberay.com", uid: identities(:tonny_google).uid)
    get "/auth/google_oauth2/callback"
    assert_redirected_to root_path
    assert_equal users(:tonny).id, session[:user_id]
  end

  test "new email → user created, signed in" do
    mock_google(email: "newbie@timberay.com", uid: "new-uid")
    assert_difference -> { User.count }, +1 do
      get "/auth/google_oauth2/callback"
    end
    assert_equal User.find_by!(email: "newbie@timberay.com").id, session[:user_id]
    assert_redirected_to root_path
  end

  test "email unverified Case B → redirect to failure with flash" do
    mock_google(email: users(:tonny).email, uid: "untrusted-uid", verified: false)
    get "/auth/google_oauth2/callback"
    assert_redirected_to auth_failure_path(strategy: "google_oauth2", message: "email_mismatch")
  end

  test "DELETE /auth/sign_out clears session" do
    # First sign in
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_equal users(:tonny).id, session[:user_id]

    delete sign_out_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/controllers/auth/sessions_controller_test.rb -v`

- [ ] **Step 3: Write controller**

Write `app/controllers/auth/sessions_controller.rb`:

```ruby
class Auth::SessionsController < ApplicationController
  skip_forgery_protection only: [:create]

  def create
    profile = adapter_for(provider_param).to_profile(request.env.fetch("omniauth.auth"))
    user = SessionCreator.new.call(profile)
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "Signed in as #{user.email}"
  rescue Auth::EmailMismatch
    redirect_to auth_failure_path(strategy: provider_param, message: "email_mismatch")
  rescue Auth::InvalidProfile
    redirect_to auth_failure_path(strategy: provider_param, message: "invalid_profile")
  rescue Auth::ProviderOutage
    redirect_to auth_failure_path(strategy: provider_param, message: "provider_outage")
  end

  def failure
    strategy = params[:strategy].presence || "unknown"
    message  = params[:message].presence  || "failed"
    flash[:alert] = "Sign-in failed (#{strategy}: #{message})."
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out."
  end

  private

  def provider_param
    params[:provider].presence || request.path_parameters[:provider] || "google_oauth2"
  end

  def adapter_for(provider)
    case provider
    when "google_oauth2" then Auth::GoogleAdapter.new
    else raise Auth::InvalidProfile, "unsupported provider: #{provider}"
    end
  end
end
```

- [ ] **Step 4: Testing controller**

Write `app/controllers/testing_controller.rb`:

```ruby
# Test-only helper — only mounted when Rails.env.test?.
class TestingController < ApplicationController
  skip_forgery_protection

  def sign_in
    session[:user_id] = params[:user_id]
    head :ok
  end
end
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rails test test/controllers/auth/sessions_controller_test.rb -v`
Expected: 4 assertions PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/auth/sessions_controller.rb app/controllers/testing_controller.rb test/controllers/auth/sessions_controller_test.rb
git commit -m "feat(auth): OAuth callback + sign_out + failure handlers"
```

### Task B.18: `ApplicationController#current_user` + session restore

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Create: `test/integration/auth_session_restore_test.rb`

- [ ] **Step 1: Failing test**

Write `test/integration/auth_session_restore_test.rb`:

```ruby
require "test_helper"

class AuthSessionRestoreTest < ActionDispatch::IntegrationTest
  test "current_user is nil when not signed in" do
    get "/"
    assert_response :ok
    assert_nil controller.current_user  # via integration helper
  end

  test "session[:user_id] restores current_user" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/"
    assert_response :ok
  end

  test "stale session[:user_id] (user deleted) silently resets" do
    # simulate by pointing to an id that doesn't exist
    Rails.application.env_config.delete("omniauth.auth")
    deleted_id = 999_999
    post "/testing/sign_in", params: { user_id: deleted_id }
    get "/"
    assert_response :ok
    # No exception; current_user is nil after stale restore
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rails test test/integration/auth_session_restore_test.rb -v`

- [ ] **Step 3: Expand `ApplicationController`**

Edit `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_user, :signed_in?

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

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rails test test/integration/auth_session_restore_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/application_controller.rb test/integration/auth_session_restore_test.rb
git commit -m "feat(auth): ApplicationController#current_user + session restore"
```

### Task B.19: rack-attack `/auth/*` throttle

**Files:**
- Create: `config/initializers/rack_attack.rb`
- Create: `test/integration/rack_attack_auth_throttle_test.rb`

- [ ] **Step 1: Failing test — 11 번째 요청 429**

Write `test/integration/rack_attack_auth_throttle_test.rb`:

```ruby
require "test_helper"

class RackAttackAuthThrottleTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    Rack::Attack.enabled = true
  end
  teardown { Rack::Attack.enabled = false }

  test "POST /auth/google_oauth2 is throttled at 10/min/IP" do
    headers = { "REMOTE_ADDR" => "198.51.100.10" }
    10.times do |i|
      post "/auth/google_oauth2", headers: headers
      refute_equal 429, response.status, "request #{i + 1} should not be throttled"
    end
    post "/auth/google_oauth2", headers: headers
    assert_equal 429, response.status
  end
end
```

- [ ] **Step 2: Run — expect FAIL (Rack::Attack 미로드)**

- [ ] **Step 3: Initializer**

Write `config/initializers/rack_attack.rb`:

```ruby
class Rack::Attack
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.start_with?("/auth/")
      req.ip
    end
  end

  throttled_responder = lambda do |req|
    [429,
     { "Content-Type" => "application/json", "Retry-After" => "60" },
     [{ errors: [{ code: "TOO_MANY_REQUESTS", message: "rate limited" }] }.to_json]]
  end
  Rack::Attack.throttled_responder = throttled_responder
end
```

- [ ] **Step 4: Application 에 middleware 로 등록 확인**

`rack-attack` gem 은 Rails 에서 자동으로 `Rack::Attack` 미들웨어를 삽입. 확인: `bin/rails middleware | grep -i attack`
Expected: `use Rack::Attack` 라인 존재.

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rails test test/integration/rack_attack_auth_throttle_test.rb -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/initializers/rack_attack.rb test/integration/rack_attack_auth_throttle_test.rb
git commit -m "feat(auth): rack-attack /auth/* 10/min/IP throttle"
```

### Task B.20: Web UI — 로그인 버튼 + 사용자 헤더

**Files:**
- Modify: `app/views/layouts/application.html.erb` (or the layout Rails currently uses)
- Create: `test/integration/login_button_visibility_test.rb`

- [ ] **Step 1: Layout 파일 확인**

Run: `ls app/views/layouts/`

기본 레이아웃은 `application.html.erb`. 파일 위치를 확인하고 내용을 읽어둔다.

- [ ] **Step 2: Failing integration test**

Write `test/integration/login_button_visibility_test.rb`:

```ruby
require "test_helper"

class LoginButtonVisibilityTest < ActionDispatch::IntegrationTest
  test "unauthenticated home shows 'Sign in with Google' button" do
    get "/"
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'][method='post'] button",
                  text: /Sign in with Google/i
  end

  test "signed-in home shows user email and sign-out" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/"
    assert_response :ok
    assert_match users(:tonny).email, response.body
    assert_select "form[action='/auth/sign_out'][method='post']"
  end
end
```

(ERB `button_to` 는 POST form 생성.)

- [ ] **Step 3: Run — expect FAIL**

- [ ] **Step 4: Update layout with partial**

Write `app/views/shared/_auth_nav.html.erb`:

```erb
<% if signed_in? %>
  <span class="text-sm text-slate-600" aria-label="signed-in user">
    <%= current_user.email %>
  </span>
  <%= button_to "Sign out", sign_out_path, method: :delete,
               class: "text-sm px-3 py-1.5 rounded-md bg-slate-100 hover:bg-slate-200",
               data: { turbo_confirm: "Sign out?" } %>
<% else %>
  <%= button_to "Sign in with Google", "/auth/google_oauth2", method: :post,
               class: "text-sm px-3 py-1.5 rounded-md bg-indigo-600 text-white hover:bg-indigo-700",
               data: { turbo: false } %>
<% end %>
```

Then include it in the layout — edit `app/views/layouts/application.html.erb`, add in the `<nav>` (or header area):

```erb
<nav class="flex items-center justify-between px-4 md:px-6 py-3 border-b border-slate-200">
  <%= link_to "open-repo", root_path, class: "font-semibold text-slate-900" %>
  <div class="flex items-center gap-3">
    <%= render "shared/auth_nav" %>
  </div>
</nav>
```

(기존 nav 구조 보존하면서 partial 삽입. 기존 nav 가 이미 있으면 그 안에 `<%= render "shared/auth_nav" %>` 삽입만.)

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rails test test/integration/login_button_visibility_test.rb -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/shared/_auth_nav.html.erb app/views/layouts/application.html.erb test/integration/login_button_visibility_test.rb
git commit -m "feat(auth): layout shows sign-in/sign-out based on current_user"
```

### Task B.21: End-to-end OAuth flow integration test

**Files:**
- Create: `test/integration/auth_google_oauth_flow_test.rb`

- [ ] **Step 1: Failing integration test — full flow**

Write `test/integration/auth_google_oauth_flow_test.rb`:

```ruby
require "test_helper"

class AuthGoogleOauthFlowTest < ActionDispatch::IntegrationTest
  setup { OmniAuth.config.test_mode = true }
  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_google(email:, uid:, verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: { email: email, name: "Test" },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  test "new user full OAuth round-trip: login → home shows email → sign out" do
    mock_google(email: "fresh@timberay.com", uid: "fresh-uid")
    assert_difference -> { User.count }, +1 do
      get "/auth/google_oauth2/callback"
      assert_redirected_to root_path
      follow_redirect!
    end
    assert_match "fresh@timberay.com", response.body

    delete sign_out_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match "Sign in with Google", response.body
  end

  test "returning user: existing identity reused, primary_identity updated" do
    existing = identities(:tonny_google)
    mock_google(email: existing.email, uid: existing.uid)

    assert_no_difference -> { User.count } do
      get "/auth/google_oauth2/callback"
    end
    existing.reload
    assert_in_delta Time.current, existing.last_login_at, 5.seconds
  end

  test "admin bootstrap: REGISTRY_ADMIN_EMAIL gets admin=true on first login" do
    Rails.configuration.x.registry.admin_email = "boss@timberay.com"
    mock_google(email: "boss@timberay.com", uid: "boss-uid")
    get "/auth/google_oauth2/callback"
    assert User.find_by!(email: "boss@timberay.com").admin?
  end
end
```

- [ ] **Step 2: Run — expect PASS (모든 요소가 Task B.12–B.20 에서 준비됨)**

Run: `bin/rails test test/integration/auth_google_oauth_flow_test.rb -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/integration/auth_google_oauth_flow_test.rb
git commit -m "test(auth): end-to-end Google OAuth flow integration test"
```

### Task B.22: CSP / CSRF protection 검증

**Files:**
- Modify: `config/initializers/content_security_policy.rb` (if present — Rails 8 default 가 주석 상태일 수 있음)

- [ ] **Step 1: 파일 존재 확인**

Run: `cat config/initializers/content_security_policy.rb 2>/dev/null | head -20`

- [ ] **Step 2: CSP 파일 주석 해제 상태면 Google OAuth 도메인 허용 확인 (연결 리스트에 accounts.google.com 포함)**

활성화된 경우 아래 directive 확인:

```ruby
policy.connect_src :self, :https
policy.script_src  :self
# Google OAuth 는 CSP 밖의 redirect 이므로 보통 추가 설정 불필요.
```

- [ ] **Step 3: CSRF — `omniauth-rails_csrf_protection` gem 이 POST-only + token 검사 적용 여부 smoke**

Run:

```bash
bin/rails runner 'puts OmniAuth.config.allowed_request_methods'
```

Expected: `[:post]`.

- [ ] **Step 4: 변경 없으면 skip; 변경 필요하면 Commit**

변경이 있었으면:
```bash
git add config/initializers/content_security_policy.rb
git commit -m "chore(auth): verify CSP + CSRF protection for OAuth"
```

### Task B.23: 문서 업데이트

**Files:**
- Modify: `README.md` (Auth 섹션 추가)
- Modify: `CLAUDE.md` (필요 시 Auth 노트)
- Modify: `docs/standards/STACK.md` (§ Authentication 섹션 — 현재 open-repo 가 실제 구현한 것을 반영)

- [ ] **Step 1: STACK.md Auth 섹션 교체**

Edit `docs/standards/STACK.md` — `### Authentication` 섹션을 실제 구현 반영 (기존 템플릿은 gstack 에서 상속된 것이라 GuestMerger 가 있었음, 실제로는 제거됨):

```markdown
### Authentication

OAuth-only via OmniAuth 2.x (no password). Provider: Google (`omniauth-google-oauth2`). Additional providers (Naver, Kakao) can be added in future stages.

Session model: no guest row. Only authenticated users exist; `User` has at least one `Identity` (`provider`, `uid`) unique per provider. `User.primary_identity_id` 는 최근 로그인 identity 포인터 (DB 레벨 nullable, SessionCreator 트랜잭션이 ~1ms 내 채움).

OAuth callback pipeline:

1. `Auth::GoogleAdapter#to_profile` — normalize omniauth `auth_hash` into `Auth::ProviderProfile` (`provider`, `uid`, `email`, `email_verified`, `name`, `avatar_url`). `email_verified` is tri-state: `true`, `false`, or `nil`.
2. `SessionCreator` — three cases:
   - **Case A** — existing `Identity(provider, uid)` → sign in.
   - **Case B** — `email` matches existing account user AND `email_verified == true` → add new identity.
   - **Case C** — new user → create User + Identity.
3. `User#track_login!(identity)` (via `Auth::LoginTracker` concern) — updates `identity.last_login_at` + `user.primary_identity_id` + `user.last_seen_at` in one transaction.

Defense: `reset_session` after every successful callback, `rack-attack` throttles `/auth/*` POST at 10/min/IP, `Auth::Error` hierarchy (`InvalidProfile`, `EmailMismatch`, `ProviderOutage`) is `rescue_from`-caught in `Auth::SessionsController`.

Admin bootstrap: `REGISTRY_ADMIN_EMAIL` 로 지정된 이메일이 최초 OAuth 로그인 시 `admin=true` 부여. Seed 없음.

Test helpers: `OmniAuth.config.mock_auth[:google_oauth2]` in `test_helper.rb`, `/testing/sign_in` route (test env only) for integration tests needing to seed session state.
```

- [ ] **Step 2: README.md 에 Authentication 섹션 추가 (로그인 방법 안내)**

Edit `README.md` — 적절한 위치에:

```markdown
## Authentication

open-repo uses Google OAuth 2 for Web UI sign-in. To enable it:

1. Create a Google Cloud OAuth Client (Web application type) at https://console.cloud.google.com/apis/credentials
2. Set redirect URI: `https://<your-host>/auth/google_oauth2/callback`
3. Store client id/secret: `bin/rails credentials:edit --environment <env>`
   ```yaml
   google_oauth:
     client_id: "xxx.apps.googleusercontent.com"
     client_secret: "GOCSPX-..."
   ```
4. Set `REGISTRY_ADMIN_EMAIL=<your-email>` (the first user to sign in with this email gets `admin=true`).

Docker CLI / Registry V2 API authentication is part of Stage 1 (not yet shipped).
```

- [ ] **Step 3: Commit**

```bash
git add docs/standards/STACK.md README.md CLAUDE.md
git commit -m "docs(auth): document OmniAuth Google flow in STACK and README"
```

### Task B.24: PR-3 push + PR 생성 + 최종 검증

- [ ] **Step 1: 전체 테스트 + lint + security**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager && bin/bundler-audit check`
Expected: 모든 도구 green.

- [ ] **Step 2: Schema 파일이 Stage 0 기대치와 일치하는지 확인**

Run: `grep -A20 'create_table "users"\|create_table "identities"' db/schema.rb`
Expected: 두 테이블 + 인덱스 + primary_identity FK.

- [ ] **Step 3: Dev 환경 수동 smoke**

Run (`.env.development` 에 `REGISTRY_ADMIN_EMAIL` + Google credentials 주입 후):
```bash
bin/rails server
# 브라우저 http://localhost:3000 → "Sign in with Google" 클릭 → Google consent → redirect → home 에 user email 표시 확인
```
Expected: 로그인 성공, User/Identity row 생성.

- [ ] **Step 4: Push + PR**

```bash
git push
gh pr create --base main --title "feat(auth): Stage 0 PR-3 OAuth callback, session, UI" --body "$(cat <<'EOF'
## Summary
- `/auth/google_oauth2/callback` → `Auth::SessionsController#create` (Case A/B/C via SessionCreator)
- `/auth/sign_out` destroys session
- `ApplicationController#current_user` + `signed_in?` helper
- Layout partial `shared/_auth_nav` with sign-in/sign-out
- rack-attack 10/min/IP on `/auth/*` POST
- End-to-end OAuth flow + session-restore + throttle integration tests
- STACK.md + README.md updated

## Test plan
- [x] `bin/rails test` — 전 테스트 PASS (신규 ~15 assertions)
- [x] `bin/rubocop` + `bin/brakeman` green
- [x] Dev smoke: 실 Google consent → user row 생성 확인

Closes Stage 0 of the registry auth initiative. Stage 1 (PAT + Docker V2 token exchange) 은 별도 브랜치에서 착수.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Merge 후 clean up**

```bash
git checkout main
git pull origin main
git branch -d feature/registry-auth-stage0
```

**Phase B Stage 0 완료**. 다음 plan: `docs/superpowers/plans/YYYY-MM-DD-registry-auth-stage1-plan.md` (별도 writing-plans 호출).

---

## 수용 기준 (Stage 0 완료 판정)

- [ ] Phase A: 35 spec 파일 전부 포팅 완료, `spec/` 디렉터리 제거, `rspec-rails` gem 제거, CI `bin/rails test` 로 실행
- [ ] Phase B: `users` / `identities` 테이블 존재, 3 마이그레이션 머지, `feature/registry-auth-stage0` 브랜치 3 PR 머지
- [ ] Staging canary: admin 1명 Google OAuth 로그인 성공 + `REGISTRY_ADMIN_EMAIL` 적용 확인 + session persist
- [ ] 기존 V2 API traffic 영향 0 (anonymous push/pull 경로 그대로)
- [ ] Production 배포 전 `TODOS.md [P0]` 항목 제거 완료

---

## Self-Review (plan 작성 후)

**Spec coverage** — spec §1.1 Stage 0, §2.1–§2.3 (auth errors + services + LoginTracker), §5.2 google_oauth credentials, §8.2 Stage 0 체크리스트 의 각 항목이 task 에 매핑되는지 확인:

| Spec 요구사항 | Task |
|---|---|
| users + identities + primary_identity FK 3 마이그레이션 | B.2, B.3, B.4 |
| User 의 Auth::LoginTracker concern | B.5 |
| REGISTRY_ADMIN_EMAIL bootstrap | B.6, B.14 |
| omniauth + google + rails_csrf + jwt + rack-attack gems | B.8 |
| Auth::Error 계층 (Stage 0 부분) | B.9 |
| Auth::ProviderProfile VO | B.10 |
| Auth::GoogleAdapter#to_profile | B.11 |
| SessionCreator Case A/B/C | B.12, B.13, B.14 |
| /auth/:provider/callback 라우트 + 컨트롤러 | B.16, B.17 |
| /testing/sign_in test-only 라우트 | B.16, B.17 |
| ApplicationController#current_user + session restore | B.18 |
| rack-attack /auth/* 10/min/IP | B.19 |
| Web UI 로그인 버튼 + 로그아웃 | B.20 |
| End-to-end OAuth flow 테스트 | B.21 |
| CSP + CSRF 검증 | B.22 |
| STACK.md / README 업데이트 | B.23 |
| Phase A blocker (RSpec→Minitest) | A.0–A.13 |

**Placeholder scan** — "TBD" / "TODO" / "appropriate handling" 등의 vague phrase 가 없음. 모든 step 에 exact code.

**Type consistency** — `Auth::ProviderProfile` 의 field 이름이 모든 task 에서 일치. `User#track_login!(identity)` signature 가 B.5 / B.12 / B.13 / B.14 에서 동일. `Auth::GoogleAdapter#to_profile` signature 일관.

**Scope check** — Phase A + Phase B 한 plan 에 묶임. 브랜치 2개, PR 4개 (Phase A 1 + Phase B 3). 한 개발자 1주 목표치.

---

## Handoff 에러 처리 — 본 plan 이 아닌 다음 단계 안내

Stage 1/2 plan 은 본 Stage 0 머지 **이후** 별도 `/superpowers:writing-plans` 호출로 생성. 본 plan 의 범위 밖.
