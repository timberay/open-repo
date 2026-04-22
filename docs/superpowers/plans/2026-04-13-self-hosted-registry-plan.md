# Open Repo Self-Hosted Registry Implementation Plan

> **STATUS: SHIPPED.** All tasks complete and merged to `main`. The Rails 8 app at this repo root is the shipped product. This plan is preserved as a historical reference for what was built, not a work queue — do NOT execute. See `git log` for per-task commits.

**Goal:** Convert Open Repo from an external Docker Registry client to a self-contained Docker Registry V2 server with web UI management.

**Architecture:** Single Rails 8 process serving both Registry V2 API (`/v2/...`) and Web UI (`/`). Local filesystem for blob storage, SQLite for metadata. Solid Queue for async jobs (import/export, GC, retention).

**Tech Stack:** Rails 8.1, Ruby 3.4, SQLite3, Hotwire (Turbo + Stimulus), TailwindCSS, Solid Queue, RSpec, Playwright

**Spec:** `docs/superpowers/specs/2026-04-13-self-hosted-registry-design.md`

---

## Phase 1: Foundation

**Outcome:** New DB schema, models with validations, core services (BlobStore, DigestCalculator), error module. Old external-registry code removed. All models and services fully tested.

---

### Task 1: Remove Old External Registry Code

**Files:**
- Delete: `app/models/registry.rb`
- Delete: `app/services/docker_registry_service.rb`
- Delete: `app/services/mock_registry_service.rb`
- Delete: `app/services/registry_connection_tester.rb`
- Delete: `app/services/registry_health_check_service.rb`
- Delete: `app/services/local_registry_scanner.rb`
- Delete: `app/controllers/registries_controller.rb`
- Delete: `app/controllers/concerns/registry_error_handler.rb`
- Delete: `app/views/registries/` (entire directory)
- Delete: `app/views/shared/_registry_selector.html.erb`
- Delete: `app/javascript/controllers/registry_selector_controller.js`
- Delete: `app/javascript/controllers/registry_form_controller.js`
- Delete: `config/initializers/docker_registry.rb`
- Delete: `config/initializers/registry_setup.rb`
- Delete: `db/migrate/20260203010727_create_registries.rb`
- Delete: `spec/models/registry_spec.rb`
- Delete: `spec/services/docker_registry_service_spec.rb`
- Delete: `spec/services/mock_registry_service_spec.rb`
- Delete: `spec/services/registry_connection_tester_spec.rb`
- Delete: `spec/services/registry_health_check_service_spec.rb`
- Delete: `spec/services/local_registry_scanner_spec.rb`
- Delete: `spec/requests/registries_spec.rb`
- Delete: `spec/helpers/registries_helper_spec.rb`
- Delete: `spec/views/registries/` (if exists)
- Delete: `e2e/registry-management.spec.js`
- Delete: `e2e/registry-switching.spec.js`
- Delete: `e2e/registry-dropdown.spec.js`
- Modify: `app/controllers/application_controller.rb` — remove `current_registry` helper
- Modify: `app/views/layouts/application.html.erb` — remove registry selector from nav
- Modify: `config/routes.rb` — remove registry routes
- Modify: `app/controllers/repositories_controller.rb` — strip registry service dependency (will rewrite in Phase 3)

- [x] **Step 1: Delete old service files**

```bash
rm -f app/services/docker_registry_service.rb \
      app/services/mock_registry_service.rb \
      app/services/registry_connection_tester.rb \
      app/services/registry_health_check_service.rb \
      app/services/local_registry_scanner.rb
```

- [x] **Step 2: Delete old model and controller files**

```bash
rm -f app/models/registry.rb \
      app/controllers/registries_controller.rb \
      app/controllers/concerns/registry_error_handler.rb
rm -rf app/views/registries/
rm -f app/views/shared/_registry_selector.html.erb
```

- [x] **Step 3: Delete old JS controllers**

```bash
rm -f app/javascript/controllers/registry_selector_controller.js \
      app/javascript/controllers/registry_form_controller.js
```

- [x] **Step 4: Delete old initializers and migration**

```bash
rm -f config/initializers/docker_registry.rb \
      config/initializers/registry_setup.rb \
      db/migrate/20260203010727_create_registries.rb
```

- [x] **Step 5: Delete old specs and e2e tests**

```bash
rm -f spec/models/registry_spec.rb \
      spec/services/docker_registry_service_spec.rb \
      spec/services/mock_registry_service_spec.rb \
      spec/services/registry_connection_tester_spec.rb \
      spec/services/registry_health_check_service_spec.rb \
      spec/services/local_registry_scanner_spec.rb \
      spec/requests/registries_spec.rb \
      spec/helpers/registries_helper_spec.rb
rm -rf spec/views/registries/
rm -f e2e/registry-management.spec.js \
      e2e/registry-switching.spec.js \
      e2e/registry-dropdown.spec.js
```

- [x] **Step 6: Clean up application_controller.rb**

Replace contents of `app/controllers/application_controller.rb` with:

```ruby
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end
```

- [x] **Step 7: Clean up routes.rb**

Replace contents of `config/routes.rb` with:

```ruby
Rails.application.routes.draw do
  root "repositories#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [x] **Step 8: Stub repositories_controller.rb**

Replace contents of `app/controllers/repositories_controller.rb` with:

```ruby
class RepositoriesController < ApplicationController
  def index
    @repositories = []
  end
end
```

- [x] **Step 9: Clean up layout — remove registry selector from nav**

In `app/views/layouts/application.html.erb`, find the registry selector partial render and the registry-related nav elements. Remove:
- The `render 'shared/registry_selector'` line
- Any registry dropdown HTML in the nav bar

Keep: logo, theme toggle, main content yield.

- [x] **Step 10: Drop registries table and reset schema**

```bash
bin/rails db:drop db:create
```

- [x] **Step 11: Verify app boots without errors**

```bash
bin/rails server &
sleep 3
curl -s http://localhost:3000 | head -20
kill %1
```

Expected: HTML response with empty repository list (no errors).

- [x] **Step 12: Commit**

```bash
git add -A
git commit -m "refactor: remove all external registry client code

Remove Registry model, DockerRegistryService, MockRegistryService,
RegistryConnectionTester, RegistryHealthCheckService, LocalRegistryScanner,
RegistriesController, all related views, JS controllers, initializers,
specs, and E2E tests. Clean up routes and layout."
```

---

### Task 2: Create Error Module

**Files:**
- Create: `app/errors/registry.rb`
- Create: `spec/errors/registry_spec.rb`

- [x] **Step 1: Write the error module tests**

Create `spec/errors/registry_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Registry do
  describe 'exception hierarchy' do
    it 'all exceptions inherit from Registry::Error' do
      expect(Registry::BlobUnknown.new).to be_a(Registry::Error)
      expect(Registry::BlobUploadUnknown.new).to be_a(Registry::Error)
      expect(Registry::ManifestUnknown.new).to be_a(Registry::Error)
      expect(Registry::ManifestInvalid.new).to be_a(Registry::Error)
      expect(Registry::NameUnknown.new).to be_a(Registry::Error)
      expect(Registry::DigestMismatch.new).to be_a(Registry::Error)
      expect(Registry::Unsupported.new).to be_a(Registry::Error)
    end

    it 'Registry::Error inherits from StandardError' do
      expect(Registry::Error.new).to be_a(StandardError)
    end

    it 'carries custom messages' do
      error = Registry::BlobUnknown.new('blob sha256:abc not found')
      expect(error.message).to eq('blob sha256:abc not found')
    end
  end
end
```

- [x] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/errors/registry_spec.rb
```

Expected: FAIL — `uninitialized constant Registry`

- [x] **Step 3: Implement error module**

Create `app/errors/registry.rb`:

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

- [x] **Step 4: Run test to verify it passes**

```bash
bundle exec rspec spec/errors/registry_spec.rb
```

Expected: 3 examples, 0 failures

- [x] **Step 5: Commit**

```bash
git add app/errors/registry.rb spec/errors/registry_spec.rb
git commit -m "feat: add Registry error module with V2 API exception hierarchy"
```

---

### Task 3: Create Database Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_registry_tables.rb`

- [x] **Step 1: Generate migration**

```bash
bin/rails generate migration CreateRegistryTables
```

- [x] **Step 2: Write migration**

Edit the generated migration file:

```ruby
class CreateRegistryTables < ActiveRecord::Migration[8.0]
  def change
    create_table :repositories do |t|
      t.string :name, null: false
      t.text :description
      t.string :maintainer
      t.integer :tags_count, default: 0
      t.bigint :total_size, default: 0
      t.timestamps
      t.index :name, unique: true
    end

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
      t.integer :pull_count, default: 0
      t.datetime :last_pulled_at
      t.timestamps
      t.index :digest, unique: true
      t.index [:repository_id, :digest]
      t.index :last_pulled_at
    end

    create_table :tags do |t|
      t.references :repository, null: false, foreign_key: true
      t.references :manifest, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
      t.index [:repository_id, :name], unique: true
    end

    create_table :blobs do |t|
      t.string :digest, null: false
      t.bigint :size, null: false
      t.string :content_type
      t.integer :references_count, default: 0
      t.timestamps
      t.index :digest, unique: true
    end

    create_table :layers do |t|
      t.references :manifest, null: false, foreign_key: true
      t.references :blob, null: false, foreign_key: true
      t.integer :position, null: false
      t.index [:manifest_id, :position], unique: true
      t.index [:manifest_id, :blob_id], unique: true
    end

    create_table :blob_uploads do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :uuid, null: false
      t.bigint :byte_offset, default: 0
      t.timestamps
      t.index :uuid, unique: true
    end

    create_table :tag_events do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :tag_name, null: false
      t.string :action, null: false
      t.string :previous_digest
      t.string :new_digest
      t.string :actor
      t.datetime :occurred_at, null: false
      t.index [:repository_id, :tag_name]
      t.index :occurred_at
    end

    create_table :pull_events do |t|
      t.references :manifest, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.string :tag_name
      t.string :user_agent
      t.string :remote_ip
      t.datetime :occurred_at, null: false
      t.index [:repository_id, :occurred_at]
      t.index [:manifest_id, :occurred_at]
      t.index :occurred_at
    end

    create_table :imports do |t|
      t.string :status, null: false, default: 'pending'
      t.string :repository_name
      t.string :tag_name
      t.string :tar_path
      t.text :error_message
      t.integer :progress, default: 0
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
  end
end
```

- [x] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: All tables created without errors.

- [x] **Step 4: Verify schema**

```bash
bin/rails db:schema:dump
cat db/schema.rb | grep create_table
```

Expected: 10 `create_table` lines (repositories, manifests, tags, blobs, layers, blob_uploads, tag_events, pull_events, imports, exports).

- [x] **Step 5: Commit**

```bash
git add db/migrate/*_create_registry_tables.rb db/schema.rb
git commit -m "feat: add database schema for self-hosted registry

Tables: repositories, manifests, tags, blobs, layers, blob_uploads,
tag_events, pull_events, imports, exports"
```

---

### Task 4: Create ActiveRecord Models

**Files:**
- Create: `app/models/repository.rb`
- Create: `app/models/manifest.rb`
- Create: `app/models/tag.rb`
- Create: `app/models/blob.rb`
- Create: `app/models/layer.rb`
- Create: `app/models/blob_upload.rb`
- Create: `app/models/tag_event.rb`
- Create: `app/models/pull_event.rb`
- Create: `app/models/import.rb`
- Create: `app/models/export.rb`
- Create: `spec/models/repository_spec.rb`
- Create: `spec/models/manifest_spec.rb`
- Create: `spec/models/tag_spec.rb`
- Create: `spec/models/blob_spec.rb`
- Create: `spec/models/layer_spec.rb`
- Create: `spec/models/blob_upload_spec.rb`
- Create: `spec/models/tag_event_spec.rb`
- Create: `spec/models/pull_event_spec.rb`

