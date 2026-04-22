# Tag Immutability Design

## Overview

Open Repo currently records tag overwrites in `TagEvent` but does not prevent them. This spec introduces a per-repository tag protection policy that blocks overwriting and deleting protected tags so downstream CI/CD consumers (Jenkins, Kubernetes) can rely on build reproducibility.

### Context

- Primary consumer: Jenkins pulls build images to run build jobs.
- Threat model: **accident prevention**, not malicious-actor defense. The registry is on an internal network with anonymous access (internal users and system accounts).
- Existing building blocks: `ManifestProcessor` is the single choke point for tag mutations; `TagEvent` already records change history; `Repository` already stores per-repo metadata (description, maintainer).

## Goals

- Prevent silent overwrites of release tags (e.g. `v1.2.3`) that break Jenkins build reproducibility.
- Make the protection policy configurable per repository with sensible presets.
- Surface protection state clearly in the Web UI.
- Return a Docker Registry–spec-compliant error that the Docker CLI displays cleanly.

## Non-goals

- Per-tag protection flags. Protection is a repository-level policy only.
- Authentication, authorization, or audit identity tracking. Anonymous access remains; "who changed the policy" is out of scope.
- Protecting tags against deletion by DB-level constraints. A user with shell access to the server can always bypass.
- Preventing deletion of the repository itself.

## Design Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | How protection targets are specified | Per-repository `policy` enum with presets (`none` / `semver` / `all_except_latest` / `custom_regex`) |
| 2 | Floating-tag exception handling | Built into presets (`all_except_latest`); custom regex covers everything else |
| 3 | Delete policy | Both overwrite and delete are blocked. Web UI offers "change policy → delete" two-step flow |
| 4 | Rejection response | `HTTP 409 Conflict` + Docker Registry error envelope with code `DENIED` |
| 5 | Migration of existing data | Default `policy=none`. No auto-protection. Per-repository opt-in |
| 6 | Idempotent re-push | If the tag already points to the same digest, `PUT` is allowed (required for CI retry safety) |

## Data Model

New columns on `repositories`:

```ruby
# db/migrate/20260422XXXXXX_add_tag_protection_to_repositories.rb
add_column :repositories, :tag_protection_policy, :string, null: false, default: "none"
add_column :repositories, :tag_protection_pattern, :string  # used only when policy = "custom_regex"
```

Model changes:

```ruby
# app/models/repository.rb
enum :tag_protection_policy,
     { none: "none", semver: "semver", all_except_latest: "all_except_latest", custom_regex: "custom_regex" },
     default: :none, prefix: :protection

validates :tag_protection_pattern, presence: true, if: :protection_custom_regex?
validate :valid_tag_protection_regex, if: :protection_custom_regex?

SEMVER_PATTERN = /\Av?\d+\.\d+\.\d+(?:[-+][\w.-]+)?\z/

def tag_protected?(tag_name)
  case tag_protection_policy
  when "none"              then false
  when "semver"            then tag_name.match?(SEMVER_PATTERN)
  when "all_except_latest" then tag_name != "latest"
  when "custom_regex"      then tag_name.match?(Regexp.new(tag_protection_pattern))
  end
end

private

def valid_tag_protection_regex
  Regexp.new(tag_protection_pattern)
rescue RegexpError => e
  errors.add(:tag_protection_pattern, "is not a valid regex: #{e.message}")
end
```

Rails 8's default `Regexp.timeout = 1` protects against ReDoS on user-supplied patterns.

Optional environment variable `TAG_PROTECTION_DEFAULT_POLICY` sets the default policy for newly created repositories (default `none`). Applied in `Repository.find_or_create_by(name:)` inside `ManifestProcessor`.

## Enforcement

A single helper `TagImmutabilityError < StandardError` is raised from three call sites.

### 1. Registry `PUT /v2/:name/manifests/:reference`

In `ManifestProcessor`, before persisting the tag:

```
if existing_tag = repo.tags.find_by(name: reference)
  if repo.tag_protected?(reference) && existing_tag.manifest.digest != new_manifest.digest
    raise TagImmutabilityError.new(tag: reference, policy: repo.tag_protection_policy)
  end
end
```

If the existing tag already points to the same digest, the PUT is a no-op and succeeds. This preserves CI retry safety.

### 2. Web UI `DELETE /repositories/:name/tags/:tag_name`

In `TagsController#destroy`, check `repo.tag_protected?(tag.name)` before destroying. On failure, redirect back with a flash error: `"Tag 'v1.2.3' is protected by policy 'semver'. Change the protection policy to delete it."`

