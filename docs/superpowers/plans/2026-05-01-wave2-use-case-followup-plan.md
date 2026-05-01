# Wave 2 — Use-Case Follow-up Implementation Plan (2026-05-01)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wave 1 후속으로 Partial/N-I 10 건 (B-03, B-07, B-22, B-37, B-38, B-39, B-46, B-30, B-35, B-42) 을 Pass 로 승격. 사용성·문서·테스트 보강을 통해 사용자가 사인인 → PAT 발급 → `docker login` 까지 가이드된 플로우로 진입하게 한다.

**Architecture:** 3 개 sub-batch 병렬 worktree 디스패치 (Wave 1 동일 패턴):
- **W2-A** — Quick UX wins. 각 view/controller 가 다르므로 한 worktree 내 sequential commit 도 가능하나 review 단위는 PR-1 로 묶음.
- **W2-B** — Help page batch. 단일 view (`app/views/help/show.html.erb`) + 단일 controller (`v2/base_controller.rb`) 에 sequential 편집. 한 worktree 한 PR.
- **W2-C** — Test reinforcement. 3 개 test file 독립. 한 worktree 한 PR.

각 batch 가 main 머지 후 다음으로 넘어가지 않아도 됨 — 충돌 없음 (W2-A: sessions_controller/sessions/new.html.erb/_token_row.html.erb, W2-B: help/show.html.erb/v2/base_controller.rb, W2-C: test files 독립). 다만 Wave 1 에서처럼 **3 worktree 병렬 → 3 PR 동시 → 순차 머지** 가 안전.

**Tech Stack:** Rails 8.1, Minitest, ViewComponent (CardComponent 재사용), Tailwind CSS, Hotwire (turbo-frame 불필요), no JS work in Wave 2.

**Source spec:** `docs/superpowers/plans/2026-04-29-use-case-followup-plan.md` (Wave 2 섹션). 99 use-case 전수검사 결과의 Partial / N-I 갭 정의.

**Branching strategy:**
- `feature/wave2-w2a-quick-ux-wins` — B-03, B-07, B-22 (3 commits)
- `feature/wave2-w2b-help-page-batch` — B-37, B-38, B-39, B-46 (4 commits, sequential)
- `feature/wave2-w2c-test-reinforcement` — B-30, B-35, B-42 (3 commits)

각 PR 은 독립 green CI. 머지 순서: W2-C (test only, 가장 안전) → W2-A → W2-B (또는 충돌 없으니 임의 순서).

---

## File Structure

| Path | 목적 | Sub-batch |
|---|---|---|
| `app/controllers/auth/sessions_controller.rb` | sign-out → `/sign_in` redirect (B-03) | W2-A |
| `app/views/auth/sessions/new.html.erb` | 프로젝트 설명 + 로그인 후 가이드 안내 (B-07) | W2-A |
| `app/views/settings/tokens/_token_row.html.erb` | Prefix 컬럼 추가 (B-22) | W2-A |
| `app/views/settings/tokens/index.html.erb` | thead 에 Prefix 헤더 추가 (B-22) | W2-A |
| `app/models/personal_access_token.rb` | `prefix` 컬럼 자동 세팅 (B-22) | W2-A |
| `app/controllers/settings/tokens_controller.rb` | 생성 시 `prefix` 저장 (B-22) | W2-A |
| `db/migrate/<ts>_add_prefix_to_personal_access_tokens.rb` | prefix 컬럼 추가 + 기존 row backfill (B-22) | W2-A |
| `db/schema.rb` | migrate 결과 반영 (B-22) | W2-A |
| `app/views/help/show.html.erb` | PAT 생성 / sign-in / HTTPS / docker login 섹션 추가 (B-37, B-39, B-46) | W2-B |
| `app/controllers/v2/base_controller.rb` | 401 본문에 `/help` 포인터 추가 (B-38) | W2-B |
| `test/integration/docker_basic_auth_test.rb` | `docker login` 시뮬 통합 테스트 (B-30) | W2-C |
| `test/integration/pat_lifecycle_test.rb` | typo password V2 테스트 (B-35) | W2-C |
| `test/integration/tag_recovery_test.rb` | 신규 — re-tag 복구 시나리오 (B-42) | W2-C |
| `test/controllers/auth/sessions_controller_test.rb` | 기존 destroy → root_path 단언 수정 (B-03) | W2-A |
| `test/controllers/settings/tokens_controller_test.rb` | prefix 노출 단언 (B-22) | W2-A |

---

## Sub-batch W2-A: Quick UX Wins

**Branch:** `feature/wave2-w2a-quick-ux-wins`