- [x] **Step 1: Write Repository model spec**

Create `spec/models/repository_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Repository, type: :model do
  describe 'validations' do
    it 'requires name' do
      repo = Repository.new(name: nil)
      expect(repo).not_to be_valid
      expect(repo.errors[:name]).to include("can't be blank")
    end

    it 'requires unique name' do
      Repository.create!(name: 'myapp')
      repo = Repository.new(name: 'myapp')
      expect(repo).not_to be_valid
      expect(repo.errors[:name]).to include('has already been taken')
    end
  end

  describe 'associations' do
    it 'has many tags' do
      expect(Repository.reflect_on_association(:tags).macro).to eq(:has_many)
    end

    it 'has many manifests' do
      expect(Repository.reflect_on_association(:manifests).macro).to eq(:has_many)
    end

    it 'has many tag_events' do
      expect(Repository.reflect_on_association(:tag_events).macro).to eq(:has_many)
    end
  end
end
```

- [x] **Step 2: Write Manifest model spec**

Create `spec/models/manifest_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Manifest, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }

  describe 'validations' do
    it 'requires digest, media_type, payload, size' do
      manifest = Manifest.new(repository: repository)
      expect(manifest).not_to be_valid
      expect(manifest.errors[:digest]).to include("can't be blank")
      expect(manifest.errors[:media_type]).to include("can't be blank")
      expect(manifest.errors[:payload]).to include("can't be blank")
      expect(manifest.errors[:size]).to include("can't be blank")
    end

    it 'requires unique digest' do
      Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
      m2 = Manifest.new(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
      expect(m2).not_to be_valid
    end
  end

  describe 'associations' do
    it 'has many tags' do
      expect(Manifest.reflect_on_association(:tags).macro).to eq(:has_many)
    end

    it 'has many layers' do
      expect(Manifest.reflect_on_association(:layers).macro).to eq(:has_many)
    end

    it 'has many pull_events' do
      expect(Manifest.reflect_on_association(:pull_events).macro).to eq(:has_many)
    end
  end
end
```

- [x] **Step 3: Write Blob model spec**

Create `spec/models/blob_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Blob, type: :model do
  describe 'validations' do
    it 'requires digest and size' do
      blob = Blob.new
      expect(blob).not_to be_valid
      expect(blob.errors[:digest]).to include("can't be blank")
      expect(blob.errors[:size]).to include("can't be blank")
    end

    it 'requires unique digest' do
      Blob.create!(digest: 'sha256:abc', size: 1024)
      b2 = Blob.new(digest: 'sha256:abc', size: 1024)
      expect(b2).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'has references_count defaulting to 0' do
      blob = Blob.create!(digest: 'sha256:abc', size: 1024)
      expect(blob.references_count).to eq(0)
    end
  end
end
```

- [x] **Step 4: Write remaining model specs**

Create `spec/models/tag_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Tag, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }

  describe 'validations' do
    it 'requires name' do
      tag = Tag.new(repository: repository, manifest: manifest, name: nil)
      expect(tag).not_to be_valid
    end

    it 'requires unique name per repository' do
      Tag.create!(repository: repository, manifest: manifest, name: 'latest')
      t2 = Tag.new(repository: repository, manifest: manifest, name: 'latest')
      expect(t2).not_to be_valid
    end
  end
end
```

Create `spec/models/layer_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Layer, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }
  let(:blob) { Blob.create!(digest: 'sha256:layer1', size: 2048) }

  describe 'validations' do
    it 'requires position' do
      layer = Layer.new(manifest: manifest, blob: blob, position: nil)
      expect(layer).not_to be_valid
    end

    it 'requires unique position per manifest' do
      Layer.create!(manifest: manifest, blob: blob, position: 0)
      l2 = Layer.new(manifest: manifest, blob: blob, position: 0)
      expect(l2).not_to be_valid
    end
  end
end
```

Create `spec/models/blob_upload_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe BlobUpload, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }

  describe 'validations' do
    it 'requires uuid' do
      upload = BlobUpload.new(repository: repository, uuid: nil)
      expect(upload).not_to be_valid
    end

    it 'requires unique uuid' do
      BlobUpload.create!(repository: repository, uuid: 'abc-123')
      u2 = BlobUpload.new(repository: repository, uuid: 'abc-123')
      expect(u2).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'byte_offset defaults to 0' do
      upload = BlobUpload.create!(repository: repository, uuid: 'abc-123')
      expect(upload.byte_offset).to eq(0)
    end
  end
end
```

Create `spec/models/tag_event_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe TagEvent, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }

  describe 'validations' do
    it 'requires tag_name, action, occurred_at' do
      event = TagEvent.new(repository: repository)
      expect(event).not_to be_valid
      expect(event.errors[:tag_name]).to include("can't be blank")
      expect(event.errors[:action]).to include("can't be blank")
      expect(event.errors[:occurred_at]).to include("can't be blank")
    end
  end
end
```

Create `spec/models/pull_event_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe PullEvent, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }

  describe 'validations' do
    it 'requires occurred_at' do
      event = PullEvent.new(manifest: manifest, repository: repository)
      expect(event).not_to be_valid
      expect(event.errors[:occurred_at]).to include("can't be blank")
    end
  end
end
```

- [x] **Step 5: Run all model specs to verify they fail**

```bash
bundle exec rspec spec/models/
```

Expected: All FAIL — models not yet defined.

- [x] **Step 6: Implement all models**

Create `app/models/repository.rb`:

```ruby
class Repository < ApplicationRecord
  has_many :tags, dependent: :destroy
  has_many :manifests, dependent: :destroy
  has_many :tag_events, dependent: :destroy
  has_many :blob_uploads, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
```

Create `app/models/manifest.rb`:

```ruby
class Manifest < ApplicationRecord
  belongs_to :repository
  has_many :tags, dependent: :nullify
  has_many :layers, dependent: :destroy
  has_many :blobs, through: :layers
  has_many :pull_events, dependent: :destroy

  validates :digest, presence: true, uniqueness: true
  validates :media_type, presence: true
  validates :payload, presence: true
  validates :size, presence: true
end
```

Create `app/models/tag.rb`:

```ruby
class Tag < ApplicationRecord
  belongs_to :repository, counter_cache: true
  belongs_to :manifest

  validates :name, presence: true, uniqueness: { scope: :repository_id }
end
```

Create `app/models/blob.rb`:

```ruby
class Blob < ApplicationRecord
  has_many :layers, dependent: :destroy
  has_many :manifests, through: :layers

  validates :digest, presence: true, uniqueness: true
  validates :size, presence: true
end
```

Create `app/models/layer.rb`:

```ruby
class Layer < ApplicationRecord
  belongs_to :manifest
  belongs_to :blob

  validates :position, presence: true, uniqueness: { scope: :manifest_id }
end
```

Create `app/models/blob_upload.rb`:

```ruby
class BlobUpload < ApplicationRecord
  belongs_to :repository

  validates :uuid, presence: true, uniqueness: true
end
```

Create `app/models/tag_event.rb`:

```ruby
class TagEvent < ApplicationRecord
  belongs_to :repository

  validates :tag_name, presence: true
  validates :action, presence: true, inclusion: { in: %w[create update delete] }
  validates :occurred_at, presence: true
end
```

Create `app/models/pull_event.rb`:

```ruby
class PullEvent < ApplicationRecord
  belongs_to :manifest
  belongs_to :repository

  validates :occurred_at, presence: true
end
```

Create `app/models/import.rb`:

```ruby
class Import < ApplicationRecord
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }
end
```

Create `app/models/export.rb`:

```ruby
class Export < ApplicationRecord
  belongs_to :repository

  validates :tag_name, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }
end
```

- [x] **Step 7: Run all model specs**

```bash
bundle exec rspec spec/models/
```

Expected: All pass.

- [x] **Step 8: Commit**

```bash
git add app/models/ spec/models/
git commit -m "feat: add ActiveRecord models for registry schema

Repository, Manifest, Tag, Blob, Layer, BlobUpload, TagEvent,
PullEvent, Import, Export with validations and associations"
```

---

### Task 5: Implement DigestCalculator Service

**Files:**
- Create: `app/services/digest_calculator.rb`
- Create: `spec/services/digest_calculator_spec.rb`

- [x] **Step 1: Write spec**

Create `spec/services/digest_calculator_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe DigestCalculator do
  describe '.compute' do
    it 'computes sha256 digest of a string' do
      digest = DigestCalculator.compute('hello world')
      expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest('hello world')}")
    end

    it 'computes sha256 digest of an IO stream' do
      io = StringIO.new('hello world')
      digest = DigestCalculator.compute(io)
      expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest('hello world')}")
    end

    it 'computes sha256 digest of a file' do
      Tempfile.create('test') do |f|
        f.write('hello world')
        f.rewind
        digest = DigestCalculator.compute(f)
        expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest('hello world')}")
      end
    end

    it 'handles large data in chunks' do
      large_data = SecureRandom.random_bytes(1024 * 1024)
      io = StringIO.new(large_data)
      digest = DigestCalculator.compute(io)
      expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest(large_data)}")
    end
  end

  describe '.verify!' do
    it 'passes when digest matches' do
      data = 'hello world'
      expected = "sha256:#{Digest::SHA256.hexdigest(data)}"
      expect { DigestCalculator.verify!(StringIO.new(data), expected) }.not_to raise_error
    end

    it 'raises DigestMismatch when digest does not match' do
      expect {
        DigestCalculator.verify!(StringIO.new('hello'), 'sha256:wrong')
      }.to raise_error(Registry::DigestMismatch, /digest mismatch/)
    end
  end
end
```

- [x] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/services/digest_calculator_spec.rb
```

Expected: FAIL — `uninitialized constant DigestCalculator`

- [x] **Step 3: Implement DigestCalculator**

Create `app/services/digest_calculator.rb`:

```ruby
class DigestCalculator
  CHUNK_SIZE = 64 * 1024 # 64KB

  def self.compute(io_or_string)
    sha = Digest::SHA256.new

    if io_or_string.is_a?(String)
      sha.update(io_or_string)
    else
      io_or_string.rewind if io_or_string.respond_to?(:rewind)
      while (chunk = io_or_string.read(CHUNK_SIZE))
        sha.update(chunk)
      end
      io_or_string.rewind if io_or_string.respond_to?(:rewind)
    end

    "sha256:#{sha.hexdigest}"
  end

  def self.verify!(io, expected_digest)
    actual = compute(io)
    return if actual == expected_digest

    raise Registry::DigestMismatch,
      "digest mismatch: expected #{expected_digest}, got #{actual}"
  end
end
```

- [x] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/digest_calculator_spec.rb
```

Expected: 5 examples, 0 failures

- [x] **Step 5: Commit**

```bash
git add app/services/digest_calculator.rb spec/services/digest_calculator_spec.rb
git commit -m "feat: add DigestCalculator service for SHA256 computation and verification"
```

---

### Task 6: Implement BlobStore Service

**Files:**
- Create: `app/services/blob_store.rb`
- Create: `spec/services/blob_store_spec.rb`

- [x] **Step 1: Write spec**

