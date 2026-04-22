# Tag Immutability Implementation Plan

> **STATUS: SHIPPED (2026-04-22).** All tasks complete and merged via PR #12. See the "Post-ship notes (2026-04-22)" section at the bottom of this file for the one bug caught during E2E review and its fix. This plan is preserved as a historical reference — do NOT execute. See `git log` for per-task commits.

**Goal:** Ship per-repository tag protection policy (`none` / `semver` / `all_except_latest` / `custom_regex`) that blocks overwrite + delete of protected tags across Registry PUT, Registry DELETE, Web UI DELETE, and the retention job — while preserving idempotent re-push for CI retry safety.

**Architecture:** Add two columns (`tag_protection_policy`, `tag_protection_pattern`) to `repositories`. Centralize enforcement in a single `Repository#enforce_tag_protection!(tag_name, new_digest:)` method that the four call sites (push, two deletes, retention) share. Raise `Registry::TagProtected` with a custom `detail` payload that `V2::BaseController#rescue_from` renders as HTTP 409 + Docker Registry envelope with code `DENIED`. Protection check runs at the ENTRY of `ManifestProcessor#call` inside `repository.with_lock { ... }` to prevent orphan manifest/blob-ref leakage AND concurrent-push races.

**Tech Stack:** Rails 8.1 (Ruby 3.4.8), SQLite, RSpec (project's actual framework, despite CLAUDE.md's Minitest mention), Stimulus (pure JS, no TypeScript), TailwindCSS, Playwright for E2E, bash `test/integration/docker_cli_test.sh` for Docker CLI integration.

**Source spec:** `docs/superpowers/specs/2026-04-22-tag-immutability-design.md` (see `## GSTACK REVIEW REPORT` section for all 13 locked decisions from the eng review and outside-voice pass).

---

## Pre-flight

- [x] **Step 0: Ensure clean working tree**

```bash
git status
```
Expected: clean (no staged or unstaged changes). If dirty, stash or commit first.

- [x] **Step 1: Baseline tests green**

