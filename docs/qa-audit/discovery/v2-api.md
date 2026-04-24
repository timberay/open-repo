# V2 Registry API Discovery

## Endpoint Inventory

| Method | Path | Controller#Action | Purpose | Auth required | Notable edge cases |
|---|---|---|---|---|---|
| GET | /v2/ | V2::BaseController#index | Ping / version check | No* | Returns 200 + `Docker-Distribution-API-Version: registry/2.0` when auth disabled; returns 401 + `WWW-Authenticate` header when auth required |
| GET | /v2/_catalog | V2::CatalogController#index | List all repositories (paginated) | No* | Paginated via `n` (default 100, clamped 1-1000) and `last` params. `Link` header for pagination rel="next". Returns `{repositories: [...]}` |
| GET | /v2/:name/tags/list | V2::TagsController#index | List tags for a repo (paginated) | No* | Supports namespace repos (`:ns/:name`). Same pagination as catalog. Returns `{name: "...", tags: [...]}` |
| GET, HEAD | /v2/:name/manifests/:reference | V2::ManifestsController#show | Pull manifest by tag or digest | No* | `reference` can be tag name or `sha256:...` digest. HEAD returns just headers (no body). Records pull event. Returns `Docker-Content-Digest`, `Content-Type`, `Content-Length` headers |
| PUT | /v2/:name/manifests/:reference | V2::ManifestsController#update | Push manifest | Yes | Only `application/vnd.docker.distribution.manifest.v2+json` accepted (415 for unsupported). Validates config + layers exist. Enforces tag protection (409 if protected). Returns 201 + `Location` header with digest URI |
| DELETE | /v2/:name/manifests/:reference | V2::ManifestsController#destroy | Delete manifest | Yes | Enforces tag protection on all tags. Cascades delete to tags and decrements layer blob refs. Returns 202 |
| GET, HEAD | /v2/:name/blobs/:digest | V2::BlobsController#show | Pull blob | No* | Checks both DB + BlobStore for existence. HEAD returns headers only. Returns `Docker-Content-Digest`, `Content-Length`, `Content-Type` headers |
| DELETE | /v2/:name/blobs/:digest | V2::BlobsController#destroy | Delete blob | Yes | Deletes from both DB and BlobStore. Returns 202 |
| POST | /v2/:name/blobs/uploads | V2::BlobUploadsController#create | Initiate or complete blob upload | Yes | 3 modes: (a) mount existing blob (?mount=digest&from=...), (b) monolithic upload (?digest=...), (c) chunked start (no params). Returns 201 + `Docker-Upload-UUID`, `Location`, `Range` headers |
| PATCH | /v2/:name/blobs/uploads/:uuid | V2::BlobUploadsController#update | Append chunk to chunked upload | Yes | Updates `byte_offset`. Returns 202 + `Docker-Upload-UUID`, `Location`, `Range` headers |
| PUT | /v2/:name/blobs/uploads/:uuid | V2::BlobUploadsController#complete | Finalize chunked upload | Yes | `?digest=...` required. Can append final chunk in body. Returns 201 + `Docker-Content-Digest`, `Location` headers |
| DELETE | /v2/:name/blobs/uploads/:uuid | V2::BlobUploadsController#destroy | Cancel upload session | Yes | Cleans up BlobStore upload dir + DB record. Returns 204 |

## Flow Groups

### 1. **Ping / Version Check**
   - `GET /v2/` → confirm registry v2 support and auth status
   - Returns empty JSON `{}` with `Docker-Distribution-API-Version: registry/2.0` header
   - No auth required if `REGISTRY_ANONYMOUS_PULL=true` (default)

### 2. **Pull Flow (Monolithic)**
   - Client: `GET /v2/:name/manifests/:tag` → fetch manifest
   - Client: `GET /v2/:name/blobs/:config-digest` → fetch config blob
   - Client: `GET /v2/:name/blobs/:layer-digest` (repeat for each layer) → fetch layers
   - No auth required if anonymous pull enabled

### 3. **Push Flow (Monolithic)**
   - Client: `POST /v2/:name/blobs/uploads?digest=:config-digest` + body → upload config
   - Client: `POST /v2/:name/blobs/uploads?digest=:layer-digest` + body (repeat) → upload layers
   - Client: `PUT /v2/:name/manifests/:tag` + manifest JSON → register manifest+tag
   - Creates repo if it doesn't exist (first pusher becomes owner)

### 4. **Push Flow (Chunked)**
   - Client: `POST /v2/:name/blobs/uploads` → initiate session, get UUID
   - Client: `PATCH /v2/:name/blobs/uploads/:uuid` + chunk → append (repeat)
   - Client: `PUT /v2/:name/blobs/uploads/:uuid?digest=:digest` + final-chunk → finalize
   - Client: (repeat for each layer, then) `PUT /v2/:name/manifests/:tag` → register