Create `spec/services/blob_store_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe BlobStore do
  let(:storage_dir) { Dir.mktmpdir }
  let(:store) { BlobStore.new(storage_dir) }

  after { FileUtils.rm_rf(storage_dir) }

  describe '#put and #get' do
    it 'stores and retrieves a blob by digest' do
      content = 'hello blob'
      digest = DigestCalculator.compute(content)

      store.put(digest, StringIO.new(content))
      io = store.get(digest)
      expect(io.read).to eq(content)
    end

    it 'skips write if blob already exists' do
      content = 'hello blob'
      digest = DigestCalculator.compute(content)

      store.put(digest, StringIO.new(content))
      path = store.path_for(digest)
      mtime_before = File.mtime(path)

      sleep 0.01
      store.put(digest, StringIO.new(content))
      expect(File.mtime(path)).to eq(mtime_before)
    end
  end

  describe '#exists?' do
    it 'returns false for non-existent blob' do
      expect(store.exists?('sha256:nonexistent')).to be false
    end

    it 'returns true after storing' do
      content = 'test'
      digest = DigestCalculator.compute(content)
      store.put(digest, StringIO.new(content))
      expect(store.exists?(digest)).to be true
    end
  end

  describe '#delete' do
    it 'removes blob from disk' do
      content = 'test'
      digest = DigestCalculator.compute(content)
      store.put(digest, StringIO.new(content))
      store.delete(digest)
      expect(store.exists?(digest)).to be false
    end
  end

  describe '#path_for' do
    it 'uses sharded directory structure' do
      path = store.path_for('sha256:aabbccdd1234')
      expect(path).to include('/blobs/sha256/aa/aabbccdd1234')
    end
  end

  describe '#size' do
    it 'returns file size' do
      content = 'hello blob'
      digest = DigestCalculator.compute(content)
      store.put(digest, StringIO.new(content))
      expect(store.size(digest)).to eq(content.bytesize)
    end
  end

  describe 'upload lifecycle' do
    let(:uuid) { SecureRandom.uuid }

    it 'creates, appends, and finalizes an upload' do
      store.create_upload(uuid)
      expect(store.upload_size(uuid)).to eq(0)

      chunk1 = 'hello '
      chunk2 = 'world'
      store.append_upload(uuid, StringIO.new(chunk1))
      expect(store.upload_size(uuid)).to eq(6)

      store.append_upload(uuid, StringIO.new(chunk2))
      expect(store.upload_size(uuid)).to eq(11)

      content = chunk1 + chunk2
      digest = DigestCalculator.compute(content)
      store.finalize_upload(uuid, digest)

      expect(store.exists?(digest)).to be true
      expect(store.get(digest).read).to eq(content)
    end

    it 'raises DigestMismatch on finalize with wrong digest' do
      store.create_upload(uuid)
      store.append_upload(uuid, StringIO.new('hello'))

      expect {
        store.finalize_upload(uuid, 'sha256:wrong')
      }.to raise_error(Registry::DigestMismatch)
    end

    it 'cancels an upload and cleans up' do
      store.create_upload(uuid)
      store.append_upload(uuid, StringIO.new('data'))
      store.cancel_upload(uuid)

      expect { store.upload_size(uuid) }.to raise_error(Errno::ENOENT)
    end
  end

  describe '#cleanup_stale_uploads' do
    it 'removes uploads older than max_age' do
      uuid = SecureRandom.uuid
      store.create_upload(uuid)
      store.append_upload(uuid, StringIO.new('data'))

      # Backdate the startedat file
      startedat_path = File.join(storage_dir, 'uploads', uuid, 'startedat')
      File.write(startedat_path, 2.hours.ago.iso8601)

      store.cleanup_stale_uploads(max_age: 1.hour)
      expect(Dir.exist?(File.join(storage_dir, 'uploads', uuid))).to be false
    end
  end
end
```

- [x] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/services/blob_store_spec.rb
```

Expected: FAIL — `uninitialized constant BlobStore`

- [x] **Step 3: Implement BlobStore**

Create `app/services/blob_store.rb`:

```ruby
class BlobStore
  CHUNK_SIZE = 64 * 1024 # 64KB

  def initialize(root_path = Rails.configuration.storage_path)
    @root_path = root_path.to_s
  end

  # --- Blob management ---

  def get(digest)
    path = path_for(digest)
    File.open(path, 'rb')
  end

  def put(digest, io)
    target = path_for(digest)
    return if File.exist?(target)

    FileUtils.mkdir_p(File.dirname(target))
    tmp = "#{target}.#{SecureRandom.hex(8)}.tmp"

    File.open(tmp, 'wb') do |f|
      io.rewind if io.respond_to?(:rewind)
      while (chunk = io.read(CHUNK_SIZE))
        f.write(chunk)
      end
    end

    File.rename(tmp, target)
  rescue => e
    FileUtils.rm_f(tmp) if tmp
    raise e
  end

  def exists?(digest)
    File.exist?(path_for(digest))
  end

  def delete(digest)
    FileUtils.rm_f(path_for(digest))
  end

  def path_for(digest)
    algorithm, hex = digest.split(':')
    shard = hex[0..1]
    File.join(@root_path, 'blobs', algorithm, shard, hex)
  end

  def size(digest)
    File.size(path_for(digest))
  end

  # --- Upload session management ---

  def create_upload(uuid)
    dir = upload_dir(uuid)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'startedat'), Time.current.iso8601)
  end

  def append_upload(uuid, io)
    data_path = File.join(upload_dir(uuid), 'data')
    File.open(data_path, 'ab') do |f|
      io.rewind if io.respond_to?(:rewind)
      while (chunk = io.read(CHUNK_SIZE))
        f.write(chunk)
      end
    end
  end

  def upload_size(uuid)
    data_path = File.join(upload_dir(uuid), 'data')
    File.exist?(data_path) ? File.size(data_path) : 0
  end

  def finalize_upload(uuid, digest)
    data_path = File.join(upload_dir(uuid), 'data')
    DigestCalculator.verify!(File.open(data_path, 'rb'), digest)
    put(digest, File.open(data_path, 'rb'))
    cancel_upload(uuid)
  end

  def cancel_upload(uuid)
    FileUtils.rm_rf(upload_dir(uuid))
  end

  def cleanup_stale_uploads(max_age: 1.hour)
    uploads_root = File.join(@root_path, 'uploads')
    return unless Dir.exist?(uploads_root)

    Dir.each_child(uploads_root) do |uuid|
      dir = File.join(uploads_root, uuid)
      startedat_path = File.join(dir, 'startedat')
      next unless File.exist?(startedat_path)

      started_at = Time.parse(File.read(startedat_path))
      FileUtils.rm_rf(dir) if started_at < max_age.ago
    end
  end

  private

  def upload_dir(uuid)
    File.join(@root_path, 'uploads', uuid)
  end
end
```

- [x] **Step 4: Add storage_path config**

Add to `config/application.rb` inside the `Application` class:

```ruby
config.storage_path = ENV.fetch('STORAGE_PATH', Rails.root.join('storage', 'registry'))
config.registry_host = ENV.fetch('REGISTRY_HOST', 'localhost:3000')
```

- [x] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/blob_store_spec.rb
```

Expected: All pass.

- [x] **Step 6: Commit**

```bash
git add app/services/blob_store.rb spec/services/blob_store_spec.rb config/application.rb
git commit -m "feat: add BlobStore service with content-addressable storage and upload lifecycle"
```

---

### Task 7: Implement ManifestProcessor Service

**Files:**
- Create: `app/services/manifest_processor.rb`
- Create: `spec/services/manifest_processor_spec.rb`
- Create: `spec/fixtures/manifests/v2_schema2.json`
- Create: `spec/fixtures/configs/image_config.json`

- [x] **Step 1: Create test fixture files**

Create `spec/fixtures/manifests/v2_schema2.json`:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {
    "mediaType": "application/vnd.docker.container.image.v1+json",
    "size": 1234,
    "digest": "sha256:config_digest_placeholder"
  },
  "layers": [
    {
      "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
      "size": 10240,
      "digest": "sha256:layer1_digest_placeholder"
    },
    {
      "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
      "size": 20480,
      "digest": "sha256:layer2_digest_placeholder"
    }
  ]
}
```

Create `spec/fixtures/configs/image_config.json`:

```json
{
  "architecture": "amd64",
  "os": "linux",
  "config": {
    "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
    "Cmd": ["/bin/sh"],
    "Entrypoint": null,
    "Labels": {"maintainer": "test@example.com"}
  }
}
```

- [x] **Step 2: Write spec**

Create `spec/services/manifest_processor_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe ManifestProcessor do
  let(:store_dir) { Dir.mktmpdir }
  let(:blob_store) { BlobStore.new(store_dir) }
  let(:processor) { ManifestProcessor.new(blob_store) }

  after { FileUtils.rm_rf(store_dir) }

  let(:config_content) { File.read(Rails.root.join('spec/fixtures/configs/image_config.json')) }
  let(:config_digest) { DigestCalculator.compute(config_content) }

  let(:layer1_content) { SecureRandom.random_bytes(1024) }
  let(:layer1_digest) { DigestCalculator.compute(layer1_content) }

  let(:layer2_content) { SecureRandom.random_bytes(2048) }
  let(:layer2_digest) { DigestCalculator.compute(layer2_content) }

  let(:manifest_json) do
    {
      schemaVersion: 2,
      mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
      config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
      layers: [
        { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: layer1_content.bytesize, digest: layer1_digest },
        { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: layer2_content.bytesize, digest: layer2_digest }
      ]
    }.to_json
  end

  before do
    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(layer1_digest, StringIO.new(layer1_content))
    blob_store.put(layer2_digest, StringIO.new(layer2_content))
  end

  describe '#call' do
    it 'creates repository, manifest, tag, layers, and blobs' do
      result = processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)

      expect(result).to be_a(Manifest)
      expect(Repository.find_by(name: 'test-repo')).to be_present
      expect(Tag.find_by(name: 'v1.0.0')).to be_present
      expect(result.layers.count).to eq(2)
      expect(result.architecture).to eq('amd64')
      expect(result.os).to eq('linux')
      expect(result.docker_config).to include('Cmd')
    end

    it 'creates a tag_event on new tag' do
      processor.call('test-repo', 'v1.0.0', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)

      event = TagEvent.last
      expect(event.action).to eq('create')
      expect(event.tag_name).to eq('v1.0.0')
      expect(event.previous_digest).to be_nil
    end

    it 'creates an update tag_event when tag is reassigned' do
      result1 = processor.call('test-repo', 'latest', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
      old_digest = result1.digest

      # Push a different manifest to same tag
      new_layer = SecureRandom.random_bytes(512)
      new_layer_digest = DigestCalculator.compute(new_layer)
      blob_store.put(new_layer_digest, StringIO.new(new_layer))

      new_manifest_json = {
        schemaVersion: 2,
        mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
        config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
        layers: [
          { mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: new_layer.bytesize, digest: new_layer_digest }
        ]
      }.to_json

      processor.call('test-repo', 'latest', 'application/vnd.docker.distribution.manifest.v2+json', new_manifest_json)

      event = TagEvent.where(action: 'update').last
      expect(event.previous_digest).to eq(old_digest)
    end

    it 'raises ManifestInvalid for missing referenced blob' do
      bad_json = {
        schemaVersion: 2,
        mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
        config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: 100, digest: 'sha256:nonexistent' },
        layers: []
      }.to_json

      expect {
        processor.call('test-repo', 'v1', 'application/vnd.docker.distribution.manifest.v2+json', bad_json)
      }.to raise_error(Registry::ManifestInvalid, /config blob not found/)
    end

    it 'handles digest reference instead of tag name' do
      result = processor.call('test-repo', nil, 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)
      expect(result).to be_a(Manifest)
      expect(Tag.count).to eq(0)
    end

    it 'increments blob references_count' do
      processor.call('test-repo', 'v1', 'application/vnd.docker.distribution.manifest.v2+json', manifest_json)

      layer1_blob = Blob.find_by(digest: layer1_digest)
      expect(layer1_blob.references_count).to eq(1)
    end
  end