### 3. Registry `DELETE /v2/:name/manifests/:digest`

In `V2::ManifestsController#destroy`, look up tags pointing to the given digest. If any of them are protected, raise `TagImmutabilityError`. This path is rarely used by Docker CLI but must be consistent.

### Error translation

`V2::BaseController` adds a `rescue_from TagImmutabilityError` that renders:

```http
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "errors": [{
    "code": "DENIED",
    "message": "tag 'v1.2.3' is protected by immutability policy 'semver'",
    "detail": { "tag": "v1.2.3", "policy": "semver" }
  }]
}
```

The `DENIED` code is defined in the Docker Registry error code catalog. The CLI prints `denied: tag 'v1.2.3' is protected...`.

## Web UI

### Repository edit form

Location: `app/views/repositories/show.html.erb` — the existing edit section.

New fields appended below description/maintainer:

- `tag_protection_policy` — `<select>` with four options. Labels describe each preset (`none: No protection`, `semver: Protect v1.2.3-style tags`, `all_except_latest: Protect everything except 'latest'`, `custom_regex: Match by custom regex`).
- `tag_protection_pattern` — `<input type="text">`, hidden unless `custom_regex` is selected. Placeholder example: `^release-\d+$`.

New Stimulus controller `tag_protection_controller.js`:
- Target: the policy select + the regex input.
- Action: on policy change, show/hide the regex input.

Strong params updated in `RepositoriesController#repository_params`:

```ruby
params.expect(repository: [:description, :maintainer, :tag_protection_policy, :tag_protection_pattern])
```

### Tag list display

Location: `app/views/repositories/show.html.erb` tag loop.

For each tag: if `repository.tag_protected?(tag.name)`, render a badge: `<span class="...">🔒 Protected</span>` with an ARIA label `"Protected tag (policy: semver)"`. Color independence is maintained via the text label.

### Tag detail / delete

Location: `app/views/tags/show.html.erb`.

If the tag is protected:
- Delete button is disabled (`disabled` attribute + visibly greyed out).
- Tooltip: `"Change the repository's tag protection policy to delete this tag."`

If the tag is not protected, the existing delete flow is unchanged.

No per-tag unprotect action. Protection is managed only at repo level.

## Testing

### RSpec (backend)

Unit specs on `Repository#tag_protected?`:
- `none` returns false for any input.
- `semver` — true for `v1.2.3`, `1.2.3`, `1.2.3-rc1`, `1.2.3+build.5`; false for `latest`, `v1.2`, `main`.
- `all_except_latest` — false for `latest`, true for everything else.
- `custom_regex` with `^release-\d+$` — true for `release-1`, false for `release-1a`.

Validation specs:
- Invalid regex (e.g., unclosed bracket) raises a model validation error.
- `custom_regex` with blank pattern is invalid.

Service specs on `ManifestProcessor`:
- PUT with same digest on a protected tag → success, no TagEvent row created for no-op.
- PUT with different digest on a protected tag → raises `TagImmutabilityError`.
- PUT on an unprotected tag → success.

Request specs on `V2::ManifestsController#update`:
- Response body matches the error envelope exactly.
- Status is 409.

### Docker CLI integration

Extend `test/integration/docker_cli_test.sh` with a protection scenario:

1. Create a repo and set policy to `semver` via `bin/rails runner`.
2. `docker push localhost:3000/proto-img:v1.0.0` — succeeds.
3. Tag a different image and `docker push localhost:3000/proto-img:v1.0.0` again — expect the CLI to print `denied:` and exit non-zero.
4. `docker push localhost:3000/proto-img:v1.0.0` with the same image — expect success (idempotent).

### Playwright E2E

New spec `e2e/tag-protection.spec.js`:

1. Seed: a repo with two tags `v1.0.0` and `latest`.
2. Visit repo page, open edit form, set policy to `semver`, save.
3. Assert `v1.0.0` row has the 🔒 Protected badge; `latest` row does not.
4. Visit `v1.0.0` tag detail page; assert Delete button is disabled and tooltip is present.
5. Return to repo page, change policy back to `none`, save.
6. Visit `v1.0.0` tag detail, click Delete — assert success redirect to repo page.

## Rollout

- Migration adds columns with `default: "none"`; no data migration needed.
- No feature flag. The feature is inert until a repo's policy is changed from `none`.
- No changes required for Docker CLI configuration.
- Existing ingest behavior (push, pull, mount) is unaffected for repos with default policy.

## Open Questions

None. All decisions resolved during brainstorming.