```bash
bin/rails db:test:prepare
bundle exec rspec --fail-fast
```
Expected: PASS for all existing specs. If any fail on baseline, fix before starting (they are not this plan's responsibility, but they must not mask new failures).

---

## Task 1: Tidy — upgrade `RepositoriesController#repository_params` to `params.expect`

**Why this is a separate commit:** Structural change (Rails 8 preferred API). Behavior identical. Isolates the behavior-change commit that follows (Task 9).

**Files:**
- Modify: `app/controllers/repositories_controller.rb:45-47`

- [x] **Step 1: Read the current method**

Current content (line 45-47):

```ruby
def repository_params
  params.require(:repository).permit(:description, :maintainer)
end
```

- [x] **Step 2: Replace with `params.expect`**

Replacement:

```ruby
def repository_params
  params.expect(repository: [:description, :maintainer])
end
```

- [x] **Step 3: Run repository request spec to confirm no regression**

```bash
bundle exec rspec spec/requests/repositories_spec.rb
```
Expected: PASS (all existing request specs still green).

- [x] **Step 4: Commit**

```bash
git add app/controllers/repositories_controller.rb
git commit -m "refactor: use params.expect for repository strong params"
```

---

## Task 2: Add `Registry::TagProtected` error class with `detail` payload

**Files:**
- Modify: `app/errors/registry.rb`
- Test: `spec/errors/registry_spec.rb`

- [x] **Step 1: Write failing test appending to existing spec**

Append to `spec/errors/registry_spec.rb` inside `RSpec.describe Registry do ... end`:

```ruby
  describe Registry::TagProtected do
    it 'inherits from Registry::Error' do
      expect(described_class.new(tag: 'v1.0.0', policy: 'semver')).to be_a(Registry::Error)
    end

    it 'builds a default message from tag and policy' do
      error = described_class.new(tag: 'v1.0.0', policy: 'semver')
      expect(error.message).to eq("tag 'v1.0.0' is protected by immutability policy 'semver'")
    end

    it 'accepts an explicit message override' do
      error = described_class.new(tag: 'v1.0.0', policy: 'semver', message: 'custom')
      expect(error.message).to eq('custom')
    end

    it 'exposes detail hash for Docker Registry error envelope' do
      error = described_class.new(tag: 'v1.0.0', policy: 'semver')
      expect(error.detail).to eq(tag: 'v1.0.0', policy: 'semver')
    end
  end
```

- [x] **Step 2: Run the test — verify it fails**

```bash
bundle exec rspec spec/errors/registry_spec.rb
```
Expected: FAIL with `uninitialized constant Registry::TagProtected`.

- [x] **Step 3: Implement the error class**

Replace the body of `app/errors/registry.rb` with:

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

  class TagProtected < Error
    attr_reader :detail

    def initialize(tag:, policy:, message: nil)
      @detail = { tag: tag, policy: policy }
      super(message || "tag '#{tag}' is protected by immutability policy '#{policy}'")
    end
  end
end
```

- [x] **Step 4: Run the test — verify it passes**

```bash
bundle exec rspec spec/errors/registry_spec.rb
```
Expected: PASS (all existing Registry tests + 4 new TagProtected tests).

- [x] **Step 5: Commit**

```bash
git add app/errors/registry.rb spec/errors/registry_spec.rb
git commit -m "feat: add Registry::TagProtected error with detail payload"
```

---

## Task 3: Wire `rescue_from Registry::TagProtected` in `V2::BaseController`

**Files:**
- Modify: `app/controllers/v2/base_controller.rb`
- Test: `spec/requests/v2/base_spec.rb`

- [x] **Step 1: Write failing request spec**

Append to `spec/requests/v2/base_spec.rb` (create `RSpec.describe 'V2 TagProtected handling', type: :request do ... end` block if the file doesn't already have a matching context):

```ruby
RSpec.describe 'V2 TagProtected error handling', type: :request do
  # Simulate by mounting a tiny route that raises inside a controller extending V2::BaseController.
  # Instead we exercise the real path via V2::ManifestsController in Task 7.
  # This spec locks the error-to-response mapping at the controller layer.

  controller(V2::BaseController) do
    def trigger
      raise Registry::TagProtected.new(tag: 'v1.0.0', policy: 'semver')
    end
  end

  before { routes.draw { get 'trigger' => 'v2/base#trigger' } }

  it 'returns 409 Conflict' do
    get :trigger
    expect(response).to have_http_status(:conflict)
  end

  it 'renders Docker Registry error envelope with DENIED code' do
    get :trigger
    body = JSON.parse(response.body)
    expect(body['errors'].first).to include(
      'code' => 'DENIED',
      'message' => "tag 'v1.0.0' is protected by immutability policy 'semver'",
      'detail' => { 'tag' => 'v1.0.0', 'policy' => 'semver' }
    )
  end

  it 'includes Docker-Distribution-API-Version header on 409' do
    get :trigger
    expect(response.headers['Docker-Distribution-API-Version']).to eq('registry/2.0')
  end
end
```

Note: this uses RSpec's `controller(...)` anonymous controller pattern which requires `type: :controller`. Because our class hierarchy uses `ActionController::API`, add this at the top of the `RSpec.describe` block instead:

```ruby
RSpec.describe V2::BaseController, type: :controller do
  controller(V2::BaseController) do
    def trigger
      raise Registry::TagProtected.new(tag: 'v1.0.0', policy: 'semver')
    end
  end

  before { routes.draw { get 'trigger' => 'v2/base#trigger' } }

  it 'returns 409 Conflict' do
    get :trigger
    expect(response).to have_http_status(:conflict)
  end

  it 'renders Docker Registry error envelope with DENIED code' do
    get :trigger
    body = JSON.parse(response.body)
    expect(body['errors'].first).to include(
      'code' => 'DENIED',
      'message' => "tag 'v1.0.0' is protected by immutability policy 'semver'",
      'detail' => { 'tag' => 'v1.0.0', 'policy' => 'semver' }
    )
  end

  it 'includes Docker-Distribution-API-Version header on 409' do
    get :trigger
    expect(response.headers['Docker-Distribution-API-Version']).to eq('registry/2.0')
  end
end
```

- [x] **Step 2: Run the test — verify it fails**

```bash
bundle exec rspec spec/requests/v2/base_spec.rb
```
Expected: FAIL — `Registry::TagProtected` is raised and not rescued; Rails renders a generic 500.

- [x] **Step 3: Add the rescue_from**

Edit `app/controllers/v2/base_controller.rb`. Find the rescue_from block (around line 4-10) and add inside it:

```ruby
  rescue_from Registry::TagProtected, with: -> (e) { render_error('DENIED', e.message, 409, detail: e.detail) }
```

Place this line after `rescue_from Registry::Unsupported` so the full block reads:

```ruby
  rescue_from Registry::BlobUnknown, with: -> (e) { render_error('BLOB_UNKNOWN', e.message, 404) }
  rescue_from Registry::BlobUploadUnknown, with: -> (e) { render_error('BLOB_UPLOAD_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestUnknown, with: -> (e) { render_error('MANIFEST_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestInvalid, with: -> (e) { render_error('MANIFEST_INVALID', e.message, 400) }
  rescue_from Registry::NameUnknown, with: -> (e) { render_error('NAME_UNKNOWN', e.message, 404) }
  rescue_from Registry::DigestMismatch, with: -> (e) { render_error('DIGEST_INVALID', e.message, 400) }
  rescue_from Registry::Unsupported, with: -> (e) { render_error('UNSUPPORTED', e.message, 415) }
  rescue_from Registry::TagProtected, with: -> (e) { render_error('DENIED', e.message, 409, detail: e.detail) }
```

- [x] **Step 4: Run the test — verify it passes**

```bash
bundle exec rspec spec/requests/v2/base_spec.rb
```
Expected: PASS (existing tests + 3 new TagProtected tests).

- [x] **Step 5: Commit**

```bash
git add app/controllers/v2/base_controller.rb spec/requests/v2/base_spec.rb
git commit -m "feat: rescue Registry::TagProtected as 409 DENIED in V2 base"
```

---

## Task 4: Migration — add `tag_protection_policy` + `tag_protection_pattern` columns

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_tag_protection_to_repositories.rb`
- Modify: `db/schema.rb` (regenerated automatically)

- [x] **Step 1: Generate migration timestamp**

```bash
bin/rails generate migration AddTagProtectionToRepositories
```

- [x] **Step 2: Write the migration body**

Open the newly created `db/migrate/YYYYMMDDHHMMSS_add_tag_protection_to_repositories.rb` and replace the body with:

```ruby
class AddTagProtectionToRepositories < ActiveRecord::Migration[8.1]
  # Rolling this migration back drops `tag_protection_policy` and
  # `tag_protection_pattern`, which PERMANENTLY discards every repo's
  # configured protection policy. See TODOS.md P3 entry for a safer
  # `IrreversibleMigration` guard to add once this feature is live.
  def change
    add_column :repositories, :tag_protection_policy, :string, null: false, default: "none"
    add_column :repositories, :tag_protection_pattern, :string
  end
end
```

- [x] **Step 3: Run the migration**

```bash
bin/rails db:migrate
bin/rails db:test:prepare
```
Expected: migration completes; `schema.rb` now shows the two columns.

- [x] **Step 4: Confirm baseline specs still green**

```bash
bundle exec rspec --fail-fast
```
Expected: PASS (columns are additive; nothing existing references them yet).

- [x] **Step 5: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "feat: add tag_protection_policy and tag_protection_pattern columns"
```

---

## Task 5: `Repository#tag_protected?` — enum + memoized regex + four policies

**Files:**
- Modify: `app/models/repository.rb`
- Test: `spec/models/repository_spec.rb`

- [x] **Step 1: Write failing unit specs for all four policies**

Append inside `RSpec.describe Repository, type: :model do ... end` in `spec/models/repository_spec.rb`:

```ruby
  describe '#tag_protected?' do
    let(:repo) { Repository.create!(name: 'example') }

    context 'when policy is none (default)' do
      it 'returns false for any tag name' do
        expect(repo.tag_protected?('v1.0.0')).to be false
        expect(repo.tag_protected?('latest')).to be false
        expect(repo.tag_protected?('anything')).to be false
      end
    end

    context 'when policy is semver' do
      before { repo.update!(tag_protection_policy: 'semver') }

      it 'protects v-prefixed semver' do
        expect(repo.tag_protected?('v1.2.3')).to be true
      end

      it 'protects bare semver' do
        expect(repo.tag_protected?('1.2.3')).to be true
      end

      it 'protects semver with pre-release' do
        expect(repo.tag_protected?('1.2.3-rc1')).to be true
      end

      it 'protects semver with build metadata' do
        expect(repo.tag_protected?('1.2.3+build.5')).to be true
      end

      it 'does NOT protect latest' do
        expect(repo.tag_protected?('latest')).to be false
      end

      it 'does NOT protect partial versions' do
        expect(repo.tag_protected?('v1.2')).to be false
      end

      it 'does NOT protect branch names' do
        expect(repo.tag_protected?('main')).to be false
      end
    end

    context 'when policy is all_except_latest' do
      before { repo.update!(tag_protection_policy: 'all_except_latest') }

      it 'does NOT protect latest' do
        expect(repo.tag_protected?('latest')).to be false
      end

      it 'protects everything else (including other floating names)' do
        expect(repo.tag_protected?('v1.0.0')).to be true
        expect(repo.tag_protected?('main')).to be true
        expect(repo.tag_protected?('develop')).to be true
        expect(repo.tag_protected?('anything')).to be true
      end
    end

    context 'when policy is custom_regex' do
      before do
        repo.update!(tag_protection_policy: 'custom_regex', tag_protection_pattern: '^release-\d+$')
      end

      it 'protects names matching the pattern' do
        expect(repo.tag_protected?('release-1')).to be true
        expect(repo.tag_protected?('release-42')).to be true
      end

      it 'does NOT protect non-matching names' do
        expect(repo.tag_protected?('release-1a')).to be false
        expect(repo.tag_protected?('v1.0.0')).to be false
      end
    end
  end

  describe 'tag_protection_pattern validation' do
    it 'requires pattern when policy is custom_regex' do
      repo = Repository.new(name: 'x', tag_protection_policy: 'custom_regex', tag_protection_pattern: nil)
      expect(repo).not_to be_valid
      expect(repo.errors[:tag_protection_pattern]).to include("can't be blank")
    end

    it 'rejects invalid regex' do
      repo = Repository.new(name: 'x', tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed')
      expect(repo).not_to be_valid
      expect(repo.errors[:tag_protection_pattern].first).to match(/is not a valid regex/)
    end

    it 'does NOT require pattern when policy is not custom_regex' do
      repo = Repository.new(name: 'x', tag_protection_policy: 'semver', tag_protection_pattern: nil)
      expect(repo).to be_valid
    end
  end

  describe 'before_save clears pattern when policy is not custom_regex' do
    it 'nullifies pattern when policy transitions to semver' do
      repo = Repository.create!(name: 'x', tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      repo.update!(tag_protection_policy: 'semver')
      expect(repo.reload.tag_protection_pattern).to be_nil
    end

    it 'keeps pattern when policy stays custom_regex' do
      repo = Repository.create!(name: 'y', tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      repo.update!(tag_protection_pattern: '^release-\d+$')
      expect(repo.reload.tag_protection_pattern).to eq('^release-\d+$')
    end
  end
```

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/models/repository_spec.rb
```
Expected: FAIL — `tag_protected?` undefined, enum undefined, no validations.

- [x] **Step 3: Implement the model additions**

Replace the body of `app/models/repository.rb` with:

```ruby
class Repository < ApplicationRecord
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

  def tag_protected?(tag_name)
    case tag_protection_policy
    when "none"              then false
    when "semver"            then tag_name.match?(SEMVER_PATTERN)
    when "all_except_latest" then tag_name != "latest"
    when "custom_regex"      then tag_name.match?(protection_regex)
    end
  end

  private

  def protection_regex
    @protection_regex ||= Regexp.new(tag_protection_pattern)
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

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/models/repository_spec.rb
```
Expected: PASS (original association/validation tests + 14 new tests).

- [x] **Step 5: Commit**

```bash
git add app/models/repository.rb spec/models/repository_spec.rb
git commit -m "feat: add tag_protected? with four-policy enum on Repository"
```

---

## Task 6: `Repository#enforce_tag_protection!` — DRY helper for all call sites

**Files:**
- Modify: `app/models/repository.rb`
- Test: `spec/models/repository_spec.rb`

- [x] **Step 1: Write failing spec**

Append inside `RSpec.describe Repository, type: :model do ... end`:

```ruby
  describe '#enforce_tag_protection!' do
    let(:repo) { Repository.create!(name: 'example', tag_protection_policy: 'semver') }
    let(:manifest) do
      m = repo.manifests.create!(
        digest: 'sha256:existing', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
        payload: '{}', size: 2
      )
      repo.tags.create!(name: 'v1.0.0', manifest: m)
      m
    end
    before { manifest } # force setup

    context 'when tag is not protected' do
      it 'returns nil and does not raise' do
        expect(repo.enforce_tag_protection!('latest')).to be_nil
      end
    end

    context 'when tag is protected and no existing tag' do
      it 'raises Registry::TagProtected' do
        expect { repo.enforce_tag_protection!('v2.0.0') }
          .to raise_error(Registry::TagProtected) { |e|
            expect(e.detail).to eq(tag: 'v2.0.0', policy: 'semver')
          }
      end
    end

    context 'when tag is protected and existing digest differs' do
      it 'raises Registry::TagProtected' do
        expect { repo.enforce_tag_protection!('v1.0.0', new_digest: 'sha256:different') }
          .to raise_error(Registry::TagProtected)
      end
    end

    context 'when tag is protected and existing digest matches (idempotent)' do
      it 'does not raise' do
        expect { repo.enforce_tag_protection!('v1.0.0', new_digest: 'sha256:existing') }.not_to raise_error
      end
    end

    context 'when called with an already-loaded tag (to avoid duplicate query)' do
      it 'accepts existing_tag keyword and uses it' do
        tag = repo.tags.find_by(name: 'v1.0.0')
        expect {
          repo.enforce_tag_protection!('v1.0.0', new_digest: 'sha256:existing', existing_tag: tag)
        }.not_to raise_error
      end
    end
  end
```

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/models/repository_spec.rb
```
Expected: FAIL — `enforce_tag_protection!` undefined.

- [x] **Step 3: Implement the method**

In `app/models/repository.rb`, add this method just after `tag_protected?`:

```ruby
  # Raises Registry::TagProtected when the tag is protected and the operation
  # would mutate it. Used by ManifestProcessor (PUT), TagsController#destroy
  # (Web UI DELETE), V2::ManifestsController#destroy (Registry DELETE), and
  # EnforceRetentionPolicyJob (retention skip).
  #
  # @param tag_name [String]
  # @param new_digest [String, nil] for PUT, the digest being pushed; same
  #   digest as existing tag is idempotent (CI retry safety) and does not raise.
  # @param existing_tag [Tag, nil] pass an already-loaded Tag to avoid a
  #   duplicate `tags.find_by(name:)` query when the caller already has it.
  def enforce_tag_protection!(tag_name, new_digest: nil, existing_tag: :unset)
    return unless tag_protected?(tag_name)

    if new_digest
      current = existing_tag.equal?(:unset) ? tags.find_by(name: tag_name) : existing_tag
      return if current && current.manifest.digest == new_digest
    end

    raise Registry::TagProtected.new(tag: tag_name, policy: tag_protection_policy)
  end
```

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/models/repository_spec.rb
```
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/models/repository.rb spec/models/repository_spec.rb
git commit -m "feat: add Repository#enforce_tag_protection! helper for all call sites"
```

---

## Task 7: `ManifestProcessor` — move check to entry, wrap in `with_lock`

**Files:**
- Modify: `app/services/manifest_processor.rb`
- Test: `spec/services/manifest_processor_spec.rb`

- [x] **Step 1: Write failing specs (including REGRESSION guards)**

Append to `RSpec.describe ManifestProcessor do ... end` in `spec/services/manifest_processor_spec.rb`:

```ruby
  describe '#call with tag protection' do
    let!(:repo) do
      # Create with initial manifest and tag, then turn on protection.
      r = Repository.create!(name: 'test-repo')
      processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
      r.update!(tag_protection_policy: 'semver')
      r.reload
    end

    context 'same digest re-push (idempotent)' do
      it 'succeeds' do
        expect {
          processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
        }.not_to raise_error
      end
    end

    context 'different digest push on protected tag' do
      let(:different_manifest_json) do
        new_layer = SecureRandom.random_bytes(512)
        new_layer_digest = DigestCalculator.compute(new_layer)
        blob_store.put(new_layer_digest, StringIO.new(new_layer))
        {
          schemaVersion: 2,
          mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
          config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
          layers: [
            { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: new_layer.bytesize, digest: new_layer_digest }
          ]
        }.to_json
      end

      it 'raises Registry::TagProtected' do
        expect {
          processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', different_manifest_json)
        }.to raise_error(Registry::TagProtected)
      end

      # REGRESSION guards for decision 1-A (check at entry, not inside assign_tag!)
      it 'does NOT create a new manifest row' do
        expect {
          begin
            processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', different_manifest_json)
          rescue Registry::TagProtected
          end
        }.not_to change { Manifest.count }
      end

      it 'does NOT increment blob references_count' do
        config_blob = Blob.find_by(digest: config_digest)
        before_refs = config_blob.references_count
        begin
          processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', different_manifest_json)
        rescue Registry::TagProtected
        end
        expect(config_blob.reload.references_count).to eq(before_refs)
      end
    end

    context 'unprotected tag (latest with semver policy)' do
      it 'permits push (latest not semver)' do
        expect {
          processor.call('test-repo', 'latest', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
        }.not_to raise_error
      end
    end

    context 'digest reference (sha256: prefix, not a tag mutation)' do
      it 'bypasses protection check' do
        r = Repository.find_by!(name: 'test-repo')
        r.update!(tag_protection_policy: 'all_except_latest')
        expect {
          processor.call('test-repo', 'sha256:dummy-ignored-anyway', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
        }.not_to raise_error
      end
    end
  end
```

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/services/manifest_processor_spec.rb
```
Expected: FAIL — protection check not wired in yet.

- [x] **Step 3: Rewrite `ManifestProcessor#call` with entry check + `with_lock`**

Replace the body of `app/services/manifest_processor.rb` with:

```ruby
class ManifestProcessor
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(repo_name, reference, content_type, payload)
    parsed = JSON.parse(payload)
    validate_schema!(parsed)

    config_digest = parsed['config']['digest']
    raise Registry::ManifestInvalid, 'config blob not found' unless @blob_store.exists?(config_digest)

    layer_digests = parsed['layers'].map { |l| l['digest'] }
    layer_digests.each do |d|
      raise Registry::ManifestInvalid, "layer blob not found: #{d}" unless @blob_store.exists?(d)
    end

    repository = Repository.find_or_create_by!(name: repo_name)
    digest = DigestCalculator.compute(payload)

    tag_name = reference if reference.present? && !reference.start_with?('sha256:')

    # Decision 1-A + OV-1: enforce tag protection at the ENTRY of the service,
    # inside a row-lock on the repository, BEFORE any manifest.save! or blob
    # references_count increments. This prevents orphan manifest rows,
    # leaked blob refs, and concurrent-push races on the same tag.
    repository.with_lock do
      if tag_name
        existing_tag = repository.tags.find_by(name: tag_name)
        repository.enforce_tag_protection!(tag_name, new_digest: digest, existing_tag: existing_tag)
      end

      manifest = repository.manifests.find_or_initialize_by(digest: digest)
      config_data = extract_config(config_digest)

      manifest.assign_attributes(
        media_type: content_type,
        payload: payload,
        size: payload.bytesize,
        config_digest: config_digest,
        architecture: config_data[:architecture],
        os: config_data[:os],
        docker_config: config_data[:config_json]
      )
      manifest.save!

      create_layers!(manifest, parsed['layers'])

      assign_tag!(repository, tag_name, manifest) if tag_name

      update_repository_size!(repository)

      manifest
    end
  end

  private

  def validate_schema!(parsed)
    unless parsed['schemaVersion'] == 2
      raise Registry::ManifestInvalid, 'unsupported schema version'
    end

    unless parsed['config'].is_a?(Hash) && parsed['config']['digest'].present?
      raise Registry::ManifestInvalid, 'missing config'
    end

    unless parsed['layers'].is_a?(Array)
      raise Registry::ManifestInvalid, 'missing layers'
    end
  end

  def extract_config(config_digest)
    config_io = @blob_store.get(config_digest)
    config_json = config_io.read
    config_io.close
    parsed = JSON.parse(config_json)

    {
      architecture: parsed['architecture'],
      os: parsed['os'],
      config_json: (parsed['config'] || {}).to_json
    }
  rescue JSON::ParserError
    { architecture: nil, os: nil, config_json: nil }
  end

  def create_layers!(manifest, layers_data)
    manifest.layers.destroy_all

    layers_data.each_with_index do |layer_data, index|
      blob = Blob.find_or_create_by!(digest: layer_data['digest']) do |b|
        b.size = layer_data['size']
        b.content_type = layer_data['mediaType']
      end
      blob.increment!(:references_count)

      Layer.create!(manifest: manifest, blob: blob, position: index)
    end
  end

  def assign_tag!(repository, tag_name, manifest)
    existing_tag = repository.tags.find_by(name: tag_name)

    if existing_tag
      old_digest = existing_tag.manifest.digest
      if old_digest != manifest.digest
        existing_tag.update!(manifest: manifest)
        TagEvent.create!(
          repository: repository,
          tag_name: tag_name,
          action: 'update',
          previous_digest: old_digest,
          new_digest: manifest.digest,
          actor: 'anonymous',
          occurred_at: Time.current
        )
      end
    else
      Tag.create!(repository: repository, name: tag_name, manifest: manifest)
      TagEvent.create!(
        repository: repository,
        tag_name: tag_name,
        action: 'create',
        new_digest: manifest.digest,
        actor: 'anonymous',
        occurred_at: Time.current
      )
    end
  end

  def update_repository_size!(repository)
    total = repository.manifests.joins(layers: :blob).sum('blobs.size')
    repository.update_column(:total_size, total)
  end
end
```

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/services/manifest_processor_spec.rb
```
Expected: PASS — all original specs still green, 5 new protection specs green, REGRESSION guards green.

- [x] **Step 5: Commit**

```bash
git add app/services/manifest_processor.rb spec/services/manifest_processor_spec.rb
git commit -m "feat: enforce tag protection at ManifestProcessor entry with row lock"
```

---

## Task 8: Web UI — `TagsController#destroy` gate

**Files:**
- Modify: `app/controllers/tags_controller.rb`
- Test: `spec/requests/tags_spec.rb` (create if missing)

- [x] **Step 1: Write failing request spec**

Create or append to `spec/requests/tags_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Tags', type: :request do
  let!(:repo) { Repository.create!(name: 'example') }
  let!(:manifest) do
    repo.manifests.create!(
      digest: 'sha256:abc',
      media_type: 'application/vnd.docker.distribution.manifest.v2+json',
      payload: '{}', size: 2
    )
  end
  let!(:tag) { repo.tags.create!(name: 'v1.0.0', manifest: manifest) }

  describe 'DELETE /repositories/:name/tags/:name' do
    context 'when tag is not protected' do
      it 'deletes the tag and redirects' do
        delete "/repositories/#{repo.name}/tags/#{tag.name}"
        expect(response).to redirect_to(repository_path(repo.name))
        expect(Tag.find_by(id: tag.id)).to be_nil
      end
    end

    context 'when tag is protected by semver policy' do
      before { repo.update!(tag_protection_policy: 'semver') }

      it 'does NOT delete the tag' do
        delete "/repositories/#{repo.name}/tags/#{tag.name}"
        expect(Tag.find_by(id: tag.id)).to be_present
      end

      it 'redirects to the repository page with a flash error' do
        delete "/repositories/#{repo.name}/tags/#{tag.name}"
        expect(response).to redirect_to(repository_path(repo.name))
        expect(flash[:alert]).to include("protected")
        expect(flash[:alert]).to include("semver")
      end

      it 'does NOT record a tag_event' do
        expect {
          delete "/repositories/#{repo.name}/tags/#{tag.name}"
        }.not_to change { TagEvent.count }
      end
    end
  end
end
```

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/requests/tags_spec.rb
```
Expected: FAIL — current controller destroys tag unconditionally.

- [x] **Step 3: Gate the destroy action**

Replace the body of `app/controllers/tags_controller.rb` with:

```ruby
class TagsController < ApplicationController
  before_action :set_repository
  before_action :set_tag, only: [:show, :destroy, :history]

  def show
    @manifest = @tag.manifest
    @layers = @manifest.layers.includes(:blob).order(:position)
  end

  def destroy
    @repository.enforce_tag_protection!(@tag.name)

    TagEvent.create!(
      repository: @repository,
      tag_name: @tag.name,
      action: 'delete',
      previous_digest: @tag.manifest.digest,
      actor: 'anonymous',
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
end
```

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/requests/tags_spec.rb
```
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/controllers/tags_controller.rb spec/requests/tags_spec.rb
git commit -m "feat: block protected tag deletion via Web UI"
```

---

## Task 9: V2 Registry — `V2::ManifestsController#destroy` gate

**Files:**
- Modify: `app/controllers/v2/manifests_controller.rb`
- Test: `spec/requests/v2/manifests_spec.rb`

- [x] **Step 1: Write failing request spec**

Append inside the existing `RSpec.describe 'V2 manifests', type: :request do ... end` block in `spec/requests/v2/manifests_spec.rb`:

```ruby
  describe 'DELETE /v2/:name/manifests/:reference (tag protection)' do
    let!(:repo) { Repository.create!(name: 'example') }
    let!(:manifest) do
      repo.manifests.create!(
        digest: 'sha256:abc',
        media_type: 'application/vnd.docker.distribution.manifest.v2+json',
        payload: '{}', size: 2
      )
    end
    let!(:tag) { repo.tags.create!(name: 'v1.0.0', manifest: manifest) }

    context 'when any connected tag is protected' do
      before { repo.update!(tag_protection_policy: 'semver') }

      it 'returns 409 Conflict with DENIED envelope (digest reference)' do
        delete "/v2/#{repo.name}/manifests/#{manifest.digest}"
        expect(response).to have_http_status(:conflict)
        body = JSON.parse(response.body)
        expect(body['errors'].first).to include('code' => 'DENIED')
        expect(body['errors'].first['detail']).to include('tag' => 'v1.0.0', 'policy' => 'semver')
      end

      it 'returns 409 even when called with tag reference (decision 1-B)' do
        delete "/v2/#{repo.name}/manifests/v1.0.0"
        expect(response).to have_http_status(:conflict)
      end

      it 'does NOT destroy the manifest' do
        delete "/v2/#{repo.name}/manifests/#{manifest.digest}"
        expect(Manifest.find_by(id: manifest.id)).to be_present
      end
    end

    context 'when no connected tag is protected' do
      it 'returns 202 Accepted and destroys the manifest' do
        delete "/v2/#{repo.name}/manifests/#{manifest.digest}"
        expect(response).to have_http_status(:accepted)
      end
    end
  end
```

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/requests/v2/manifests_spec.rb
```
Expected: FAIL — destroy action has no protection check.

- [x] **Step 3: Gate the destroy action**

In `app/controllers/v2/manifests_controller.rb`, replace the `destroy` method (currently lines 43-66) with:

```ruby
  def destroy
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

    # Decision 1-B: whether reference is a digest or a tag name, if ANY tag
    # connected to this manifest is protected, block the delete.
    manifest.tags.each { |tag| repository.enforce_tag_protection!(tag.name) }

    manifest.tags.each do |tag|
      TagEvent.create!(
        repository: repository,
        tag_name: tag.name,
        action: 'delete',
        previous_digest: manifest.digest,
        actor: 'anonymous',
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
```

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/requests/v2/manifests_spec.rb
```
Expected: PASS (existing destroy specs still green + 4 new protection specs).

- [x] **Step 5: Commit**

```bash
git add app/controllers/v2/manifests_controller.rb spec/requests/v2/manifests_spec.rb
git commit -m "feat: block protected manifest deletion via Registry V2 DELETE"
```

---

## Task 10: `EnforceRetentionPolicyJob` — skip protected tags (OV-2 P0)

**Files:**
- Modify: `app/jobs/enforce_retention_policy_job.rb`
- Test: `spec/jobs/enforce_retention_policy_job_spec.rb`

- [x] **Step 1: Write failing spec**

Create or replace `spec/jobs/enforce_retention_policy_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe EnforceRetentionPolicyJob do
  let!(:repo) { Repository.create!(name: 'example') }
  let!(:manifest) do
    repo.manifests.create!(
      digest: 'sha256:abc',
      media_type: 'application/vnd.docker.distribution.manifest.v2+json',
      payload: '{}', size: 2,
      last_pulled_at: 200.days.ago, pull_count: 0
    )
  end
  let!(:v1_tag) { repo.tags.create!(name: 'v1.0.0', manifest: manifest) }
  let!(:latest_tag) { repo.tags.create!(name: 'latest', manifest: manifest) }

  around do |ex|
    ClimateControl.modify(
      RETENTION_ENABLED: 'true',
      RETENTION_DAYS_WITHOUT_PULL: '90',
      RETENTION_MIN_PULL_COUNT: '5',
      RETENTION_PROTECT_LATEST: 'true'
    ) { ex.run }
  end

  context 'when retention is enabled and tags are stale' do
    it 'deletes stale v1.0.0 tag on a repo with no protection' do
      described_class.perform_now
      expect(Tag.find_by(id: v1_tag.id)).to be_nil
    end

    it 'preserves latest tag regardless of protection (existing behavior)' do
      described_class.perform_now
      expect(Tag.find_by(id: latest_tag.id)).to be_present
    end
  end

  context 'when repo has tag_protection_policy=semver' do
    before { repo.update!(tag_protection_policy: 'semver') }

    it 'does NOT delete the protected v1.0.0 tag' do
      described_class.perform_now
      expect(Tag.find_by(id: v1_tag.id)).to be_present
    end

    it 'does NOT record a tag_event for the skipped protected tag' do
      expect { described_class.perform_now }.not_to change { TagEvent.where(tag_name: 'v1.0.0').count }
    end

    it 'still preserves latest (not a semver tag, so outside policy anyway)' do
      described_class.perform_now
      expect(Tag.find_by(id: latest_tag.id)).to be_present
    end
  end

  context 'when repo has tag_protection_policy=all_except_latest' do
    before { repo.update!(tag_protection_policy: 'all_except_latest') }

    it 'preserves v1.0.0 (protected by policy)' do
      described_class.perform_now
      expect(Tag.find_by(id: v1_tag.id)).to be_present
    end
  end
end
```

Note: if `climate_control` gem is not in the Gemfile, replace `around do |ex| ClimateControl.modify(...) { ex.run } end` with:

```ruby
  before do
    stub_const('ENV', ENV.to_h.merge(
      'RETENTION_ENABLED' => 'true',
      'RETENTION_DAYS_WITHOUT_PULL' => '90',
      'RETENTION_MIN_PULL_COUNT' => '5',
      'RETENTION_PROTECT_LATEST' => 'true'
    ))
  end
```

Check the Gemfile first:

```bash
grep -q "climate_control" Gemfile && echo "USE_CLIMATE" || echo "USE_STUB"
```

Use the matching variant.

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/jobs/enforce_retention_policy_job_spec.rb
```
Expected: FAIL — retention job currently deletes protected tags.

- [x] **Step 3: Add protection skip**

Replace the body of `app/jobs/enforce_retention_policy_job.rb` with:

```ruby
class EnforceRetentionPolicyJob < ApplicationJob
  queue_as :default

  def perform
    return unless retention_enabled?

    days = ENV.fetch('RETENTION_DAYS_WITHOUT_PULL', 90).to_i
    min_pulls = ENV.fetch('RETENTION_MIN_PULL_COUNT', 5).to_i
    protect_latest = ENV.fetch('RETENTION_PROTECT_LATEST', 'true') == 'true'

    threshold = days.days.ago

    stale_manifests = Manifest
      .where('last_pulled_at < ? OR last_pulled_at IS NULL', threshold)
      .where('pull_count < ?', min_pulls)

    stale_manifests.find_each do |manifest|
      scope = manifest.tags
      scope = scope.where.not(name: 'latest') if protect_latest

      scope.find_each do |tag|
        # OV-2 (P0): do not touch tags protected by repo policy.
        next if manifest.repository.tag_protected?(tag.name)

        TagEvent.create!(
          repository: manifest.repository,
          tag_name: tag.name,
          action: 'delete',
          previous_digest: manifest.digest,
          actor: 'retention-policy',
          occurred_at: Time.current
        )
        tag.destroy!
      end
    end
  end

  private

  def retention_enabled?
    ENV.fetch('RETENTION_ENABLED', 'false') == 'true'
  end
end
```

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/jobs/enforce_retention_policy_job_spec.rb
```
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/jobs/enforce_retention_policy_job.rb spec/jobs/enforce_retention_policy_job_spec.rb
git commit -m "fix: EnforceRetentionPolicyJob skips protected tags"
```

---

## Task 11: `RepositoriesController` — add tag protection fields to `params.expect`

**Files:**
- Modify: `app/controllers/repositories_controller.rb`
- Test: `spec/requests/repositories_spec.rb`

- [x] **Step 1: Write failing request spec**

Append to `spec/requests/repositories_spec.rb` inside the existing `RSpec.describe 'Repositories', type: :request do ... end` block:

```ruby
  describe 'PATCH /repositories/:name with tag protection fields' do
    let!(:repo) { Repository.create!(name: 'example') }

    it 'persists tag_protection_policy when set to semver' do
      patch "/repositories/#{repo.name}",
        params: { repository: { tag_protection_policy: 'semver' } }
      expect(repo.reload.tag_protection_policy).to eq('semver')
    end

    it 'persists tag_protection_pattern when policy is custom_regex' do
      patch "/repositories/#{repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '^release-\d+$' } }
      expect(repo.reload.tag_protection_policy).to eq('custom_regex')
      expect(repo.reload.tag_protection_pattern).to eq('^release-\d+$')
    end

    it 'clears pattern when policy reverts from custom_regex' do
      repo.update!(tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      patch "/repositories/#{repo.name}",
        params: { repository: { tag_protection_policy: 'semver', tag_protection_pattern: '^v.+$' } }
      expect(repo.reload.tag_protection_pattern).to be_nil
    end

    it 'rejects invalid regex' do
      patch "/repositories/#{repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed' } }
      # update! raises ActiveRecord::RecordInvalid, which Rails renders as 500 without handling.
      # We expect either 422 (if the controller handles it) or the repo to stay unchanged.
      expect(repo.reload.tag_protection_policy).to eq('none')
    end
  end
```

- [x] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/requests/repositories_spec.rb
```
Expected: FAIL — strong params drops the new fields.

- [x] **Step 3: Update strong params and render form error on validation failure**

Replace `update` and `repository_params` in `app/controllers/repositories_controller.rb` with:

```ruby
  def update
    @repository = Repository.find_by!(name: params[:name])
    if @repository.update(repository_params)
      redirect_to repository_path(@repository.name), notice: 'Repository updated.'
    else
      @tags = @repository.tags.includes(:manifest).order(updated_at: :desc)
      flash.now[:alert] = @repository.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  private

  def repository_params
    params.expect(repository: [:description, :maintainer, :tag_protection_policy, :tag_protection_pattern])
  end
```

- [x] **Step 4: Run the spec — verify it passes**

```bash
bundle exec rspec spec/requests/repositories_spec.rb
```
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add app/controllers/repositories_controller.rb spec/requests/repositories_spec.rb
git commit -m "feat: accept tag protection fields in repository update"
```

---

## Task 12: Stimulus controller — show/hide regex input

**Files:**
- Create: `app/javascript/controllers/tag_protection_controller.js`
- Modify: `app/javascript/controllers/index.js` (if it manually registers controllers; Rails 8 auto-registers via stimulus-rails, so usually no edit)

- [x] **Step 1: Check whether controllers are auto-registered**

```bash
cat app/javascript/controllers/index.js 2>/dev/null | head -20
```

If the file uses `import { application } from "./application"` + `eagerLoadControllersFrom("controllers", application)`, controllers are auto-loaded by file name. Otherwise, a manual `application.register` line is needed for each controller.

- [x] **Step 2: Write the Stimulus controller**

Create `app/javascript/controllers/tag_protection_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Shows the custom regex input only when the policy select is set to
// "custom_regex". Data-driven, no DOM assumptions beyond the two targets.
export default class extends Controller {
  static targets = ["policy", "regexWrapper"]

  connect() {
    this.toggle()
  }

  toggle() {
    const shouldShow = this.policyTarget.value === "custom_regex"
    this.regexWrapperTarget.hidden = !shouldShow
  }
}
```

- [x] **Step 3: Manually register if needed**

If Step 1 shows `index.js` uses manual registration, add:

```javascript
import TagProtectionController from "./tag_protection_controller"
application.register("tag-protection", TagProtectionController)
```

If auto-loaded, skip.

- [x] **Step 4: Sanity check — no build error**

Rails 8 with importmap has no build step. A syntax error surfaces only when the browser loads the JS. We'll verify in the E2E spec (Task 16) and via manual browser load in Task 13. No commit yet — hold until paired with the view (Task 13).

---

## Task 13: Repository show — tag protection form + 🔒 Protected badge + disabled delete

**Files:**
- Modify: `app/views/repositories/show.html.erb`

- [x] **Step 1: Add policy select + regex input to the edit form**

In `app/views/repositories/show.html.erb`, find the form block that currently contains `<%= form_with model: @repository, ... do |f| %>` (around line 60-74). Extend it. Replace the form body (inside the `do |f| ... end`) with:

```erb
<%= form_with model: @repository, url: repository_path(@repository.name), method: :patch, class: "space-y-4",
              data: { controller: "tag-protection" } do |f| %>
  <div>
    <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">Description</label>
    <%= f.text_area :description, rows: 4, placeholder: "Describe the purpose of this repository, included tools, etc.",
      class: "block w-full rounded-md border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 px-3 py-2.5 text-base text-slate-900 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20 dark:focus:ring-blue-400/20 focus:border-blue-500 dark:focus:border-blue-400 transition-colors duration-150 resize-y" %>
  </div>
  <div>
    <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">Maintainer</label>
    <%= f.text_field :maintainer, placeholder: "Name or team...",
      class: "block w-full h-10 rounded-md border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 px-3 text-base text-slate-900 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20 dark:focus:ring-blue-400/20 focus:border-blue-500 dark:focus:border-blue-400 transition-colors duration-150" %>
  </div>
  <div>
    <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">Tag protection policy</label>
    <%= f.select :tag_protection_policy,
      [
        ["No protection",                      "none"],
        ["Protect semver tags (v1.2.3)",       "semver"],
        ["Protect everything except 'latest'", "all_except_latest"],
        ["Match by custom regex",              "custom_regex"]
      ],
      {},
      data: { tag_protection_target: "policy", action: "change->tag-protection#toggle" },
      class: "block w-full h-10 rounded-md border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 px-3 text-base text-slate-900 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-colors duration-150" %>
  </div>
  <div data-tag-protection-target="regexWrapper" <%= 'hidden' unless @repository.protection_custom_regex? %>>
    <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5">Protection pattern (regex)</label>
    <%= f.text_field :tag_protection_pattern, placeholder: '^release-\d+$',
      class: "block w-full h-10 rounded-md border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 px-3 text-base font-mono text-slate-900 dark:text-slate-100 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-colors duration-150" %>
    <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">Ruby regex. Tag names matching this pattern will be protected from overwrite and delete.</p>
  </div>
  <div class="flex items-center gap-3">
    <%= f.submit "Save", class: "inline-flex items-center gap-2 h-10 px-4 text-base font-medium text-white bg-blue-600 hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-400 rounded-md transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-blue-500/50 focus-visible:ring-offset-2 dark:focus-visible:ring-blue-400/50 dark:focus-visible:ring-offset-slate-900 cursor-pointer" %>
  </div>
<% end %>
```

- [x] **Step 2: Add 🔒 Protected badge + disabled delete button in the desktop table row**

In the same file, find the desktop tag row (around line 110-141). In the row's first column (the Tag column, currently line 112-115), replace with:

```erb
<div class="px-4 py-3">
  <div class="flex items-center gap-2">
    <%= link_to tag.name, repository_tag_path(@repository.name, tag),
      class: "text-sm font-medium text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300 hover:underline" %>
    <% if @repository.tag_protected?(tag.name) %>
      <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300 ring-1 ring-inset ring-amber-600/20"
            role="img"
            aria-label="Protected tag (policy: <%= @repository.tag_protection_policy %>)">
        🔒 Protected
      </span>
    <% end %>
  </div>
</div>
```

Then replace the desktop delete button cell (currently around line 131-140) with:

```erb
<div class="px-4 py-3 flex items-center justify-end">
  <% if @repository.tag_protected?(tag.name) %>
    <span class="inline-flex items-center gap-1.5 text-sm font-medium text-slate-400 dark:text-slate-500 cursor-not-allowed"
          title="Change the repository's tag protection policy to delete this tag.">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"/>
      </svg>
      Delete
    </span>
  <% else %>
    <%= button_to repository_tag_path(@repository.name, tag), method: :delete,
      data: { turbo_confirm: "Delete tag '#{tag.name}'? This action cannot be undone." },
      class: "inline-flex items-center gap-1.5 text-sm font-medium text-red-600 dark:text-red-400 hover:text-red-700 dark:hover:text-red-300 transition-colors duration-150" do %>
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"/>
      </svg>
      Delete
    <% end %>
  <% end %>
</div>
```

- [x] **Step 3: Apply the same badge + disable logic to the mobile card stack**

In the same file's mobile section (around line 147-170), update each card. Replace the card block body with:

```erb
<div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 px-4 py-4 shadow-sm">
  <div class="flex items-start justify-between gap-3 mb-2">
    <div class="flex items-center gap-2 min-w-0">
      <%= link_to tag.name, repository_tag_path(@repository.name, tag),
        class: "text-base font-medium text-blue-600 dark:text-blue-400 hover:underline truncate" %>
      <% if @repository.tag_protected?(tag.name) %>
        <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300 ring-1 ring-inset ring-amber-600/20 flex-shrink-0"
              role="img"
              aria-label="Protected tag (policy: <%= @repository.tag_protection_policy %>)">
          🔒 Protected
        </span>
      <% end %>
    </div>
    <span class="text-sm text-slate-400 dark:text-slate-500 flex-shrink-0"><%= time_ago_in_words(tag.updated_at) %> ago</span>
  </div>
  <div class="space-y-1 mb-3">
    <p class="text-sm text-slate-600 dark:text-slate-400 font-mono tabular-nums">Digest: <%= short_digest(tag.manifest.digest) %></p>
    <p class="text-sm text-slate-600 dark:text-slate-400">Size: <%= human_size(tag.manifest.size) %> &middot; <%= tag.manifest.architecture %>/<%= tag.manifest.os %> &middot; Pulls: <%= tag.manifest.pull_count %></p>
  </div>
  <div class="flex items-center gap-2">
    <% if @repository.tag_protected?(tag.name) %>
      <span class="inline-flex items-center gap-1.5 h-8 px-3 text-sm font-medium text-slate-400 dark:text-slate-500 cursor-not-allowed"
            title="Change the repository's tag protection policy to delete this tag.">
        Delete
      </span>
    <% else %>
      <%= button_to repository_tag_path(@repository.name, tag), method: :delete,
        data: { turbo_confirm: "Delete tag '#{tag.name}'?" },
        class: "inline-flex items-center gap-1.5 h-8 px-3 text-sm font-medium text-red-600 dark:text-red-400 hover:bg-red-100 dark:hover:bg-red-900/30 rounded-md transition-colors duration-150" do %>
        Delete
      <% end %>
    <% end %>
  </div>
</div>
```

- [x] **Step 4: Manual smoke test**

```bash
bin/dev
```

Open `http://localhost:3000/repositories/<existing-repo>` in the browser. Expand the edit form, select "Protect semver tags", save. Confirm a semver tag (e.g., `v1.0.0`) now shows 🔒 and the delete button is disabled. Select "Match by custom regex" — regex input appears. Select back to "No protection" — regex input hides.

If anything misbehaves, fix before committing. Also verify dark mode renders correctly.

- [x] **Step 5: Commit (bundles Task 12 + Task 13)**

```bash
git add app/views/repositories/show.html.erb app/javascript/controllers/tag_protection_controller.js app/javascript/controllers/index.js
git commit -m "feat: add tag protection form and protected badge to repo show"
```

---

## Task 14: Tag detail page — add delete button with disabled state for protected tags

**Files:**
- Modify: `app/views/tags/show.html.erb`

- [x] **Step 1: Insert a delete-button section above the "Layers" heading**

In `app/views/tags/show.html.erb`, the current structure is: back nav → tag info card → layers card → docker config. Insert a new section between the tag info card and the layers card.

After the closing `</div>` of the tag info card (around line 45) and before the Layers card, add:

```erb
<%# Tag actions: delete (decision 1-D — add button to tag detail, disable if protected) %>
<div class="flex items-center justify-end mb-6">
  <% if @repository.tag_protected?(@tag.name) %>
    <span class="inline-flex items-center gap-2 h-10 px-4 text-base font-medium text-slate-400 dark:text-slate-500 bg-slate-100 dark:bg-slate-800 rounded-md cursor-not-allowed"
          title="Change the repository's tag protection policy to delete this tag.">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"/>
      </svg>
      Delete tag (protected)
    </span>
  <% else %>
    <%= button_to repository_tag_path(@repository.name, @tag), method: :delete,
      data: { turbo_confirm: "Delete tag '#{@tag.name}'? This action cannot be undone." },
      class: "inline-flex items-center gap-2 h-10 px-4 text-base font-medium text-white bg-red-600 hover:bg-red-700 dark:bg-red-500 dark:hover:bg-red-400 rounded-md transition-colors duration-150 focus-visible:ring-2 focus-visible:ring-red-500/50 focus-visible:ring-offset-2 dark:focus-visible:ring-red-400/50 dark:focus-visible:ring-offset-slate-900" do %>
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"/>
      </svg>
      Delete tag
    <% end %>
  <% end %>
</div>
```

- [x] **Step 2: Manual smoke test**

Reload a protected tag detail page — button shows "Delete tag (protected)" disabled with tooltip. Reload an unprotected tag — button is active. Click delete on an unprotected tag — confirms + redirects with success flash.

- [x] **Step 3: Commit**

```bash
git add app/views/tags/show.html.erb
git commit -m "feat: add delete button to tag detail with disabled state when protected"
```

---

## Task 15: Docker CLI integration — extend `docker_cli_test.sh` with three scenarios

**Files:**
- Modify: `test/integration/docker_cli_test.sh`

- [x] **Step 1: Review current structure**

```bash
cat test/integration/docker_cli_test.sh
```

Note the existing `REGISTRY=${REGISTRY:-localhost:3000}` variable and the pattern of `echo "--- Test N: ..." ; ... ; echo "PASS: ..."`.

- [x] **Step 2: Append the protection scenarios**

Append to `test/integration/docker_cli_test.sh` before any final summary line:

```bash
# ============================================================
# Tag Protection scenarios (see 2026-04-22-tag-immutability-design.md)
# ============================================================

echo ""
echo "--- Test P1: enable semver protection on proto-img ---"
bin/rails runner 'Repository.find_or_create_by!(name: "proto-img").update!(tag_protection_policy: "semver")'
echo "PASS: policy set"

echo ""
echo "--- Test P2: initial push of v1.0.0 succeeds ---"
echo -e "FROM alpine:latest\nRUN echo protection-test-v1" | docker build -t $REGISTRY/proto-img:v1.0.0 - >/dev/null
docker push $REGISTRY/proto-img:v1.0.0 >/dev/null
echo "PASS: initial push accepted"

echo ""
echo "--- Test P3: re-push SAME digest succeeds (idempotent CI retry safety) ---"
docker push $REGISTRY/proto-img:v1.0.0 >/dev/null
echo "PASS: idempotent re-push accepted"

echo ""
echo "--- Test P4: push DIFFERENT digest to v1.0.0 is denied ---"
echo -e "FROM alpine:latest\nRUN echo protection-test-v2-DIFFERENT" | docker build -t $REGISTRY/proto-img:v1.0.0 - >/dev/null
PUSH_OUTPUT=$(docker push $REGISTRY/proto-img:v1.0.0 2>&1 || true)
echo "$PUSH_OUTPUT" | grep -q "denied" || { echo "FAIL: expected stderr to contain 'denied', got:"; echo "$PUSH_OUTPUT"; exit 1; }
echo "PASS: CLI printed 'denied:' on protected overwrite attempt"

echo ""
echo "--- Test P5: unprotected tag (latest) can still be overwritten under semver ---"
echo -e "FROM alpine:latest\nRUN echo protection-test-latest" | docker build -t $REGISTRY/proto-img:latest - >/dev/null
docker push $REGISTRY/proto-img:latest >/dev/null
echo "PASS: latest push succeeded under semver policy"

echo ""
echo "--- Cleanup: reset protection on proto-img ---"
bin/rails runner 'Repository.find_by(name: "proto-img")&.update!(tag_protection_policy: "none")'
docker rmi $REGISTRY/proto-img:v1.0.0 $REGISTRY/proto-img:latest 2>/dev/null || true
echo "PASS: cleanup done"
```

- [x] **Step 3: Run the full integration suite**

```bash
# Start a fresh local registry in another terminal:
# bin/dev
# Then:
./test/integration/docker_cli_test.sh
```
Expected: all existing tests PASS, all P1-P5 PASS. If P4 fails because the CLI does not include `"denied"` in stderr, inspect the actual output — Docker CLI typically surfaces the DENIED code as `denied:` prefix in the error line.

- [x] **Step 4: Commit**

```bash
git add test/integration/docker_cli_test.sh
git commit -m "test: add Docker CLI scenarios for tag protection"
```

---

## Task 16: Playwright E2E — `tag-protection.spec.js`

**Files:**
- Create: `e2e/tag-protection.spec.js`

- [x] **Step 1: Inspect an existing E2E spec to match the conventions**

```bash
ls e2e/
cat e2e/$(ls e2e/ | head -1) 2>/dev/null | head -50
```

Use the same import/convention pattern (imports, `test`, `expect`, `baseURL`, any fixtures for DB seed).

- [x] **Step 2: Write the spec**

Create `e2e/tag-protection.spec.js`:

```javascript
import { test, expect } from '@playwright/test'

test.describe('Tag Protection', () => {
  const repoName = 'e2e-tag-protection-repo'
  const protectedTag = 'v1.0.0'
  const floatingTag = 'latest'

  test.beforeEach(async ({ request }) => {
    // Seed via rails runner over HTTP is not available; rely on a test-setup
    // endpoint OR a pre-seeded fixture. The project's existing Playwright
    // specs use `test/fixtures` via bin/rails. If no endpoint exists,
    // gate this spec behind a RAILS_ENV=test API seed route.
    // See e2e/README.md (create if missing) for seed strategy.
  })

  test('policy save reflects 🔒 badge and disabled delete button', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`)

    // Open edit form (the <details> collapsible)
    await page.getByText('Edit description & maintainer').click()

    // Select semver policy
    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'semver')
    await page.getByRole('button', { name: 'Save' }).click()

    // After redirect, v1.0.0 should have badge, latest should not
    await expect(page.getByText('🔒 Protected').first()).toBeVisible()

    const protectedRow = page.locator(`a:has-text("${protectedTag}")`).locator('..')
    await expect(protectedRow.getByText('🔒 Protected')).toBeVisible()

    const floatingRow = page.locator(`a:has-text("${floatingTag}")`).locator('..')
    await expect(floatingRow.getByText('🔒 Protected')).toHaveCount(0)
  })

  test('protected tag delete button on repo show is disabled with tooltip', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`)
    const protectedRow = page.locator(`a:has-text("${protectedTag}")`).locator('..')
    const disabledDelete = protectedRow.getByText('Delete').first()
    await expect(disabledDelete).toHaveAttribute('title', /Change the repository's tag protection policy/)
  })

  test('protected tag detail page shows disabled delete button', async ({ page }) => {
    await page.goto(`/repositories/${repoName}/tags/${protectedTag}`)
    const btn = page.getByText('Delete tag (protected)')
    await expect(btn).toBeVisible()
    await expect(btn).toHaveAttribute('title', /Change the repository's tag protection policy/)
  })

  test('custom_regex shows regex input, non-custom hides it', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`)
    await page.getByText('Edit description & maintainer').click()

    const regexInput = page.locator('input[name="repository[tag_protection_pattern]"]')

    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'custom_regex')
    await expect(regexInput).toBeVisible()

    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'semver')
    await expect(regexInput).not.toBeVisible()
  })

  test('two-step flow: change policy to none, delete tag, restore policy', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`)
    await page.getByText('Edit description & maintainer').click()
    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'none')
    await page.getByRole('button', { name: 'Save' }).click()

    // Badge disappears
    const protectedRow = page.locator(`a:has-text("${protectedTag}")`).locator('..')
    await expect(protectedRow.getByText('🔒 Protected')).toHaveCount(0)

    // Delete button is now active and clickable
    page.on('dialog', dialog => dialog.accept())
    await protectedRow.getByRole('button', { name: /Delete/ }).click()

    // Back on repo page, tag is gone
    await expect(page.locator(`a:has-text("${protectedTag}")`)).toHaveCount(0)

    // Restore policy
    await page.getByText('Edit description & maintainer').click()
    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'semver')
    await page.getByRole('button', { name: 'Save' }).click()
  })

  test('invalid regex surfaces validation error', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`)
    await page.getByText('Edit description & maintainer').click()
    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'custom_regex')
    await page.fill('input[name="repository[tag_protection_pattern]"]', '[unclosed')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page.getByText(/is not a valid regex/)).toBeVisible()
  })
})
```

- [x] **Step 3: Add seed fixture support**

If `e2e/` has no seed mechanism yet, use the existing `test/integration/docker_cli_test.sh` approach — seed via `bin/rails runner` in a pre-spec hook. Add this helper at the top of `e2e/tag-protection.spec.js` if no `beforeAll` seed endpoint exists:

```javascript
import { execSync } from 'child_process'