end
```

- [x] **Step 3: Run test to verify it fails**

```bash
bundle exec rspec spec/services/manifest_processor_spec.rb
```

Expected: FAIL — `uninitialized constant ManifestProcessor`

- [x] **Step 4: Implement ManifestProcessor**

Create `app/services/manifest_processor.rb`:

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

    if reference.present? && !reference.start_with?('sha256:')
      assign_tag!(repository, reference, manifest)
    end

    update_repository_size!(repository)

    manifest
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
      blob = Blob.create_or_find_by!(digest: layer_data['digest']) do |b|
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
    total = repository.manifests.joins(:layers => :blob).sum('blobs.size')
    repository.update_column(:total_size, total)
  end
end
```

- [x] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/manifest_processor_spec.rb
```

Expected: All pass.

- [x] **Step 6: Commit**

```bash
git add app/services/manifest_processor.rb spec/services/manifest_processor_spec.rb spec/fixtures/
git commit -m "feat: add ManifestProcessor service for manifest validation, storage, and tag management"
```

---

## Phase 2: Registry V2 API

**Outcome:** All Docker Registry V2 endpoints functional. `docker push` and `docker pull` work against the server.

---

### Task 8: V2 Base Controller and Base Endpoint

**Files:**
- Create: `app/controllers/v2/base_controller.rb`
- Create: `spec/requests/v2/base_spec.rb`

- [x] **Step 1: Write spec**

Create `spec/requests/v2/base_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'V2 Base API', type: :request do
  describe 'GET /v2/' do
    it 'returns 200 with empty JSON body' do
      get '/v2/'
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq({})
    end

    it 'includes Docker-Distribution-API-Version header' do
      get '/v2/'
      expect(response.headers['Docker-Distribution-API-Version']).to eq('registry/2.0')
    end
  end
end
```

- [x] **Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/requests/v2/base_spec.rb
```

Expected: FAIL — route not defined.

- [x] **Step 3: Add V2 routes to config/routes.rb**