### Task A1 (B-03): Sign-out redirects to /sign_in

**Files:**
- Modify: `app/controllers/auth/sessions_controller.rb:42-45`
- Modify: `test/controllers/auth/sessions_controller_test.rb` (existing destroy assertion)

- [ ] **Step 1: Update existing destroy test to expect /sign_in redirect**

`test/controllers/auth/sessions_controller_test.rb` 의 기존 destroy 테스트:

```ruby
test "DELETE /auth/sign_out clears session" do
  post "/testing/sign_in", params: { user_id: users(:tonny).id }
  assert_equal users(:tonny).id, session[:user_id]

  delete sign_out_path
  assert_redirected_to sign_in_path
  assert_nil session[:user_id]
end
```

(이전 `assert_redirected_to root_path` → `sign_in_path`)

- [ ] **Step 2: Run the test, expect FAIL**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb -n "/sign_out clears session/"
```

기대 출력: `Expected response to be a redirect to <http://www.example.com/sign_in> but was a redirect to <http://www.example.com/>`.

- [ ] **Step 3: Update destroy action**

`app/controllers/auth/sessions_controller.rb:42-45`:

```ruby
def destroy
  reset_session
  redirect_to sign_in_path, notice: "Signed out."
end
```

- [ ] **Step 4: Run the test, expect PASS**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb
```

전체 sessions_controller_test 그린이어야 함 (다른 단언 영향 없음).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/auth/sessions_controller.rb test/controllers/auth/sessions_controller_test.rb
git commit -m "fix(auth): redirect to /sign_in after sign-out (B-03)"
```

---

### Task A2 (B-07): Sign-in page project description

**Files:**
- Modify: `app/views/auth/sessions/new.html.erb:1-7`
- Modify: `test/controllers/auth/sessions_controller_test.rb` (assertion on landing copy)

- [ ] **Step 1: Add a failing test asserting description copy on /sign_in**

`test/controllers/auth/sessions_controller_test.rb` 끝 부분에 추가:

```ruby
test "GET /sign_in shows project description and PAT/help pointers" do
  get "/sign_in"
  assert_response :ok
  assert_select "p", text: /open-repo.*self-hosted Docker registry/i
  assert_select "a[href=?]", "/help", text: /Setup guide/i
end
```

- [ ] **Step 2: Run, expect FAIL**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb -n "/sign_in shows project description/"
```

- [ ] **Step 3: Update view**

`app/views/auth/sessions/new.html.erb` 전체 교체:

```erb
<% content_for :title, "Sign in" %>
<div class="max-w-md mx-auto py-16 px-4 text-center">
  <h1 class="text-2xl font-semibold text-slate-100 mb-4">Sign in to continue</h1>
  <p class="text-sm text-slate-300 mb-2">
    open-repo is a self-hosted Docker registry. Sign in with your work account
    to push images, manage repositories, and issue Personal Access Tokens for
    <code class="bg-slate-800 text-slate-100 rounded px-1">docker login</code>.
  </p>
  <p class="text-xs text-slate-400 mb-6">
    Need configuration help first? See the
    <%= link_to "Setup guide", help_path, class: "underline text-indigo-300 hover:text-indigo-200" %>.
  </p>
  <%= button_to "Sign in with Google", "/auth/google_oauth2", method: :post,
                class: "inline-flex items-center justify-center min-h-11 px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700 transition-colors duration-150",
                data: { turbo: false } %>
</div>
```

- [ ] **Step 4: Run, expect PASS**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb
```

전체 sessions_controller_test 그린.

- [ ] **Step 5: Commit**

```bash
git add app/views/auth/sessions/new.html.erb test/controllers/auth/sessions_controller_test.rb
git commit -m "feat(auth): describe project on /sign_in with help link (B-07)"
```

---

### Task A3 (B-22): Show PAT prefix column

`oprk_` 자체는 모든 토큰 공통이라 식별 가치가 작다. 토큰 처음 12 자 (`oprk_xxxxxxx`) 를 `prefix` 컬럼에 저장해 사용자가 분실/혼동 시 어떤 토큰인지 식별할 수 있게 한다 (GitHub `ghp_` 패턴 동일).

**Files:**
- Create: `db/migrate/<ts>_add_prefix_to_personal_access_tokens.rb`
- Modify: `db/schema.rb` (migrate 결과 자동 반영)
- Modify: `app/models/personal_access_token.rb`
- Modify: `app/controllers/settings/tokens_controller.rb`
- Modify: `app/views/settings/tokens/index.html.erb` (thead)
- Modify: `app/views/settings/tokens/_token_row.html.erb` (tbody)
- Modify: `test/controllers/settings/tokens_controller_test.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails g migration AddPrefixToPersonalAccessTokens prefix:string
```