test.beforeAll(() => {
  execSync(`bin/rails runner '
    repo = Repository.find_or_create_by!(name: "${repoName}")
    m = repo.manifests.find_or_create_by!(digest: "sha256:e2e-seed") do |x|
      x.media_type = "application/vnd.docker.distribution.manifest.v2+json"
      x.payload = "{}"
      x.size = 2
    end
    repo.tags.find_or_create_by!(name: "${protectedTag}") { |t| t.manifest = m }
    repo.tags.find_or_create_by!(name: "${floatingTag}") { |t| t.manifest = m }
    repo.update!(tag_protection_policy: "semver")
  '`, { stdio: 'inherit' })
})

test.afterAll(() => {
  execSync(`bin/rails runner 'Repository.find_by(name: "${repoName}")&.destroy!'`, { stdio: 'inherit' })
})
```

(Remove the lifecycle hooks if the project has a better seed pattern — check `e2e/README.md` or existing specs first.)

- [x] **Step 4: Run the E2E spec**

```bash
# Ensure dev server is running in another terminal
npx playwright test e2e/tag-protection.spec.js
```
Expected: all 6 tests PASS. If any fail due to selector specificity, tighten the locators — the Tailwind classes and structure from Task 13/14 are the source of truth.

- [x] **Step 5: Commit**

```bash
git add e2e/tag-protection.spec.js
git commit -m "test: add Playwright E2E for tag protection flow"
```

---

## Task 17: Final verification — full test suite + rubocop + brakeman

- [x] **Step 1: Full RSpec**

```bash
bundle exec rspec
```
Expected: PASS for all specs.

- [x] **Step 2: Rubocop**

```bash
bin/rubocop
```
Expected: PASS. If any offenses appear in the changed files, run `bin/rubocop -a` and re-commit via an additional "style:" commit if the changes are auto-corrections.

- [x] **Step 3: Brakeman security scan**

```bash
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
```
Expected: no new warnings. The new regex-input field accepts user-supplied strings but is only used as a `Regexp.new(...)` pattern (not shell-evaled, not SQL-interpolated). Rails 8 `Regexp.timeout = 1` prevents ReDoS.

- [x] **Step 4: Full CI dry run**

```bash
bin/ci
```
Expected: green. If seed check fails, inspect and fix (the migration adds a column with a safe default so no seed changes should be needed).

- [x] **Step 5: Diff review**

```bash
git log --oneline main..HEAD
git diff main...HEAD --stat
```

Confirm the commit sequence is:
1. `refactor: use params.expect for repository strong params`
2. `feat: add Registry::TagProtected error with detail payload`
3. `feat: rescue Registry::TagProtected as 409 DENIED in V2 base`
4. `feat: add tag_protection_policy and tag_protection_pattern columns`
5. `feat: add tag_protected? with four-policy enum on Repository`
6. `feat: add Repository#enforce_tag_protection! helper for all call sites`
7. `feat: enforce tag protection at ManifestProcessor entry with row lock`
8. `feat: block protected tag deletion via Web UI`
9. `feat: block protected manifest deletion via Registry V2 DELETE`
10. `fix: EnforceRetentionPolicyJob skips protected tags`
11. `feat: accept tag protection fields in repository update`
12. `feat: add tag protection form and protected badge to repo show`
13. `feat: add delete button to tag detail with disabled state when protected`
14. `test: add Docker CLI scenarios for tag protection`
15. `test: add Playwright E2E for tag protection flow`