### 5. **Blob Mount (Cross-repo reuse)**
   - Client: `POST /v2/:name/blobs/uploads?mount=:existing-digest&from=:other-repo` → request mount
   - If blob + BlobStore file exist → 201 (mount succeeds, refs_count++, no upload needed)
   - If blob not found → 202 (falls back to chunked start flow, ignores mount params)

### 6. **Catalog / Discovery**
   - Client: `GET /v2/_catalog?n=100&last=lastRepoName` → discover repos
   - Client: (for each repo) `GET /v2/:name/tags/list?n=100` → discover tags
   - No auth required if anonymous pull enabled

### 7. **Delete Flow**
   - Client: `DELETE /v2/:name/manifests/:tag` → remove tag+manifest (403 if protected, 202 if success)
   - Client: (optional) `DELETE /v2/:name/blobs/:digest` → remove unreferenced blob (202)
   - Both require write/delete auth, blob checks both DB + BlobStore

## Edge Cases Worth Testing

### Authentication & Authorization
- **Missing Authorization header** → 401 + `WWW-Authenticate: Basic realm="Registry"` + error code `UNAUTHORIZED`
- **Invalid PAT / email mismatch** → 401 (same as missing)
- **Valid auth but no write access** → 403 + error code `DENIED` with `insufficient_scope` detail
- **Anonymous pull disabled** → 401 on GET manifests/blobs even without auth header
- **First-pusher repo creation** → authenticated user becomes owner; subsequent pushes check write ACL (RecordNotUnique race is gracefully passed, see BlobUploadsController#ensure_repository)

### Manifest Validation
- **Unsupported media type** (e.g., multi-platform, schema v1) → 415 + error code `UNSUPPORTED` + message about V2 Schema 2 requirement
- **Schema version != 2** → 400 + error code `MANIFEST_INVALID` + "unsupported schema version"
- **Missing config blob** → 400 + "config blob not found"
- **Missing layer blob** → 400 + "layer blob not found: <digest>"
- **Content-Type header mismatch vs payload** → processor validates schema before checking content-type
- **Pull by digest that doesn't exist** → 404 + error code `MANIFEST_UNKNOWN`
- **Push to protected tag with different digest** → 409 + error code `DENIED` + detail includes tag + policy (e.g., semver, all_except_latest, custom_regex)
- **Push same digest to protected tag (idempotent retry)** → 201 (idempotent, does not raise)

### Digest & Content Verification
- **Blob upload digest mismatch** → 400 + error code `DIGEST_INVALID` (raised by finalize_upload validation in BlobStore)
- **Manifest payload size mismatch** → not validated in current impl; Content-Length is computed from payload bytesize
- **HEAD request to manifest/blob** → returns all headers but no body (200 OK with Content-Length, Docker-Content-Digest, Content-Type)

### Chunked Upload Edge Cases
- **Append to non-existent upload UUID** → 404 + error code `BLOB_UPLOAD_UNKNOWN`
- **Finalize without prior PATCH** (body-only finalize) → valid; blob created with just the body
- **PATCH after finalize** → 404 (upload record destroyed on complete)
- **Cancel upload with DELETE** → removes BlobStore upload dir + DB record; idempotent returns 204
- **Range header on PATCH** → returned as `"0-<byte_offset-1>"` (Docker client uses this to resume)

### Blob Mount Edge Cases
- **Mount non-existent blob** → falls back to chunked start (no error)
- **Mount existing blob to same repo** → succeeds, refs_count incremented (deduplication within repo)
- **Mount with invalid mount param format** → treated as regular start if mount param present but digest invalid
- **Blob file missing from BlobStore but DB record exists** → treated as not existing (404 on pull, mount falls back)

### Repository & Tag Management
- **Non-existent repo on pull** → 404 + error code `NAME_UNKNOWN` + "repository '...' not found"
- **Non-existent tag** → 404 + error code `MANIFEST_UNKNOWN`
- **Catalog/tags pagination with invalid `n`** → clamped to [1, 1000]
- **Pagination with `last` beyond all repos** → returns empty list (no error)
- **Tag name uniqueness within repo** → enforced in schema; re-tagging same tag with new manifest is allowed (no INSERT error)
- **Namespace repos** → routes support `:ns/:name` constraint (both `name` and `name/sub/parts` formats)

### Response Headers
- **Docker-Distribution-API-Version** → always present (registry/2.0) on all V2 endpoints
- **Docker-Content-Digest** → present on manifest/blob GETs + all upload completions
- **WWW-Authenticate** → only on 401, format `Basic realm="Registry"`
- **Location** → on PUT manifest, POST create, PATCH update, PUT complete (redirect to digest URI or next upload step)
- **Range** → on upload operations, format `"0-<byte_offset-1>"` (for resumable uploads)
- **Link** → on catalog/tags pagination, format `</v2/...?last=X&n=Y>; rel="next"` (RFC 5988)
- **Content-Type** → manifest returns `application/vnd.docker.distribution.manifest.v2+json`; blobs return `application/octet-stream` or stored type

### Concurrent Access
- **Race on first-pusher repo creation** → handled by ManifestProcessor + BlobUploadsController (repo.with_lock + catch RecordNotUnique on blob upload side)
- **Race on tag-protection check** → enforced inside repo.with_lock in ManifestProcessor to prevent orphan manifests
- **Simultaneous push to same tag** → tag protection + with_lock ensures only one digest succeeds; others see existing_tag.manifest != new_digest and raise TagProtected (409)

### Error Response Format
All errors follow Docker distribution spec:
```json
{
  "errors": [
    {
      "code": "ERROR_CODE",
      "message": "human description",
      "detail": { /* optional structured data */ }
    }
  ]
}
```
Defined error codes: `BLOB_UNKNOWN`, `BLOB_UPLOAD_UNKNOWN`, `MANIFEST_UNKNOWN`, `MANIFEST_INVALID`, `NAME_UNKNOWN`, `DIGEST_INVALID`, `UNSUPPORTED`, `DENIED`, `UNAUTHORIZED`

## Notes on Quirks

1. **First-Pusher Ownership** — Repository ownership is assigned on first blob upload, not first manifest push. This is intentional (tech design D2): a client may upload blobs then fail on manifest; the repo is created to prevent orphan blobs, and on retry (or another client) the manifest PUT gates on write permission.

2. **Tag Protection Atomicity** — Tag protection is checked inside `repository.with_lock` in ManifestProcessor BEFORE manifest.save!, preventing orphan manifests if a protected tag blocks the push mid-way.

3. **Blob References Counting** — Manifests track layers; layers track blobs; blobs have `references_count`. Blob mount increments this. Delete manifest decrements layer blob refs. Orphaned blobs (refs_count == 0) are not auto-cleaned (manual cleanup needed).

4. **Idempotent Manifest Push** — Pushing the same manifest (same JSON payload) to the same tag or digest is idempotent and succeeds even if the tag is protected (compare digest, skip error if equal).

5. **HEAD Request Semantics** — HEAD on manifest/blob returns same headers as GET but no body. This is used by clients to check existence + size + digest without downloading.

6. **Monolithic Upload Over POST** — To upload a blob in one shot (not chunked), client sends `POST /v2/:name/blobs/uploads?digest=:digest` with body. This is non-standard but supported (not in OCI spec, used by some Docker clients for small blobs).

7. **Mount Fallback** — Blob mount with invalid/non-existent source blob silently falls back to a normal chunked-upload initiation, not an error. This matches Docker Registry v2 behavior.

8. **Config Blob Requirement** — Manifest schema validation requires config + layers arrays; empty layers array is allowed but config is mandatory (OCI Image Spec).

9. **Architecture + OS Extraction** — ManifestProcessor extracts `architecture` and `os` from config.json (parsed), stored on manifest record for discovery (not yet used in current endpoints, but recorded for future filtering).

10. **Pull Event Tracking** — Each manifest pull (GET, not HEAD) increments `pull_count` and records PullEvent with user_agent + remote_ip + occurred_at. This data is for analytics; no impact on response.

11. **Anonymous Pull Default** — `REGISTRY_ANONYMOUS_PULL=true` by default. Allows GET on manifests/blobs/tags/catalog/_catalog without auth. Only whitelisted endpoints support anonymous access (base index, catalog, tags, manifests show, blobs show).

12. **Digest Algorithm Hardcoding** — Routes use `sha256:` in examples; BlobStore.path_for splits on `:` to extract algorithm and hex. Non-sha256 digests are supported structurally but client usage would be rare (v2 assumes sha256).

13. **Content-Type Negotiation Gap** — Registry doesn't support Accept header or content negotiation for manifest media types (always returns stored type). Multi-platform manifests rejected outright (415).

14. **Tag Event Audit Trail** — Every tag mutation (push, delete) creates TagEvent record (action, previous_digest, actor, actor_identity_id, occurred_at). Manifest DELETE cascades TagEvents for all tags.

15. **Blob Delete Doesn't Check Refs** — DELETE /v2/:name/blobs/:digest succeeds even if blob is still referenced by manifests. No orphan-prevention or cascade. Caller must ensure blob is truly unreferenced.