생성된 마이그레이션 파일을 다음과 같이 수정 (backfill + null:false):

```ruby
class AddPrefixToPersonalAccessTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :personal_access_tokens, :prefix, :string
    # Backfill: existing rows lose distinguishing chars (raw token is gone),
    # but we can still assign the static "oprk_" sentinel so the column stays
    # NOT NULL and readers don't have to handle nil. Display logic shows the
    # full prefix (12 chars) for new tokens.
    PersonalAccessToken.reset_column_information
    PersonalAccessToken.where(prefix: nil).update_all(prefix: "oprk_legacy")
    change_column_null :personal_access_tokens, :prefix, false
  end

  def down
    remove_column :personal_access_tokens, :prefix
  end
end
```

- [ ] **Step 2: Run migration, schema check**

```bash
bin/rails db:migrate
bin/rails db:migrate RAILS_ENV=test
grep -A 3 "personal_access_tokens" db/schema.rb | grep prefix
```

기대: `t.string "prefix", null: false`.

- [ ] **Step 3: Add failing test asserting prefix display**

`test/controllers/settings/tokens_controller_test.rb` 에 추가:

```ruby
test "GET /settings/tokens lists prefix column for each token" do
  post "/testing/sign_in", params: { user_id: users(:tonny).id }
  get settings_tokens_path
  assert_response :ok
  assert_select "th", text: "Prefix"
  # Existing fixture-loaded PATs render via _token_row partial; the column
  # is present on every row.
  assert_select "tr td", text: /\Aoprk_/
end
```

또한 create 가 prefix 를 저장하는지:

```ruby
test "POST /settings/tokens stores 12-char prefix from raw token" do
  post "/testing/sign_in", params: { user_id: users(:tonny).id }
  assert_difference -> { PersonalAccessToken.count }, +1 do
    post settings_tokens_path, params: {
      personal_access_token: { name: "with-prefix", kind: "cli" }
    }
  end
  raw = flash[:raw_token]
  pat = PersonalAccessToken.order(:id).last
  assert_equal raw[0, 12], pat.prefix
end
```

- [ ] **Step 4: Run tests, expect FAIL**

```bash
bin/rails test test/controllers/settings/tokens_controller_test.rb
```

기대: 두 신규 테스트 FAIL (`prefix` 미저장 / 컬럼 미렌더).

- [ ] **Step 5: Update model + controller to set prefix**

`app/models/personal_access_token.rb` 의 `generate_raw` 와 인접해 `prefix_for` 헬퍼 추가:

```ruby
class PersonalAccessToken < ApplicationRecord
  RAW_PREFIX = "oprk_".freeze
  DISPLAY_PREFIX_LENGTH = 12

  belongs_to :identity

  validates :name, presence: true, uniqueness: { scope: :identity_id }
  validates :token_digest, presence: true, uniqueness: true
  validates :prefix, presence: true
  validates :kind, inclusion: { in: %w[cli ci] }

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  def self.generate_raw
    RAW_PREFIX + SecureRandom.urlsafe_base64(32)
  end

  def self.prefix_for(raw_token)
    raw_token.to_s[0, DISPLAY_PREFIX_LENGTH]
  end

  def self.authenticate_raw(raw_token)
    return nil if raw_token.blank?
    active.find_by(token_digest: Digest::SHA256.hexdigest(raw_token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
```

`app/controllers/settings/tokens_controller.rb` 의 create 에서 `prefix:` 세팅:

```ruby
def create
  raw = PersonalAccessToken.generate_raw
  pat = current_identity.personal_access_tokens.new(
    name: pat_params[:name],
    kind: pat_params[:kind].presence || "cli",
    token_digest: Digest::SHA256.hexdigest(raw),
    prefix: PersonalAccessToken.prefix_for(raw),
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
```

- [ ] **Step 6: Update views**

`app/views/settings/tokens/index.html.erb` 의 thead:

```erb
<thead>
  <tr class="text-left border-b">
    <th class="py-2">Name</th>
    <th>Kind</th>
    <th>Prefix</th>
    <th>Expires</th>
    <th>Last used</th>
    <th>Status</th>
    <th></th>
  </tr>
</thead>
```

`app/views/settings/tokens/_token_row.html.erb`:

```erb
<tr class="border-b">
  <td class="py-2"><%= token.name %></td>
  <td><%= token.kind %></td>
  <td><code class="font-mono text-xs text-slate-700"><%= token.prefix %></code></td>
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
                    data: { turbo_confirm: "Revoke '#{token.name}'? Docker logins using this token will fail." } %>
    <% end %>
  </td>
</tr>
```