---

## Out of scope for this plan (captured in TODOS.md)

- Policy-change audit event (`TagEvent` with `action=policy_change`) — P2 TODO.
- Repository edit form preview of "N tags will become protected/unprotected" — P2 TODO.
- Migration `IrreversibleMigration` guard after feature ships — P3 TODO.

Do not expand scope into any of these during execution. If a test or implementation step reveals a new concern not listed here, STOP and confirm with the user before adding tasks.

---

## Self-review notes

- Every task has exact file paths, complete code, exact commands, and a commit step.
- Test framework is RSpec throughout (matching project reality, not CLAUDE.md's outdated Minitest mention).
- `Repository#enforce_tag_protection!` is defined in Task 6 and used by Tasks 7, 8, 9, 10 — signatures match.
- `Registry::TagProtected` is defined in Task 2, raised in Task 6, rescued in Task 3, consumed in Tasks 7-10 — consistent throughout.
- Tidy First preserved: Task 1 is a pure refactor with its own commit before any behavior-adding commits.
- Decision 1-A (check at entry, not in `assign_tag!`): enforced in Task 7 by moving the call to before `manifest.find_or_initialize_by` and wrapping in `with_lock`. REGRESSION specs lock this in.
- Decision OV-2 (retention job P0): Task 10 with three protection scenarios.
- Critical gap "Regexp::TimeoutError rescue": currently not handled explicitly — `Regexp.new` in `tag_protection_pattern_is_valid_regex` rescues `RegexpError` (the parent class of `Regexp::TimeoutError` in Ruby 3.2+). If the project pins an older Ruby, promote this rescue to include `Regexp::TimeoutError` explicitly. Ruby 3.4.8 (per `docs/standards/STACK.md`) — `RegexpError` covers it, but add an explicit rescue if validation starts throwing 500s.

---

## Post-ship notes (2026-04-22)

### Issue found during E2E review (PR #12)

The self-review above correctly predicted that `Regexp.new` could throw a 500 — but only flagged the **validation** path. The **view-render** path was missed: when `RepositoriesController#update` fails validation, `@repository` is left in memory with the invalid `tag_protection_pattern`, and the re-rendered `show` template calls `tag_protected?` → `protection_regex` → `Regexp.new("[unclosed")` → `RegexpError` → HTTP 500.

### Fixes applied in this PR

- `e516b73` `fix: guard Repository#protection_regex against invalid pattern` — `protection_regex` now short-circuits on blank patterns and rescues `RegexpError` → `nil`. `tag_protected?`'s `custom_regex` branch is nil-safe.
- `8cbf7c0` `feat: render flash alert in layout to surface validation errors` — `application.html.erb` now renders `flash[:alert]` / `flash[:notice]` so validation failures are actually visible to the user.
- `9f150c5` `test: scope tag-protection Playwright spec to desktop grid and serial run` — locators narrowed to `.hidden.md\:block` to avoid strict-mode matches against the mobile card stack; describe marked `serial` so the shared SQLite seed/teardown is not raced by parallel workers.

### Regression tests

- `spec/models/repository_spec.rb` — "when policy is custom_regex but in-memory pattern is invalid" covers the view-safety unit case.
- `spec/requests/repositories_spec.rb` — "renders 422 with the validation message when regex is invalid (no 500)" and "does not crash when the invalid in-memory state touches tags in the view" cover the controller+view integration case.
- `e2e/tag-protection.spec.js` — "invalid regex surfaces validation error" exercises the full browser flow under Playwright.

### Takeaway for future plans

When a plan rescues an exception class in a validator, also explicitly check every call site that may dereference the same attribute **after** a failed validation (re-rendered forms, before_save hooks, memoised getters). The self-review prompt should include "does any view path call a method that performs the same dangerous operation without its own rescue?"