Replace `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "repositories#index"

  # Docker Registry V2 API
  scope '/v2', defaults: { format: :json } do
    get '/', to: 'v2/base#index'
    get '/_catalog', to: 'v2/catalog#index'

    get '/*name/tags/list', to: 'v2/tags#index', format: false
    get '/*name/manifests/:reference', to: 'v2/manifests#show', format: false
    head '/*name/manifests/:reference', to: 'v2/manifests#show', format: false
    put '/*name/manifests/:reference', to: 'v2/manifests#update', format: false
    delete '/*name/manifests/:reference', to: 'v2/manifests#destroy', format: false

    get '/*name/blobs/:digest', to: 'v2/blobs#show', format: false
    head '/*name/blobs/:digest', to: 'v2/blobs#show', format: false
    delete '/*name/blobs/:digest', to: 'v2/blobs#destroy', format: false

    post '/*name/blobs/uploads', to: 'v2/blob_uploads#create', format: false
    patch '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#update', format: false
    put '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#complete', format: false
    delete '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#destroy', format: false
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [x] **Step 4: Implement V2::BaseController**

Create `app/controllers/v2/base_controller.rb`:

```ruby
class V2::BaseController < ActionController::API
  before_action :set_registry_headers

  rescue_from Registry::BlobUnknown, with: -> (e) { render_error('BLOB_UNKNOWN', e.message, 404) }
  rescue_from Registry::BlobUploadUnknown, with: -> (e) { render_error('BLOB_UPLOAD_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestUnknown, with: -> (e) { render_error('MANIFEST_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestInvalid, with: -> (e) { render_error('MANIFEST_INVALID', e.message, 400) }
  rescue_from Registry::NameUnknown, with: -> (e) { render_error('NAME_UNKNOWN', e.message, 404) }
  rescue_from Registry::DigestMismatch, with: -> (e) { render_error('DIGEST_INVALID', e.message, 400) }
  rescue_from Registry::Unsupported, with: -> (e) { render_error('UNSUPPORTED', e.message, 415) }

  def index
    render json: {}
  end

  private

  def set_registry_headers
    response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
  end

  def render_error(code, message, status, detail: {})
    render json: { errors: [{ code: code, message: message, detail: detail }] }, status: status
  end

  def find_repository!
    Repository.find_by!(name: params[:name])
  rescue ActiveRecord::RecordNotFound
    raise Registry::NameUnknown, "repository '#{params[:name]}' not found"
  end
end
```

- [x] **Step 5: Run tests**

```bash
bundle exec rspec spec/requests/v2/base_spec.rb
```

Expected: 2 examples, 0 failures

- [x] **Step 6: Commit**

```bash
git add app/controllers/v2/ config/routes.rb spec/requests/v2/
git commit -m "feat: add V2 base controller with error handling and GET /v2/ endpoint"
```

---

### Task 9: Blob Uploads Controller (Push Flow)

**Files:**
- Create: `app/controllers/v2/blob_uploads_controller.rb`
- Create: `spec/requests/v2/blob_uploads_spec.rb`

- [x] **Step 1: Write spec**

Create `spec/requests/v2/blob_uploads_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'V2 Blob Uploads API', type: :request do
  let(:repo_name) { 'test-repo' }

  describe 'POST /v2/:name/blobs/uploads (start upload)' do
    it 'returns 202 with Location and upload UUID' do
      post "/v2/#{repo_name}/blobs/uploads"

      expect(response).to have_http_status(202)
      expect(response.headers['Location']).to match(%r{/v2/#{repo_name}/blobs/uploads/.+})
      expect(response.headers['Docker-Upload-UUID']).to be_present
      expect(response.headers['Range']).to eq('0-0')
    end

    it 'creates repository if not exists' do
      post "/v2/#{repo_name}/blobs/uploads"
      expect(Repository.find_by(name: repo_name)).to be_present
    end
  end

  describe 'POST /v2/:name/blobs/uploads?digest= (monolithic upload)' do
    it 'stores blob in single request' do
      content = 'monolithic blob data'
      digest = DigestCalculator.compute(content)

      post "/v2/#{repo_name}/blobs/uploads?digest=#{digest}",
           params: content,
           headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
    end
  end

  describe 'PATCH /v2/:name/blobs/uploads/:uuid (chunk upload)' do
    it 'appends data and returns updated range' do
      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
            params: 'chunk data',
            headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      expect(response).to have_http_status(202)
      expect(response.headers['Range']).to eq('0-9')
      expect(response.headers['Docker-Upload-UUID']).to eq(uuid)
    end
  end

  describe 'PUT /v2/:name/blobs/uploads/:uuid?digest= (complete upload)' do
    it 'finalizes upload and creates blob record' do
      content = 'final blob content'
      digest = DigestCalculator.compute(content)

      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
            params: content,
            headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      put "/v2/#{repo_name}/blobs/uploads/#{uuid}?digest=#{digest}"

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
      expect(Blob.find_by(digest: digest)).to be_present
    end

    it 'rejects wrong digest' do
      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      patch "/v2/#{repo_name}/blobs/uploads/#{uuid}",
            params: 'some data',
            headers: { 'CONTENT_TYPE' => 'application/octet-stream' }

      put "/v2/#{repo_name}/blobs/uploads/#{uuid}?digest=sha256:wrong"

      expect(response).to have_http_status(400)
      expect(JSON.parse(response.body)['errors'][0]['code']).to eq('DIGEST_INVALID')
    end
  end

  describe 'POST /v2/:name/blobs/uploads?mount=&from= (cross-repo mount)' do
    it 'mounts existing blob from another repo' do
      # Push a blob to source repo first
      content = 'shared layer'
      digest = DigestCalculator.compute(content)
      source_repo = Repository.create!(name: 'source-repo')
      Blob.create!(digest: digest, size: content.bytesize)
      BlobStore.new.put(digest, StringIO.new(content))

      post "/v2/#{repo_name}/blobs/uploads?mount=#{digest}&from=source-repo"

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
    end

    it 'falls back to regular upload if blob not found' do
      post "/v2/#{repo_name}/blobs/uploads?mount=sha256:nonexistent&from=other-repo"

      expect(response).to have_http_status(202)
      expect(response.headers['Docker-Upload-UUID']).to be_present
    end
  end

  describe 'DELETE /v2/:name/blobs/uploads/:uuid' do
    it 'cancels upload' do
      post "/v2/#{repo_name}/blobs/uploads"
      uuid = response.headers['Docker-Upload-UUID']

      delete "/v2/#{repo_name}/blobs/uploads/#{uuid}"
      expect(response).to have_http_status(204)
      expect(BlobUpload.find_by(uuid: uuid)).to be_nil
    end
  end
end
```

- [x] **Step 2: Implement BlobUploadsController**

Create `app/controllers/v2/blob_uploads_controller.rb`:

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

    response.headers['Location'] = upload_url(upload)
    response.headers['Docker-Upload-UUID'] = upload.uuid
    response.headers['Range'] = "0-#{upload.byte_offset - 1}"
    head :accepted
  end

  def complete
    upload = find_upload!
    digest = params[:digest]

    if request.body.size > 0
      blob_store.append_upload(upload.uuid, request.body)
    end

    blob_store.finalize_upload(upload.uuid, digest)

    blob = Blob.create_or_find_by!(digest: digest) do |b|
      b.size = blob_store.size(digest)
      b.content_type = 'application/octet-stream'
    end

    upload.destroy!

    response.headers['Docker-Content-Digest'] = digest
    response.headers['Location'] = "/v2/#{params[:name]}/blobs/#{digest}"
    head :created
  end

  def destroy
    upload = find_upload!
    blob_store.cancel_upload(upload.uuid)
    upload.destroy!
    head :no_content
  end

  private

  def ensure_repository!
    @repository = Repository.find_or_create_by!(name: params[:name])
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

    response.headers['Location'] = upload_url(upload)
    response.headers['Docker-Upload-UUID'] = uuid
    response.headers['Range'] = '0-0'
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
      b.content_type = 'application/octet-stream'
    end

    response.headers['Docker-Content-Digest'] = digest
    response.headers['Location'] = "/v2/#{params[:name]}/blobs/#{digest}"
    head :created
  end

  def handle_blob_mount
    blob = Blob.find_by(digest: params[:mount])

    if blob && blob_store.exists?(params[:mount])
      ensure_repository!
      blob.increment!(:references_count)

      response.headers['Docker-Content-Digest'] = params[:mount]
      response.headers['Location'] = "/v2/#{params[:name]}/blobs/#{params[:mount]}"
      head :created
    else
      handle_start_upload
    end
  end

  def upload_url(upload)
    "/v2/#{params[:name]}/blobs/uploads/#{upload.uuid}"
  end

  def blob_store
    @blob_store ||= BlobStore.new
  end
end
```

- [x] **Step 3: Run tests**

```bash
bundle exec rspec spec/requests/v2/blob_uploads_spec.rb
```

Expected: All pass.

- [x] **Step 4: Commit**

```bash
git add app/controllers/v2/blob_uploads_controller.rb spec/requests/v2/blob_uploads_spec.rb
git commit -m "feat: add V2 blob uploads controller with chunked, monolithic, and cross-repo mount support"
```

---

### Task 10: Manifests Controller

**Files:**
- Create: `app/controllers/v2/manifests_controller.rb`
- Create: `spec/requests/v2/manifests_spec.rb`

- [x] **Step 1: Write spec**

Create `spec/requests/v2/manifests_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'V2 Manifests API', type: :request do
  let(:blob_store) { BlobStore.new }
  let(:repo_name) { 'test-repo' }

  let(:config_content) { File.read(Rails.root.join('spec/fixtures/configs/image_config.json')) }
  let(:config_digest) { DigestCalculator.compute(config_content) }
  let(:layer_content) { SecureRandom.random_bytes(1024) }
  let(:layer_digest) { DigestCalculator.compute(layer_content) }

  let(:manifest_payload) do
    {
      schemaVersion: 2,
      mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
      config: { mediaType: 'application/vnd.docker.container.image.v1+json', size: config_content.bytesize, digest: config_digest },
      layers: [{ mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip', size: layer_content.bytesize, digest: layer_digest }]
    }.to_json
  end

  before do
    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(layer_digest, StringIO.new(layer_content))
    Blob.create!(digest: config_digest, size: config_content.bytesize)
    Blob.create!(digest: layer_digest, size: layer_content.bytesize)
  end

  describe 'PUT /v2/:name/manifests/:reference' do
    it 'creates manifest and tag' do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }

      expect(response).to have_http_status(201)
      expect(response.headers['Docker-Content-Digest']).to start_with('sha256:')
    end

    it 'rejects unsupported media type' do
      put "/v2/#{repo_name}/manifests/v1",
          params: '{}',
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.list.v2+json' }

      expect(response).to have_http_status(415)
      expect(JSON.parse(response.body)['errors'][0]['code']).to eq('UNSUPPORTED')
    end
  end

  describe 'GET /v2/:name/manifests/:reference' do
    before do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }
    end

    it 'returns manifest by tag' do
      get "/v2/#{repo_name}/manifests/v1.0.0"

      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to start_with('sha256:')
      expect(response.headers['Content-Type']).to eq('application/vnd.docker.distribution.manifest.v2+json')
      expect(JSON.parse(response.body)['schemaVersion']).to eq(2)
    end

    it 'returns manifest by digest' do
      digest = response.headers['Docker-Content-Digest']
      get "/v2/#{repo_name}/manifests/#{digest}"
      expect(response).to have_http_status(200)
    end

    it 'increments pull_count on GET' do
      get "/v2/#{repo_name}/manifests/v1.0.0"
      manifest = Manifest.last
      expect(manifest.pull_count).to eq(1)
    end

    it 'creates a PullEvent on GET' do
      get "/v2/#{repo_name}/manifests/v1.0.0"
      expect(PullEvent.count).to eq(1)
      expect(PullEvent.last.tag_name).to eq('v1.0.0')
    end

    it 'returns 404 for unknown tag' do
      get "/v2/#{repo_name}/manifests/nonexistent"
      expect(response).to have_http_status(404)
    end
  end

  describe 'HEAD /v2/:name/manifests/:reference' do
    before do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }
    end

    it 'returns headers without body' do
      head "/v2/#{repo_name}/manifests/v1.0.0"

      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to start_with('sha256:')
      expect(response.body).to be_empty
    end

    it 'does NOT increment pull_count' do
      head "/v2/#{repo_name}/manifests/v1.0.0"
      manifest = Manifest.last
      expect(manifest.pull_count).to eq(0)
    end
  end

  describe 'DELETE /v2/:name/manifests/:digest' do
    before do
      put "/v2/#{repo_name}/manifests/v1.0.0",
          params: manifest_payload,
          headers: { 'CONTENT_TYPE' => 'application/vnd.docker.distribution.manifest.v2+json' }
    end

    it 'deletes manifest and associated tags' do
      digest = Manifest.last.digest
      delete "/v2/#{repo_name}/manifests/#{digest}"

      expect(response).to have_http_status(202)
      expect(Manifest.find_by(digest: digest)).to be_nil
      expect(Tag.count).to eq(0)
    end
  end
end
```

- [x] **Step 2: Implement ManifestsController**

Create `app/controllers/v2/manifests_controller.rb`:

```ruby
class V2::ManifestsController < V2::BaseController
  SUPPORTED_MEDIA_TYPES = [
    'application/vnd.docker.distribution.manifest.v2+json'
  ].freeze

  def show
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

    response.headers['Docker-Content-Digest'] = manifest.digest
    response.headers['Content-Type'] = manifest.media_type
    response.headers['Content-Length'] = manifest.size.to_s

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

    payload = request.body.read
    manifest = ManifestProcessor.new.call(
      params[:name],
      params[:reference],
      request.content_type,
      payload
    )

    response.headers['Docker-Content-Digest'] = manifest.digest
    response.headers['Location'] = "/v2/#{params[:name]}/manifests/#{manifest.digest}"
    head :created
  end

  def destroy
    repository = find_repository!
    manifest = find_manifest!(repository, params[:reference])

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

    manifest.layers.each do |layer|
      layer.blob.decrement!(:references_count)
    end

    manifest.destroy!
    head :accepted
  end

  private

  def find_manifest!(repository, reference)
    if reference.start_with?('sha256:')
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

    tag_name = params[:reference].start_with?('sha256:') ? nil : params[:reference]
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

- [x] **Step 3: Run tests**

```bash
bundle exec rspec spec/requests/v2/manifests_spec.rb
```

Expected: All pass.

- [x] **Step 4: Commit**

```bash
git add app/controllers/v2/manifests_controller.rb spec/requests/v2/manifests_spec.rb
git commit -m "feat: add V2 manifests controller with HEAD/GET/PUT/DELETE, pull tracking, and media type validation"
```

---

### Task 11: Blobs Controller

**Files:**
- Create: `app/controllers/v2/blobs_controller.rb`
- Create: `spec/requests/v2/blobs_spec.rb`

- [x] **Step 1: Write spec**

Create `spec/requests/v2/blobs_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'V2 Blobs API', type: :request do
  let(:blob_store) { BlobStore.new }
  let(:repo_name) { 'test-repo' }
  let(:content) { 'blob content data' }
  let(:digest) { DigestCalculator.compute(content) }

  before do
    Repository.create!(name: repo_name)
    Blob.create!(digest: digest, size: content.bytesize)
    blob_store.put(digest, StringIO.new(content))
  end

  describe 'GET /v2/:name/blobs/:digest' do
    it 'returns blob content' do
      get "/v2/#{repo_name}/blobs/#{digest}"
      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
      expect(response.headers['Content-Length']).to eq(content.bytesize.to_s)
    end

    it 'returns 404 for unknown digest' do
      get "/v2/#{repo_name}/blobs/sha256:nonexistent"
      expect(response).to have_http_status(404)
    end
  end

  describe 'HEAD /v2/:name/blobs/:digest' do
    it 'returns headers without body' do
      head "/v2/#{repo_name}/blobs/#{digest}"
      expect(response).to have_http_status(200)
      expect(response.headers['Docker-Content-Digest']).to eq(digest)
      expect(response.body).to be_empty
    end
  end

  describe 'DELETE /v2/:name/blobs/:digest' do
    it 'deletes blob' do
      delete "/v2/#{repo_name}/blobs/#{digest}"
      expect(response).to have_http_status(202)
    end
  end
end
```

- [x] **Step 2: Implement BlobsController**

Create `app/controllers/v2/blobs_controller.rb`:

```ruby
class V2::BlobsController < V2::BaseController
  def show
    find_repository!
    blob = Blob.find_by!(digest: params[:digest])
    blob_store = BlobStore.new

    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found" unless blob_store.exists?(params[:digest])

    response.headers['Docker-Content-Digest'] = blob.digest
    response.headers['Content-Length'] = blob.size.to_s
    response.headers['Content-Type'] = blob.content_type || 'application/octet-stream'

    if request.head?
      head :ok
    else
      send_file blob_store.path_for(blob.digest), type: 'application/octet-stream', disposition: 'inline'
    end
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found"
  end

  def destroy
    find_repository!
    blob = Blob.find_by!(digest: params[:digest])
    BlobStore.new.delete(blob.digest)
    blob.destroy!
    head :accepted
  rescue ActiveRecord::RecordNotFound
    raise Registry::BlobUnknown, "blob '#{params[:digest]}' not found"
  end
end
```

- [x] **Step 3: Run tests**

```bash
bundle exec rspec spec/requests/v2/blobs_spec.rb
```

Expected: All pass.

- [x] **Step 4: Commit**

```bash
git add app/controllers/v2/blobs_controller.rb spec/requests/v2/blobs_spec.rb
git commit -m "feat: add V2 blobs controller with HEAD/GET/DELETE and send_file streaming"
```

---

### Task 12: Catalog and Tags Controllers

**Files:**
- Create: `app/controllers/v2/catalog_controller.rb`
- Create: `app/controllers/v2/tags_controller.rb`
- Create: `spec/requests/v2/catalog_spec.rb`
- Create: `spec/requests/v2/tags_spec.rb`

- [x] **Step 1: Write catalog spec**

Create `spec/requests/v2/catalog_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'V2 Catalog API', type: :request do
  before do
    %w[alpha bravo charlie].each { |n| Repository.create!(name: n) }
  end

  describe 'GET /v2/_catalog' do
    it 'returns all repositories' do
      get '/v2/_catalog'
      expect(response).to have_http_status(200)
      body = JSON.parse(response.body)
      expect(body['repositories']).to eq(%w[alpha bravo charlie])
    end

    it 'paginates with n and last' do
      get '/v2/_catalog?n=2'
      body = JSON.parse(response.body)
      expect(body['repositories']).to eq(%w[alpha bravo])
      expect(response.headers['Link']).to include('rel="next"')

      get '/v2/_catalog?n=2&last=bravo'
      body = JSON.parse(response.body)
      expect(body['repositories']).to eq(%w[charlie])
      expect(response.headers['Link']).to be_nil
    end
  end
end
```

- [x] **Step 2: Write tags spec**

Create `spec/requests/v2/tags_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'V2 Tags API', type: :request do
  let(:repo) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repo, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }

  before do
    %w[v1.0.0 v2.0.0 latest].each { |t| Tag.create!(repository: repo, manifest: manifest, name: t) }
  end

  describe 'GET /v2/:name/tags/list' do
    it 'returns all tags' do
      get "/v2/#{repo.name}/tags/list"
      body = JSON.parse(response.body)
      expect(body['name']).to eq('test-repo')
      expect(body['tags']).to eq(%w[latest v1.0.0 v2.0.0])
    end

    it 'paginates with n and last' do
      get "/v2/#{repo.name}/tags/list?n=2"
      body = JSON.parse(response.body)
      expect(body['tags'].length).to eq(2)
      expect(response.headers['Link']).to include('rel="next"')
    end

    it 'returns 404 for unknown repo' do
      get '/v2/nonexistent/tags/list'
      expect(response).to have_http_status(404)
    end
  end
end
```

- [x] **Step 3: Implement controllers**

Create `app/controllers/v2/catalog_controller.rb`:

```ruby
class V2::CatalogController < V2::BaseController
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
end
```

Create `app/controllers/v2/tags_controller.rb`:

```ruby
class V2::TagsController < V2::BaseController
  def index
    repository = find_repository!
    n = (params[:n] || 100).to_i.clamp(1, 1000)
    scope = repository.tags.order(:name)
    scope = scope.where('name > ?', params[:last]) if params[:last].present?
    tags = scope.limit(n + 1).pluck(:name)

    if tags.size > n
      tags.pop
      response.headers['Link'] = "</v2/#{repository.name}/tags/list?n=#{n}&last=#{tags.last}>; rel=\"next\""
    end

    render json: { name: repository.name, tags: tags }
  end
end
```

- [x] **Step 4: Run tests**

```bash
bundle exec rspec spec/requests/v2/catalog_spec.rb spec/requests/v2/tags_spec.rb
```

Expected: All pass.

- [x] **Step 5: Commit**

```bash
git add app/controllers/v2/catalog_controller.rb app/controllers/v2/tags_controller.rb \
        spec/requests/v2/catalog_spec.rb spec/requests/v2/tags_spec.rb
git commit -m "feat: add V2 catalog and tags controllers with Link header pagination"
```

---

### Task 13: Docker CLI Integration Test

**Files:**
- Create: `test/integration/docker_cli_test.sh`

- [x] **Step 1: Create integration test script**

Create `test/integration/docker_cli_test.sh`:

```bash
#!/bin/bash
set -e

REGISTRY=${REGISTRY:-localhost:3000}

echo "=== Docker CLI Integration Test ==="
echo "Registry: $REGISTRY"
echo ""

# Test 1: Push an image
echo "--- Test 1: Build and push image ---"
echo "FROM alpine:latest" | docker build -t $REGISTRY/test-image:v1 -
docker push $REGISTRY/test-image:v1
echo "PASS: Push succeeded"

# Test 2: Pull the image back
echo "--- Test 2: Pull image ---"
docker rmi $REGISTRY/test-image:v1
docker pull $REGISTRY/test-image:v1
echo "PASS: Pull succeeded"

# Test 3: Push second tag (tests cross-repo mount)
echo "--- Test 3: Push second tag (mount test) ---"
docker tag $REGISTRY/test-image:v1 $REGISTRY/test-image:v2
docker push $REGISTRY/test-image:v2
echo "PASS: Second tag push succeeded (shared layers mounted)"

# Test 4: Verify catalog
echo "--- Test 4: Verify catalog ---"
CATALOG=$(curl -sf http://$REGISTRY/v2/_catalog)
echo "Catalog: $CATALOG"
echo "$CATALOG" | grep -q "test-image" || { echo "FAIL: test-image not in catalog"; exit 1; }
echo "PASS: Catalog contains test-image"

# Test 5: Verify tags
echo "--- Test 5: Verify tags ---"
TAGS=$(curl -sf http://$REGISTRY/v2/test-image/tags/list)
echo "Tags: $TAGS"
echo "$TAGS" | grep -q "v1" || { echo "FAIL: v1 not in tags"; exit 1; }
echo "$TAGS" | grep -q "v2" || { echo "FAIL: v2 not in tags"; exit 1; }
echo "PASS: Tags list correct"

# Test 6: HEAD manifest
echo "--- Test 6: HEAD manifest ---"
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -I http://$REGISTRY/v2/test-image/manifests/v1)
[ "$HTTP_CODE" = "200" ] || { echo "FAIL: HEAD manifest returned $HTTP_CODE"; exit 1; }
echo "PASS: HEAD manifest returns 200"

# Cleanup
echo "--- Cleanup ---"
docker rmi $REGISTRY/test-image:v1 $REGISTRY/test-image:v2 2>/dev/null || true

echo ""
echo "=== All Docker CLI integration tests PASSED ==="
```

- [x] **Step 2: Make executable**

```bash
chmod +x test/integration/docker_cli_test.sh
```

- [x] **Step 3: Commit**

```bash
git add test/integration/docker_cli_test.sh
git commit -m "feat: add Docker CLI integration test script for push/pull/mount/catalog verification"
```

---

## Phase 3: Web UI + Import/Export

**Outcome:** Web UI for browsing repositories, tags, details. Tar import/export with async processing. Repository description editing. Docker pull command with real host.

---

### Task 14: Web UI — Repository List and Detail

**Files:**
- Modify: `app/controllers/repositories_controller.rb`
- Create: `app/controllers/tags_controller.rb`
- Modify: `app/views/repositories/index.html.erb`
- Create: `app/views/repositories/show.html.erb`
- Create: `app/views/repositories/_repository_card.html.erb`
- Create: `app/views/tags/show.html.erb`
- Modify: `app/helpers/repositories_helper.rb`
- Modify: `config/routes.rb` — add web UI routes
- Create: `spec/requests/repositories_spec.rb`

- [x] **Step 1: Update routes for web UI**

Add web UI routes to `config/routes.rb` (before the V2 scope):

```ruby
root "repositories#index"

resources :repositories, only: [:index, :show, :update, :destroy], param: :name,
                         constraints: { name: /[^\/]+(?:\/[^\/]+)*/ } do
  resources :tags, only: [:show, :destroy], param: :name do
    member do
      get :export
      get :history
      get :compare
    end
  end

  member do
    get :pull_stats
    get :dependency_graph
  end

  collection do
    post :import
  end
end

resources :imports, only: [:show]
resources :exports, only: [:show]
```

- [x] **Step 2: Implement RepositoriesController**

Replace `app/controllers/repositories_controller.rb`:

```ruby
class RepositoriesController < ApplicationController
  def index
    @repositories = Repository.all.order(updated_at: :desc)

    if params[:q].present?
      q = "%#{params[:q]}%"
      @repositories = @repositories.where('name LIKE ? OR description LIKE ? OR maintainer LIKE ?', q, q, q)
    end

    case params[:sort]
    when 'name' then @repositories = @repositories.reorder(:name)
    when 'size' then @repositories = @repositories.reorder(total_size: :desc)
    when 'pulls'
      @repositories = @repositories
        .left_joins(:manifests)
        .group(:id)
        .reorder(Arel.sql('COALESCE(SUM(manifests.pull_count), 0) DESC'))
    end
  end

  def show
    @repository = Repository.find_by!(name: params[:name])
    @tags = @repository.tags.includes(:manifest).order(updated_at: :desc)
  end

  def update
    @repository = Repository.find_by!(name: params[:name])
    @repository.update!(repository_params)
    redirect_to repository_path(@repository.name), notice: 'Repository updated.'
  end

  def destroy
    repository = Repository.find_by!(name: params[:name])

    repository.manifests.includes(:layers => :blob).find_each do |manifest|
      manifest.layers.each { |layer| layer.blob.decrement!(:references_count) }
    end

    repository.destroy!
    redirect_to root_path, notice: "Repository '#{repository.name}' deleted."
  end

  private

  def repository_params
    params.require(:repository).permit(:description, :maintainer)
  end
end
```

- [x] **Step 3: Implement TagsController**

Create `app/controllers/tags_controller.rb`:

```ruby
class TagsController < ApplicationController
  before_action :set_repository
  before_action :set_tag, only: [:show, :destroy, :export, :history, :compare]

  def show
    @manifest = @tag.manifest
    @layers = @manifest.layers.includes(:blob).order(:position)
  end

  def destroy
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
  end

  def history
    @events = TagEvent.where(repository: @repository, tag_name: @tag.name).order(occurred_at: :desc)
  end

  def compare
    @other_tag = @repository.tags.find_by!(name: params[:with])
    @diff = TagDiffService.new.call(@tag.manifest, @other_tag.manifest)
  end

  def export
    # Placeholder for Phase 3 async export — will be implemented in Task 16
    redirect_to repository_tag_path(@repository.name, @tag.name), alert: 'Export not yet implemented.'
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

- [x] **Step 4: Implement repositories_helper**

Replace `app/helpers/repositories_helper.rb`:

```ruby
module RepositoriesHelper
  def docker_pull_command(repository_name, tag_name = 'latest')
    host = Rails.configuration.registry_host
    "docker pull #{host}/#{repository_name}:#{tag_name}"
  end

  def human_size(bytes)
    return '0 B' if bytes.nil? || bytes == 0

    units = ['B', 'KB', 'MB', 'GB', 'TB']
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.length - 1 if exp >= units.length
    format('%.1f %s', bytes.to_f / 1024**exp, units[exp])
  end

  def short_digest(digest)
    return '' unless digest
    digest.sub('sha256:', '')[0..11]
  end
end
```

- [x] **Step 5: Create view templates**

Create `app/views/repositories/index.html.erb`, `app/views/repositories/show.html.erb`, `app/views/repositories/_repository_card.html.erb`, `app/views/tags/show.html.erb`, `app/views/tags/history.html.erb` — these follow existing TailwindCSS patterns from the current codebase. Implementation details for ERB templates should follow the existing blue pastel theme and dark mode patterns.

(Note for implementer: Reference existing `app/views/repositories/index.html.erb` and `app/views/repositories/show.html.erb` for layout patterns. Adapt them to use the new ActiveRecord-backed Repository and Tag models instead of the old in-memory models. Add description/maintainer display and edit fields. Add pull count column to tag tables.)

- [x] **Step 6: Write request spec**

Create `spec/requests/repositories_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Repositories', type: :request do
  let!(:repo) { Repository.create!(name: 'test-repo', description: 'Test', maintainer: 'Team A') }
  let!(:manifest) { Manifest.create!(repository: repo, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }
  let!(:tag) { Tag.create!(repository: repo, manifest: manifest, name: 'v1.0.0') }

  describe 'GET /' do
    it 'lists repositories' do
      get root_path
      expect(response).to have_http_status(200)
      expect(response.body).to include('test-repo')
    end

    it 'searches by name' do
      get root_path, params: { q: 'test' }
      expect(response.body).to include('test-repo')
    end
  end

  describe 'GET /repositories/:name' do
    it 'shows repository details' do
      get repository_path('test-repo')
      expect(response).to have_http_status(200)
      expect(response.body).to include('v1.0.0')
    end
  end

  describe 'PATCH /repositories/:name' do
    it 'updates description' do
      patch repository_path('test-repo'), params: { repository: { description: 'Updated' } }
      expect(response).to redirect_to(repository_path('test-repo'))
      expect(repo.reload.description).to eq('Updated')
    end
  end

  describe 'DELETE /repositories/:name' do
    it 'destroys repository' do
      delete repository_path('test-repo')
      expect(response).to redirect_to(root_path)
      expect(Repository.find_by(name: 'test-repo')).to be_nil
    end
  end
end
```

- [x] **Step 7: Run tests**

```bash
bundle exec rspec spec/requests/repositories_spec.rb
```

Expected: All pass.

- [x] **Step 8: Commit**

```bash
git add app/controllers/ app/views/ app/helpers/ config/routes.rb spec/requests/repositories_spec.rb
git commit -m "feat: add web UI for repository listing, detail, editing, deletion, and tag management"
```

---

### Task 15: TagDiffService and DependencyAnalyzer

**Files:**
- Create: `app/services/tag_diff_service.rb`
- Create: `app/services/dependency_analyzer.rb`
- Create: `spec/services/tag_diff_service_spec.rb`
- Create: `spec/services/dependency_analyzer_spec.rb`

- [x] **Step 1: Write TagDiffService spec**

Create `spec/services/tag_diff_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe TagDiffService do
  let(:repo) { Repository.create!(name: 'test-repo') }
  let(:shared_blob) { Blob.create!(digest: 'sha256:shared', size: 1024) }
  let(:old_blob) { Blob.create!(digest: 'sha256:old', size: 512) }
  let(:new_blob) { Blob.create!(digest: 'sha256:new', size: 2048) }

  let(:manifest_a) do
    m = Manifest.create!(repository: repo, digest: 'sha256:ma', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
                         payload: '{}', size: 100, docker_config: '{"Cmd":["/bin/sh"]}', architecture: 'amd64', os: 'linux')
    Layer.create!(manifest: m, blob: shared_blob, position: 0)
    Layer.create!(manifest: m, blob: old_blob, position: 1)
    m
  end

  let(:manifest_b) do
    m = Manifest.create!(repository: repo, digest: 'sha256:mb', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
                         payload: '{}', size: 100, docker_config: '{"Cmd":["/bin/bash"]}', architecture: 'amd64', os: 'linux')
    Layer.create!(manifest: m, blob: shared_blob, position: 0)
    Layer.create!(manifest: m, blob: new_blob, position: 1)
    m
  end

  describe '#call' do
    it 'identifies common, added, and removed layers' do
      result = TagDiffService.new.call(manifest_a, manifest_b)

      expect(result[:common_layers]).to include('sha256:shared')
      expect(result[:removed_layers]).to include('sha256:old')
      expect(result[:added_layers]).to include('sha256:new')
    end

    it 'computes size delta' do
      result = TagDiffService.new.call(manifest_a, manifest_b)
      expect(result[:size_delta]).to eq(2048 - 512)
    end

    it 'computes config diff' do
      result = TagDiffService.new.call(manifest_a, manifest_b)
      expect(result[:config_diff]).to be_a(Hash)
    end
  end
end
```

- [x] **Step 2: Implement TagDiffService**

Create `app/services/tag_diff_service.rb`:

```ruby
class TagDiffService
  def call(manifest_a, manifest_b)
    layers_a = manifest_a.layers.includes(:blob).map { |l| l.blob.digest }
    layers_b = manifest_b.layers.includes(:blob).map { |l| l.blob.digest }

    common = layers_a & layers_b
    removed = layers_a - layers_b
    added = layers_b - layers_a

    size_a = Blob.where(digest: layers_a).sum(:size)
    size_b = Blob.where(digest: layers_b).sum(:size)

    config_a = parse_config(manifest_a.docker_config)
    config_b = parse_config(manifest_b.docker_config)

    {
      common_layers: common,
      removed_layers: removed,
      added_layers: added,
      size_delta: size_b - size_a,
      config_diff: diff_configs(config_a, config_b)
    }
  end

  private

  def parse_config(json_string)
    json_string.present? ? JSON.parse(json_string) : {}
  rescue JSON::ParserError
    {}
  end

  def diff_configs(a, b)
    all_keys = (a.keys + b.keys).uniq
    diff = {}
    all_keys.each do |key|
      next if a[key] == b[key]
      diff[key] = { before: a[key], after: b[key] }
    end
    diff
  end
end
```

- [x] **Step 3: Write DependencyAnalyzer spec**

Create `spec/services/dependency_analyzer_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe DependencyAnalyzer do
  let(:shared_blob) { Blob.create!(digest: 'sha256:shared', size: 1024) }
  let(:unique_blob) { Blob.create!(digest: 'sha256:unique', size: 512) }

  let(:repo_a) { Repository.create!(name: 'repo-a') }
  let(:repo_b) { Repository.create!(name: 'repo-b') }

  before do
    ma = Manifest.create!(repository: repo_a, digest: 'sha256:ma', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
    Layer.create!(manifest: ma, blob: shared_blob, position: 0)
    Layer.create!(manifest: ma, blob: unique_blob, position: 1)

    mb = Manifest.create!(repository: repo_b, digest: 'sha256:mb', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
    Layer.create!(manifest: mb, blob: shared_blob, position: 0)
  end

  describe '#call' do
    it 'identifies repositories sharing layers' do
      result = DependencyAnalyzer.new.call(repo_a)
      expect(result.length).to eq(1)
      expect(result[0][:repository]).to eq('repo-b')
      expect(result[0][:shared_layers]).to eq(1)
    end
  end
end
```

- [x] **Step 4: Implement DependencyAnalyzer**

Create `app/services/dependency_analyzer.rb`:

```ruby
class DependencyAnalyzer
  def call(repository)
    layer_digests = repository.manifests
      .joins(:layers => :blob)
      .pluck('blobs.digest')
      .uniq

    return [] if layer_digests.empty?

    other_repos = Repository
      .where.not(id: repository.id)
      .joins(manifests: { layers: :blob })
      .where(blobs: { digest: layer_digests })
      .group('repositories.id')
      .select('repositories.*, COUNT(DISTINCT blobs.digest) as shared_count')

    other_repos.map do |repo|
      total_layers = repo.manifests.joins(:layers).distinct.count('layers.blob_id')
      {
        repository: repo.name,
        shared_layers: repo.shared_count.to_i,
        total_layers: total_layers,
        ratio: total_layers > 0 ? repo.shared_count.to_f / total_layers : 0
      }
    end
  end
end
```

- [x] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/tag_diff_service_spec.rb spec/services/dependency_analyzer_spec.rb
```

Expected: All pass.

- [x] **Step 6: Commit**

```bash
git add app/services/tag_diff_service.rb app/services/dependency_analyzer.rb \
        spec/services/tag_diff_service_spec.rb spec/services/dependency_analyzer_spec.rb
git commit -m "feat: add TagDiffService for layer/config comparison and DependencyAnalyzer for shared layer detection"
```

---

### Task 16: Async Import/Export with Solid Queue

**Files:**
- Create: `app/services/image_import_service.rb`
- Create: `app/services/image_export_service.rb`
- Create: `app/jobs/process_tar_import_job.rb`
- Create: `app/jobs/prepare_export_job.rb`
- Create: `spec/services/image_import_service_spec.rb`
- Create: `spec/services/image_export_service_spec.rb`
- Create: `spec/jobs/process_tar_import_job_spec.rb`

- [x] **Step 1: Write ImageImportService spec**

Create `spec/services/image_import_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe ImageImportService do
  let(:store_dir) { Dir.mktmpdir }
  let(:blob_store) { BlobStore.new(store_dir) }
  let(:service) { ImageImportService.new(blob_store) }

  after { FileUtils.rm_rf(store_dir) }

  describe '#call' do
    it 'imports a docker save tar file' do
      # Create a minimal docker save tar for testing
      tar_path = create_test_docker_tar(store_dir)

      result = service.call(tar_path, repository_name: 'imported-image', tag_name: 'v1')

      expect(result).to be_a(Manifest)
      expect(Repository.find_by(name: 'imported-image')).to be_present
      expect(Tag.find_by(name: 'v1')).to be_present
    end
  end

  private

  def create_test_docker_tar(dir)
    # Build a minimal docker save compatible tar
    tar_path = File.join(dir, 'test.tar')

    config_content = '{"architecture":"amd64","os":"linux","config":{"Cmd":["/bin/sh"]}}'
    config_digest = Digest::SHA256.hexdigest(config_content)

    layer_content = SecureRandom.random_bytes(256)
    layer_digest = Digest::SHA256.hexdigest(layer_content)

    manifest_list = [{
      'Config' => "#{config_digest}.json",
      'RepoTags' => ['imported-image:v1'],
      'Layers' => ["#{layer_digest}/layer.tar"]
    }]

    # Write tar file
    File.open(tar_path, 'wb') do |tar_io|
      Gem::Package::TarWriter.new(tar_io) do |tar|
        tar.add_file_simple('manifest.json', 0644, manifest_list.to_json.bytesize) { |f| f.write(manifest_list.to_json) }
        tar.add_file_simple("#{config_digest}.json", 0644, config_content.bytesize) { |f| f.write(config_content) }
        tar.mkdir("#{layer_digest}", 0755)
        tar.add_file_simple("#{layer_digest}/layer.tar", 0644, layer_content.bytesize) { |f| f.write(layer_content) }
      end
    end

    tar_path
  end
end
```

- [x] **Step 2: Implement ImageImportService**

Create `app/services/image_import_service.rb`:

```ruby
class ImageImportService
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(tar_path, repository_name: nil, tag_name: nil)
    entries = {}

    File.open(tar_path, 'rb') do |tar_io|
      Gem::Package::TarReader.new(tar_io) do |tar|
        tar.each do |entry|
          entries[entry.full_name] = entry.read if entry.file?
        end
      end
    end

    manifest_list = JSON.parse(entries['manifest.json'])
    image_manifest = manifest_list.first

    repo_name = repository_name || extract_repo_name(image_manifest)
    tag = tag_name || extract_tag_name(image_manifest)

    # Store config blob
    config_filename = image_manifest['Config']
    config_content = entries[config_filename]
    config_digest = DigestCalculator.compute(config_content)
    @blob_store.put(config_digest, StringIO.new(config_content))
    Blob.create_or_find_by!(digest: config_digest) { |b| b.size = config_content.bytesize }

    # Store layer blobs
    layer_digests = []
    image_manifest['Layers'].each do |layer_path|
      layer_content = entries[layer_path]
      layer_digest = DigestCalculator.compute(layer_content)
      @blob_store.put(layer_digest, StringIO.new(layer_content))
      Blob.create_or_find_by!(digest: layer_digest) { |b| b.size = layer_content.bytesize }
      layer_digests << { digest: layer_digest, size: layer_content.bytesize }
    end

    # Build and process V2 manifest
    v2_manifest = build_v2_manifest(config_digest, config_content.bytesize, layer_digests)
    processor = ManifestProcessor.new(@blob_store)
    processor.call(repo_name, tag, 'application/vnd.docker.distribution.manifest.v2+json', v2_manifest.to_json)
  end

  private

  def extract_repo_name(image_manifest)
    repo_tag = image_manifest['RepoTags']&.first
    return 'imported' unless repo_tag
    repo_tag.split(':').first
  end

  def extract_tag_name(image_manifest)
    repo_tag = image_manifest['RepoTags']&.first
    return 'latest' unless repo_tag
    repo_tag.split(':').last
  end

  def build_v2_manifest(config_digest, config_size, layer_digests)
    {
      schemaVersion: 2,
      mediaType: 'application/vnd.docker.distribution.manifest.v2+json',
      config: {
        mediaType: 'application/vnd.docker.container.image.v1+json',
        size: config_size,
        digest: config_digest
      },
      layers: layer_digests.map do |ld|
        {
          mediaType: 'application/vnd.docker.image.rootfs.diff.tar.gzip',
          size: ld[:size],
          digest: ld[:digest]
        }
      end
    }
  end
end
```

- [x] **Step 3: Implement Jobs**

Create `app/jobs/process_tar_import_job.rb`:

```ruby
class ProcessTarImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Import.find(import_id)
    import.update!(status: 'processing', progress: 10)

    begin
      manifest = ImageImportService.new.call(
        import.tar_path,
        repository_name: import.repository_name,
        tag_name: import.tag_name
      )
      import.update!(status: 'completed', progress: 100)

      broadcast_import_status(import)
    rescue => e
      import.update!(status: 'failed', error_message: e.message)
      broadcast_import_status(import)
      raise
    end
  end

  private

  def broadcast_import_status(import)
    Turbo::StreamsChannel.broadcast_replace_to(
      "import_#{import.id}",
      target: "import_#{import.id}",
      partial: 'imports/status',
      locals: { import: import }
    )
  end
end
```

Create `app/jobs/prepare_export_job.rb`:

```ruby
class PrepareExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    export = Export.find(export_id)
    export.update!(status: 'processing')

    begin
      output_path = File.join(
        Rails.configuration.storage_path, 'tmp', 'exports', "#{export.id}.tar"
      )
      FileUtils.mkdir_p(File.dirname(output_path))

      ImageExportService.new.call(
        export.repository.name,
        export.tag_name,
        output_path: output_path
      )

      export.update!(status: 'completed', output_path: output_path)
      broadcast_export_status(export)
    rescue => e
      export.update!(status: 'failed', error_message: e.message)
      broadcast_export_status(export)
      raise
    end
  end

  private

  def broadcast_export_status(export)
    Turbo::StreamsChannel.broadcast_replace_to(
      "export_#{export.id}",
      target: "export_#{export.id}",
      partial: 'exports/status',
      locals: { export: export }
    )
  end
end
```

- [x] **Step 4: Implement ImageExportService**

Create `app/services/image_export_service.rb`:

```ruby
class ImageExportService
  def initialize(blob_store = BlobStore.new)
    @blob_store = blob_store
  end

  def call(repository_name, tag_name, output_path:)
    repo = Repository.find_by!(name: repository_name)
    tag = repo.tags.find_by!(name: tag_name)
    manifest = tag.manifest

    config_digest_hex = manifest.config_digest.sub('sha256:', '')
    layers = manifest.layers.includes(:blob).order(:position)

    File.open(output_path, 'wb') do |tar_io|
      Gem::Package::TarWriter.new(tar_io) do |tar|
        # manifest.json
        docker_manifest = [{
          'Config' => "#{config_digest_hex}.json",
          'RepoTags' => ["#{repository_name}:#{tag_name}"],
          'Layers' => layers.map { |l| "#{l.blob.digest.sub('sha256:', '')}/layer.tar" }
        }]
        manifest_json = docker_manifest.to_json
        tar.add_file_simple('manifest.json', 0644, manifest_json.bytesize) { |f| f.write(manifest_json) }

        # Config blob
        config_io = @blob_store.get(manifest.config_digest)
        config_data = config_io.read
        config_io.close
        tar.add_file_simple("#{config_digest_hex}.json", 0644, config_data.bytesize) { |f| f.write(config_data) }

        # Layer blobs
        layers.each do |layer|
          layer_io = @blob_store.get(layer.blob.digest)
          layer_data = layer_io.read
          layer_io.close
          digest_hex = layer.blob.digest.sub('sha256:', '')
          tar.mkdir(digest_hex, 0755)
          tar.add_file_simple("#{digest_hex}/layer.tar", 0644, layer_data.bytesize) { |f| f.write(layer_data) }
        end
      end
    end
  end
end
```

- [x] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/image_import_service_spec.rb
```

Expected: All pass.

- [x] **Step 6: Commit**

```bash
git add app/services/image_import_service.rb app/services/image_export_service.rb \
        app/jobs/process_tar_import_job.rb app/jobs/prepare_export_job.rb \
        spec/services/image_import_service_spec.rb
git commit -m "feat: add async tar import/export with Solid Queue jobs and Turbo Stream status updates"
```

---

## Phase 4: Operations (GC, Retention, Deployment)

**Outcome:** Background GC cleans orphaned blobs. Retention policy auto-expires unused images. Production deployment guide and help page.

---

### Task 17: GC and Retention Jobs

**Files:**
- Create: `app/jobs/cleanup_orphaned_blobs_job.rb`
- Create: `app/jobs/enforce_retention_policy_job.rb`
- Create: `app/jobs/prune_old_events_job.rb`
- Create: `config/recurring.yml`
- Create: `spec/jobs/cleanup_orphaned_blobs_job_spec.rb`
- Create: `spec/jobs/enforce_retention_policy_job_spec.rb`

- [x] **Step 1: Write CleanupOrphanedBlobsJob spec**

Create `spec/jobs/cleanup_orphaned_blobs_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe CleanupOrphanedBlobsJob do
  let(:store_dir) { Dir.mktmpdir }
  let(:blob_store) { BlobStore.new(store_dir) }

  before { allow(BlobStore).to receive(:new).and_return(blob_store) }
  after { FileUtils.rm_rf(store_dir) }

  describe '#perform' do
    it 'deletes blobs with references_count == 0' do
      content = 'orphan blob'
      digest = DigestCalculator.compute(content)
      blob_store.put(digest, StringIO.new(content))
      Blob.create!(digest: digest, size: content.bytesize, references_count: 0)

      CleanupOrphanedBlobsJob.perform_now

      expect(Blob.find_by(digest: digest)).to be_nil
      expect(blob_store.exists?(digest)).to be false
    end

    it 'does NOT delete blobs with references_count > 0' do
      content = 'referenced blob'
      digest = DigestCalculator.compute(content)
      blob_store.put(digest, StringIO.new(content))
      Blob.create!(digest: digest, size: content.bytesize, references_count: 1)

      CleanupOrphanedBlobsJob.perform_now

      expect(Blob.find_by(digest: digest)).to be_present
      expect(blob_store.exists?(digest)).to be true
    end
  end
end
```

- [x] **Step 2: Implement GC Job**

Create `app/jobs/cleanup_orphaned_blobs_job.rb`:

```ruby
class CleanupOrphanedBlobsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    cleanup_orphaned_blobs
    cleanup_orphaned_manifests
    blob_store.cleanup_stale_uploads(max_age: 1.hour)
    cleanup_stale_exports
    cleanup_stale_imports
  end

  private

  def cleanup_orphaned_blobs
    Blob.where(references_count: 0).find_each(batch_size: BATCH_SIZE) do |blob|
      blob.reload
      next if blob.references_count > 0

      blob_store.delete(blob.digest)
      blob.destroy!
    end
  end

  def cleanup_orphaned_manifests
    Manifest.left_joins(:tags).where(tags: { id: nil }).find_each(batch_size: BATCH_SIZE) do |manifest|
      manifest.layers.each { |layer| layer.blob.decrement!(:references_count) }
      manifest.destroy!
    end
  end

  def cleanup_stale_exports
    exports_dir = File.join(Rails.configuration.storage_path, 'tmp', 'exports')
    return unless Dir.exist?(exports_dir)

    Export.where(status: ['completed', 'failed']).where('updated_at < ?', 1.hour.ago).find_each do |export|
      FileUtils.rm_f(export.output_path) if export.output_path
      export.destroy!
    end
  end

  def cleanup_stale_imports
    Import.where(status: ['completed', 'failed']).where('updated_at < ?', 24.hours.ago).find_each do |imp|
      FileUtils.rm_f(imp.tar_path) if imp.tar_path
      imp.destroy!
    end
  end

  def blob_store
    @blob_store ||= BlobStore.new
  end
end
```

- [x] **Step 3: Implement Retention Policy Job**

Create `app/jobs/enforce_retention_policy_job.rb`:

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

- [x] **Step 4: Implement Event Pruning Job**

Create `app/jobs/prune_old_events_job.rb`:

```ruby
class PruneOldEventsJob < ApplicationJob
  queue_as :default

  def perform
    PullEvent.where('occurred_at < ?', 90.days.ago).in_batches.delete_all
  end
end
```

- [x] **Step 5: Create recurring schedule**

Create `config/recurring.yml`:

```yaml
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

- [x] **Step 6: Run tests**

```bash
bundle exec rspec spec/jobs/cleanup_orphaned_blobs_job_spec.rb
```

Expected: All pass.

- [x] **Step 7: Commit**

```bash
git add app/jobs/ config/recurring.yml spec/jobs/
git commit -m "feat: add background jobs for GC, retention policy, and event pruning with Solid Queue scheduling"
```

---

### Task 18: Help Page and Production Guide

**Files:**
- Create: `app/controllers/help_controller.rb`
- Create: `app/views/help/show.html.erb`
- Modify: `config/routes.rb` — add help route
- Modify: `config/puma.rb` — production tuning

- [x] **Step 1: Add help route**

Add to `config/routes.rb`:

```ruby
get '/help', to: 'help#show'
```

- [x] **Step 2: Create HelpController**

Create `app/controllers/help_controller.rb`:

```ruby
class HelpController < ApplicationController
  def show
    @registry_host = Rails.configuration.registry_host
  end
end
```

- [x] **Step 3: Create help page view**

Create `app/views/help/show.html.erb` with setup instructions for:
- Docker daemon `insecure-registries` configuration (with `@registry_host` auto-filled)
- Kubernetes containerd mirror configuration
- Nginx reverse proxy configuration
- `docker push`/`docker pull` usage examples
- Multi-arch limitation notice with `--platform` workaround

(Note for implementer: Follow existing TailwindCSS patterns. Use code blocks with copy buttons via clipboard_controller.js. Support dark mode.)

- [x] **Step 4: Update puma.rb for production**

Modify `config/puma.rb` to read from environment:

```ruby
threads_count = ENV.fetch("PUMA_THREADS", 16).to_i
threads threads_count, threads_count

workers ENV.fetch("PUMA_WORKERS", 2).to_i

port ENV.fetch("PORT", 3000)

environment ENV.fetch("RAILS_ENV", "development")

pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

plugin :solid_queue if ENV.fetch("RAILS_ENV", "development") == "production"
```

- [x] **Step 5: Commit**

```bash
git add app/controllers/help_controller.rb app/views/help/ config/routes.rb config/puma.rb
git commit -m "feat: add help page with Docker/K8s client setup guide and production Puma tuning"
```

---

### Task 19: Full Test Suite Verification

- [x] **Step 1: Run all RSpec tests**

```bash
bundle exec rspec
```

Expected: All pass.

- [x] **Step 2: Run E2E tests (if dev server is available)**

```bash
bin/dev &
sleep 5
npx playwright test e2e/repository-list.spec.js e2e/tag-details.spec.js e2e/search.spec.js e2e/dark-mode.spec.js
kill %1
```

- [x] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: verify full test suite passes after self-hosted registry implementation"
```

---

## Summary: File Structure

```
app/
├── controllers/
│   ├── application_controller.rb        (cleaned)
│   ├── repositories_controller.rb       (rewritten)
│   ├── tags_controller.rb               (new)
│   ├── help_controller.rb               (new)
│   └── v2/
│       ├── base_controller.rb           (new)
│       ├── catalog_controller.rb        (new)
│       ├── tags_controller.rb           (new)
│       ├── manifests_controller.rb      (new)
│       ├── blobs_controller.rb          (new)
│       └── blob_uploads_controller.rb   (new)
├── errors/
│   └── registry.rb                      (new)
├── helpers/
│   └── repositories_helper.rb           (rewritten)
├── jobs/
│   ├── cleanup_orphaned_blobs_job.rb    (new)
│   ├── enforce_retention_policy_job.rb  (new)
│   ├── prune_old_events_job.rb          (new)
│   ├── process_tar_import_job.rb        (new)
│   └── prepare_export_job.rb            (new)
├── models/
│   ├── repository.rb                    (rewritten — ActiveRecord)
│   ├── manifest.rb                      (new)
│   ├── tag.rb                           (rewritten — ActiveRecord)
│   ├── blob.rb                          (new)
│   ├── layer.rb                         (new)
│   ├── blob_upload.rb                   (new)
│   ├── tag_event.rb                     (new)
│   ├── pull_event.rb                    (new)
│   ├── import.rb                        (new)
│   └── export.rb                        (new)
├── services/
│   ├── blob_store.rb                    (new)
│   ├── digest_calculator.rb             (new)
│   ├── manifest_processor.rb            (new)
│   ├── image_import_service.rb          (new)
│   ├── image_export_service.rb          (new)
│   ├── tag_diff_service.rb              (new)
│   └── dependency_analyzer.rb           (new)
└── views/
    ├── repositories/                    (rewritten)
    ├── tags/                            (new)
    └── help/                            (new)

config/
├── routes.rb                            (rewritten)
├── puma.rb                              (modified)
├── recurring.yml                        (new)
└── application.rb                       (modified — storage_path, registry_host)

db/
└── migrate/
    └── TIMESTAMP_create_registry_tables.rb  (new)

spec/
├── errors/registry_spec.rb             (new)
├── models/                             (new — all models)
├── services/                           (new — all services)
├── jobs/                               (new — all jobs)
├── requests/
│   ├── v2/                             (new — all V2 endpoints)
│   └── repositories_spec.rb            (rewritten)
└── fixtures/                           (new — manifests, configs)

test/
└── integration/
    └── docker_cli_test.sh              (new)
```