- [ ] **Step 7: Update fixture (existing rows need prefix value)**

`test/fixtures/personal_access_tokens.yml` 의 모든 항목에 `prefix:` 추가. e.g.:

```yaml
tonny_cli_active:
  identity: tonny_google
  name: cli-active
  kind: cli
  token_digest: <%= Digest::SHA256.hexdigest("oprk_tonny_cli_active_raw_token_xxxxxxxxxxxxxxxxxxxxx") %>
  prefix: "oprk_tonnycl"
  ...
```

(실제 값은 fixture 파일 내 raw token 의 첫 12 자에 맞춤. 모든 fixture row 갱신.)

- [ ] **Step 8: Run tests, expect PASS**

```bash
bin/rails db:test:prepare
bin/rails test test/controllers/settings/tokens_controller_test.rb test/models/personal_access_token_test.rb
```

또한 기존 PAT lifecycle 테스트가 그린인지 확인:

```bash
bin/rails test test/integration/pat_lifecycle_test.rb
```

- [ ] **Step 9: Commit**

```bash
git add db/migrate/ db/schema.rb app/models/personal_access_token.rb \
        app/controllers/settings/tokens_controller.rb \
        app/views/settings/tokens/index.html.erb \
        app/views/settings/tokens/_token_row.html.erb \
        test/controllers/settings/tokens_controller_test.rb \
        test/fixtures/personal_access_tokens.yml
git commit -m "feat(tokens): show 12-char PAT prefix to disambiguate tokens (B-22)"
```

---

### Task A4 (W2-A): Open W2-A PR

- [ ] **Step 1: Push branch + create PR**

```bash
git push -u origin feature/wave2-w2a-quick-ux-wins
gh pr create --title "Wave2 W2-A: Quick UX wins (B-03, B-07, B-22)" --body "$(cat <<'EOF'
## Summary
- B-03: sign-out redirects to /sign_in instead of root
- B-07: /sign_in describes the project + links to /help
- B-22: PAT list shows 12-char prefix (oprk_xxxxxxx) for disambiguation

## Test plan
- [ ] sessions_controller_test.rb green
- [ ] settings/tokens_controller_test.rb green
- [ ] pat_lifecycle_test.rb green
- [ ] full suite green
EOF
)"
```

---

## Sub-batch W2-B: Help Page Batch + 401 Pointer

**Branch:** `feature/wave2-w2b-help-page-batch`

`app/views/help/show.html.erb` 단일 view 에 sequential 편집. 마지막에 `v2/base_controller.rb` 의 unauthorized 본문 추가.

### Task B1 (B-37): PAT generation guidance section in /help

**Files:**
- Modify: `app/views/help/show.html.erb`
- Modify: `test/controllers/help_controller_test.rb` (없으면 신규)

- [ ] **Step 1: Add failing test for PAT-generation section**

`test/controllers/help_controller_test.rb` (없으면 생성):

```ruby
require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "GET /help renders PAT generation guidance" do
    get "/help"
    assert_response :ok
    assert_select "h2", text: /Personal Access Token/i
    assert_select "a[href=?]", "/settings/tokens"
  end
end
```

- [ ] **Step 2: Run, expect FAIL**

```bash
bin/rails test test/controllers/help_controller_test.rb
```

- [ ] **Step 3: Add PAT section to help/show.html.erb**

`app/views/help/show.html.erb` 의 "Push & Pull Images" 카드 **앞** 에 신규 카드 삽입:

```erb
<%# Personal Access Tokens (B-37) %>
<%= render CardComponent.new(padding: :none, class: "mb-6") do %>
  <div class="p-6">
    <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-100 mb-4">Personal Access Tokens</h2>
    <p class="text-base text-slate-700 dark:text-slate-300 mb-3">
      The Docker CLI authenticates with this registry using a Personal Access Token (PAT).
      Generate one from <%= link_to "Settings → Tokens", settings_tokens_path, class: "text-blue-600 dark:text-blue-400 hover:underline" %>.
    </p>
    <ol class="list-decimal list-inside text-sm text-slate-700 dark:text-slate-300 space-y-1 mb-3">
      <li>Sign in with your work Google account.</li>
      <li>Open <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">/settings/tokens</code> and click <strong>New token</strong>.</li>
      <li>Copy the token shown once — it will not be displayed again.</li>
      <li>Use the token as the password in <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">docker login</code>.</li>
    </ol>
    <p class="text-sm text-slate-500 dark:text-slate-400">
      Tokens begin with <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">oprk_</code> and the next 7 chars form the visible <em>prefix</em> shown in the token list, so you can identify which one is on which machine.
    </p>
  </div>
<% end %>
```

- [ ] **Step 4: Run, expect PASS, commit**

```bash
bin/rails test test/controllers/help_controller_test.rb
git add app/views/help/show.html.erb test/controllers/help_controller_test.rb
git commit -m "feat(help): document PAT generation flow on /help (B-37)"
```

---

### Task B2 (B-39): HTTP vs HTTPS guidance section

**Files:**
- Modify: `app/views/help/show.html.erb`
- Modify: `test/controllers/help_controller_test.rb`

- [ ] **Step 1: Failing test for HTTP/HTTPS section**

```ruby
test "GET /help renders HTTP vs HTTPS guidance" do
  get "/help"
  assert_response :ok
  assert_select "h2", text: /HTTP vs HTTPS/i
  assert_select "*", text: /insecure-registries/
end
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Insert HTTPS section between Daemon Configuration and Push&Pull**

```erb
<%# HTTP vs HTTPS (B-39) %>
<%= render CardComponent.new(padding: :none, class: "mb-6") do %>
  <div class="p-6">
    <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-100 mb-4">HTTP vs HTTPS</h2>
    <p class="text-base text-slate-700 dark:text-slate-300 mb-3">
      Docker daemon refuses plain HTTP registries by default. You have two options:
    </p>
    <ul class="list-disc list-inside text-sm text-slate-700 dark:text-slate-300 space-y-2 mb-3">
      <li>
        <strong>Development / intranet:</strong> add the host to
        <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">insecure-registries</code>
        in <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">/etc/docker/daemon.json</code> (see Daemon Configuration above).
      </li>
      <li>
        <strong>Production:</strong> terminate TLS at a reverse proxy (Nginx example below) and serve the registry over <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">https://</code>. No client config needed.
      </li>
    </ul>
    <p class="text-sm text-slate-500 dark:text-slate-400">
      Credentials sent to a plain-HTTP registry are visible on the wire. Use HTTPS whenever the registry is reachable beyond a single trusted host.
    </p>
  </div>
<% end %>
```

- [ ] **Step 4: Run, PASS, commit**

```bash
bin/rails test test/controllers/help_controller_test.rb
git add app/views/help/show.html.erb test/controllers/help_controller_test.rb
git commit -m "feat(help): document HTTP vs HTTPS choice (B-39)"
```

---

### Task B3 (B-46): docker login + sign-in workflow walkthrough

**Files:**
- Modify: `app/views/help/show.html.erb`
- Modify: `test/controllers/help_controller_test.rb`

- [ ] **Step 1: Failing test for end-to-end walkthrough**

```ruby
test "GET /help shows sign-in to docker-login walkthrough" do
  get "/help"
  assert_response :ok
  assert_select "h2", text: /Sign in.*docker login/i
  assert_select "*", text: /docker login/
end
```

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Add walkthrough card right after PAT section**

```erb
<%# Sign-in → Token → docker login walkthrough (B-46) %>
<%= render CardComponent.new(padding: :none, class: "mb-6") do %>
  <div class="p-6">
    <h2 class="text-xl font-semibold text-slate-900 dark:text-slate-100 mb-4">Sign in, generate token, docker login</h2>
    <ol class="list-decimal list-inside text-base text-slate-700 dark:text-slate-300 space-y-2 mb-3">
      <li>Visit <%= link_to "/sign_in", sign_in_path, class: "text-blue-600 dark:text-blue-400 hover:underline" %> and complete Google sign-in.</li>
      <li>Open <%= link_to "Settings → Tokens", settings_tokens_path, class: "text-blue-600 dark:text-blue-400 hover:underline" %>, name a token (e.g. <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">laptop-cli</code>), choose an expiry, and create.</li>
      <li>Copy the token immediately — it appears once.</li>
      <li>Run <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">docker login</code>:</li>
    </ol>
    <pre class="bg-slate-100 dark:bg-slate-900 rounded-md p-4 text-sm font-mono text-slate-800 dark:text-blue-300 overflow-x-auto">docker login <%= @registry_host %> -u your.email@company.com -p oprk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx</pre>
    <p class="text-sm text-slate-500 dark:text-slate-400 mt-3">
      Successful login stores credentials in <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">~/.docker/config.json</code>. After that, <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">docker push</code> and <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded text-sm font-mono">docker pull</code> use the saved token automatically.
    </p>
  </div>
<% end %>
```

- [ ] **Step 4: Run, PASS, commit**

```bash
bin/rails test test/controllers/help_controller_test.rb
git add app/views/help/show.html.erb test/controllers/help_controller_test.rb
git commit -m "feat(help): walkthrough sign-in → token → docker login (B-46)"
```

---

### Task B4 (B-38): 401 V2 response body points to /help

V2 `UNAUTHORIZED` 응답 body 에 사용자가 docker CLI / log 에서 볼 수 있는 가이드 포인터 추가. detail 필드에 `help_url` 키.

**Files:**
- Modify: `app/controllers/v2/base_controller.rb` (`render_v2_challenge`)
- Modify: `test/controllers/v2/base_controller_test.rb`

- [ ] **Step 1: Failing test for 401 body containing help URL**

`test/controllers/v2/base_controller_test.rb` 끝에 추가:

```ruby
test "401 response body includes a /help URL pointer" do
  get "/v2/some-repo/manifests/latest"
  assert_response :unauthorized
  body = JSON.parse(response.body)
  detail = body["errors"].first["detail"]
  assert_kind_of Hash, detail
  assert_match %r{/help}, detail["help_url"]
end
```

이 테스트는 `anonymous_pull_enabled` 가 false 인 환경에서 동작해야 함. 테스트 setup 에 추가:

```ruby
setup do
  @prev_anon = Rails.configuration.x.registry.anonymous_pull_enabled
  Rails.configuration.x.registry.anonymous_pull_enabled = false
end

teardown do
  Rails.configuration.x.registry.anonymous_pull_enabled = @prev_anon
end
```

(이미 base_controller_test 내 비슷한 패턴이 있는지 확인 후 적용.)

- [ ] **Step 2: Run, expect FAIL**

```bash
bin/rails test test/controllers/v2/base_controller_test.rb -n "/help URL pointer/"
```

- [ ] **Step 3: Update render_v2_challenge to include help_url**

`app/controllers/v2/base_controller.rb`:

```ruby
def render_v2_challenge
  response.headers["WWW-Authenticate"]                = %(Basic realm="Registry")
  response.headers["Docker-Distribution-API-Version"] = "registry/2.0"
  render json: {
    errors: [ {
      code: "UNAUTHORIZED",
      message: "authentication required — generate a Personal Access Token at /settings/tokens; see /help for setup",
      detail: { help_url: help_path }
    } ]
  }, status: :unauthorized
end
```

(`help_path` 사용 가능 — controller 내 routes 헬퍼.)

- [ ] **Step 4: Run, expect PASS**

```bash
bin/rails test test/controllers/v2/base_controller_test.rb
bin/rails test test/integration/docker_basic_auth_test.rb
```

기존 401 단언이 message 정확히 일치하는 곳이 있을 수 있음 — 깨지면 단언을 substring 매칭으로 완화 (e.g., `assert_match /authentication required/`) 하고 commit 에 포함.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/v2/base_controller.rb test/controllers/v2/base_controller_test.rb
git commit -m "feat(v2): point 401 unauthorized body to /help and /settings/tokens (B-38)"
```

---

### Task B5 (W2-B): Open W2-B PR

```bash
git push -u origin feature/wave2-w2b-help-page-batch
gh pr create --title "Wave2 W2-B: Help page expansion + 401 pointer (B-37, B-38, B-39, B-46)" --body "$(cat <<'EOF'
## Summary
- B-37: /help describes PAT generation flow
- B-39: /help discusses HTTP vs HTTPS choice
- B-46: /help walkthrough sign-in → token → docker login
- B-38: V2 401 body links to /help (docker CLI displays the body on auth failures)

## Test plan
- [ ] help_controller_test green (3 new assertions)
- [ ] v2/base_controller_test green (new help_url assertion)
- [ ] docker_basic_auth_test green (no regression)
EOF
)"
```

---

## Sub-batch W2-C: Test Reinforcement

**Branch:** `feature/wave2-w2c-test-reinforcement`

3 개 test file 독립. 각자 commit.

### Task C1 (B-30): docker login simulation integration test

`/v2/` 베이스 ping 으로 challenge → 같은 path 를 Authorization Basic 으로 재시도 → 200 시퀀스를 검증. 실 docker CLI 가 수행하는 정확한 challenge–response 패턴.

**Files:**
- Modify: `test/integration/docker_basic_auth_test.rb`

- [ ] **Step 1: Append failing test simulating docker login challenge–response**

기존 `DockerBasicAuthTest` 클래스 끝에 추가:

```ruby
# B-30: docker login uses GET /v2/ as the auth probe.
# Real CLI sequence:
#   1. GET /v2/  (no auth) → 401 + WWW-Authenticate: Basic realm="Registry"
#   2. GET /v2/  (Authorization: Basic <b64>) → 200
test "docker login challenge: GET /v2/ no-auth → 401 then Basic-auth → 200" do
  Rails.configuration.x.registry.anonymous_pull_enabled = false

  # Step 1: probe without auth
  get "/v2/"
  assert_response :unauthorized
  assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]

  # Step 2: retry with Basic auth using a valid PAT
  pat = personal_access_tokens(:tonny_cli_active)
  get "/v2/", headers: basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")
  assert_response :ok
  assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
ensure
  Rails.configuration.x.registry.anonymous_pull_enabled = true
end

test "docker login challenge: invalid PAT on /v2/ returns 401 (login fails)" do
  Rails.configuration.x.registry.anonymous_pull_enabled = false
  get "/v2/", headers: basic_auth_for(pat_raw: "oprk_bogus_token", email: "tonny@timberay.com")
  assert_response :unauthorized
ensure
  Rails.configuration.x.registry.anonymous_pull_enabled = true
end
```

- [ ] **Step 2: Run, expect PASS (functionality already exists)**

```bash
bin/rails test test/integration/docker_basic_auth_test.rb
```

기능은 이미 구현되어 있으므로 두 테스트가 곧바로 그린이어야 정상. 만약 FAIL 하면 시나리오 검증 — 실패 메시지를 보고 ANONYMOUS_PULL_ENDPOINTS 에 `["base", "index"]` 가 포함되어 있어 anonymous flag 가 true 일 때 GET /v2/ 가 401 이 안 날 수 있다는 점을 반영 (위에서 이미 비활성화).

- [ ] **Step 3: Commit**

```bash
git add test/integration/docker_basic_auth_test.rb
git commit -m "test(auth): cover docker login challenge–response sequence on /v2/ (B-30)"
```

---

### Task C2 (B-35): Wrong-password V2 integration test

PAT 가 정확히 일치하는 토큰이 아닌 경우 (typo / 잘못된 토큰) 401. 기존 lifecycle 테스트가 expired/revoked 위주이므로 typo 시나리오를 명시.

**Files:**
- Modify: `test/integration/pat_lifecycle_test.rb`

- [ ] **Step 1: Append failing test**

기존 `PatLifecycleTest` 끝에 추가:

```ruby
# B-35: Mistyped password (typo) → 401, last_used_at unchanged on the real PAT.
# Asserts that authentication side-effects only happen on a successful match.
test "B-35: typo password returns 401 and does not update last_used_at" do
  raw = PersonalAccessToken.generate_raw
  pat = create_pat!(raw: raw, name: "typo-test", expires_at: 1.day.from_now)
  pat.update_column(:last_used_at, nil)

  # Drop a single character to simulate a typo
  typo = raw[0..-2]

  post "/v2/#{@repo_name}/blobs/uploads", headers: pat_headers(typo)
  assert_response :unauthorized

  pat.reload
  assert_nil pat.last_used_at,
             "typo'd password must not advance last_used_at"
end
```

`pat_headers` 가 lifecycle test 내에 정의되어 있는지 확인 (`pat_lifecycle_test.rb` 의 helper). 없으면 `basic_auth_for(pat_raw: typo, email: EMAIL)` 패턴으로 대체.

- [ ] **Step 2: Run, expect PASS**

```bash
bin/rails test test/integration/pat_lifecycle_test.rb -n "/typo password/"
```

- [ ] **Step 3: Commit**

```bash
git add test/integration/pat_lifecycle_test.rb
git commit -m "test(auth): typo'd password is rejected without touching last_used_at (B-35)"
```

---

### Task C3 (B-42): Re-tag recovery scenario test

사용자가 실수로 tag 를 삭제 후 같은 manifest 에 같은 이름 tag 를 다시 push → 정상 복구. 데이터 모델이 이를 지원함을 회귀 보호.

**Files:**
- Create: `test/integration/tag_recovery_test.rb`

- [ ] **Step 1: New test file**

```ruby
require "test_helper"

# B-42: Accidentally deleted a tag, then push the same digest+name back.
# Verifies:
#   1. DELETE /v2/<name>/manifests/<reference> succeeds
#   2. PUT  /v2/<name>/manifests/<reference> with same digest restores the tag
#   3. GET  /v2/<name>/manifests/<reference> returns the manifest after recovery
#   4. TagEvent records 'pushed' a second time with a new occurred_at
class TagRecoveryTest < ActionDispatch::IntegrationTest
  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  setup do
    @suffix = SecureRandom.hex(4)
    @repo_name = "recover-#{@suffix}"
    @tag_name  = "v1"

    @storage_dir = Dir.mktmpdir
    @original_storage_path = Rails.configuration.storage_path
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)

    @config_digest = DigestCalculator.compute(config_content)
    @layer_content = SecureRandom.random_bytes(512)
    @layer_digest  = DigestCalculator.compute(@layer_content)

    @manifest_payload = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: config_content.bytesize, digest: @config_digest },
      layers: [
        { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: @layer_content.bytesize, digest: @layer_digest }
      ]
    }.to_json

    @blob_store.put(@config_digest, StringIO.new(config_content))
    @blob_store.put(@layer_digest,  StringIO.new(@layer_content))
    Blob.create!(digest: @config_digest, size: config_content.bytesize)
    Blob.create!(digest: @layer_digest,  size: @layer_content.bytesize)
    Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))

    @auth = basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")
    @manifest_headers = { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(@auth)
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
    Rails.configuration.storage_path = @original_storage_path
  end

  test "deleted tag can be re-pushed with the same digest and recovers" do
    # 1) Initial push
    put "/v2/#{@repo_name}/manifests/#{@tag_name}", params: @manifest_payload, headers: @manifest_headers
    assert_response 201
    digest_after_push = response.headers["Docker-Content-Digest"]

    # 2) Delete the tag
    delete "/v2/#{@repo_name}/manifests/#{@tag_name}", headers: @auth
    assert_response 202

    # 3) GET should now 404
    get "/v2/#{@repo_name}/manifests/#{@tag_name}", headers: @auth
    assert_response :not_found

    # 4) Re-push the SAME manifest payload
    assert_difference -> { TagEvent.where(action: "pushed").count }, +1 do
      put "/v2/#{@repo_name}/manifests/#{@tag_name}", params: @manifest_payload, headers: @manifest_headers
      assert_response 201
    end

    # 5) Re-push digest is identical to original
    assert_equal digest_after_push, response.headers["Docker-Content-Digest"]

    # 6) GET succeeds
    get "/v2/#{@repo_name}/manifests/#{@tag_name}", headers: @auth
    assert_response :ok
  end
end
```

- [ ] **Step 2: Run, expect PASS (functionality exists)**

```bash
bin/rails test test/integration/tag_recovery_test.rb
```

만약 TagEvent action 컬럼 값이 `"pushed"` 가 아니면 (e.g., enum 또는 다른 키) 실제 값으로 교체.

- [ ] **Step 3: Commit**

```bash
git add test/integration/tag_recovery_test.rb
git commit -m "test(tags): cover tag deletion + re-push recovery scenario (B-42)"
```

---

### Task C4 (W2-C): Open W2-C PR

```bash
git push -u origin feature/wave2-w2c-test-reinforcement
gh pr create --title "Wave2 W2-C: Test reinforcement (B-30, B-35, B-42)" --body "$(cat <<'EOF'
## Summary
- B-30: docker login challenge–response sequence on /v2/
- B-35: typo'd PAT rejected without bumping last_used_at
- B-42: tag deletion + re-push recovery

All three are pure test additions — no production code changes.

## Test plan
- [ ] docker_basic_auth_test green
- [ ] pat_lifecycle_test green
- [ ] tag_recovery_test (new) green
- [ ] full suite green
EOF
)"
```

---

## Merge Order

W2-C (test only) → W2-A → W2-B 권장. 충돌 없으니 순서 자유, 단 머지될 때마다 base branch 업데이트 후 다음 PR rebase.

머지 후 main 의 `docs/superpowers/plans/2026-04-29-use-case-followup-plan.md` 의 "Status snapshot" 표를 업데이트:

```
| Pass ✅ | 87 | 87.9% |
| Partial ⚠️ | 6 | 6.1% |
```

---

## Self-Review

**Spec coverage:** 10/10 items mapped to tasks (B-03/A1, B-07/A2, B-22/A3, B-37/B1, B-38/B4, B-39/B2, B-46/B3, B-30/C1, B-35/C2, B-42/C3).

**Placeholder scan:** none — all code blocks are concrete; all test assertions show actual matchers.

**Type consistency:** `prefix` column / `DISPLAY_PREFIX_LENGTH` / `prefix_for` are consistent across model, controller, view, fixture, test. `help_url` key consistent in controller body and test JSON parse.

**Out of scope (carried to Wave 3+):** B-05/13/18/41 UX, B-10/16 nav, B-04 admin, B-43 stimulus, E-37 import. Documented in 2026-04-29 plan.
