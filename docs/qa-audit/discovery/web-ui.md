# Web UI Discovery

## Page Inventory

| Route | Controller#Action | View / Component | Purpose | Role / Auth gate | Key interactions |
|---|---|---|---|---|---|
| GET / | repositories#index | repositories/index.html.erb | Home: browse all repositories with search & sort | Public (anonymous see login button) | Search (AJAX Turbo Frame), sort dropdown, repository cards |
| GET /repositories/:name | repositories#show | repositories/show.html.erb | Repo detail: tags list, metadata, protection policy, delete button | Signed-in required | Edit repo metadata, tag protection policy, tag list (delete buttons), copy docker pull command |
| PATCH /repositories/:name | repositories#update | repositories/show.html.erb | Update description, maintainer, tag protection policy | Signed-in + write-access | Form submission with validation errors |
| DELETE /repositories/:name | repositories#destroy | — | Delete repository & all tags (danger zone) | Signed-in + delete-access | Turbo confirmation dialog, redirect to root |
| GET /repositories/:name/tags/:tag | tags#show | tags/show.html.erb | Tag detail: manifest info, layers, docker config, danger zone delete | Signed-in required | View layer stack, copy docker pull command, delete tag button |
| GET /repositories/:name/tags/:tag/history | tags#history | tags/history.html.erb | Tag event history (create/update/delete with digests) | Signed-in required | Back link, event list cards with action badges |
| DELETE /repositories/:name/tags/:tag | tags#destroy | — | Delete tag (protected if policy matches) | Signed-in + delete-access | Turbo confirmation, tag protection error handling, redirect to repo |
| GET /help | help#show | help/show.html.erb | Setup guide: Docker daemon, K8s/containerd, nginx reverse proxy, image format warnings | Public (no auth required) | Code blocks, registry host interpolation, multi-platform warning |
| GET /auth/:provider/callback | auth/sessions#create | — | OAuth callback handler (Google only, Stage 0) | Public | Session creation, email mismatch/invalid profile error handling |
| GET /auth/failure | auth/sessions#failure | — | OAuth failure page | Public | Flash alert with strategy + message |
| DELETE /auth/sign_out | auth/sessions#destroy | — | Sign out | Signed-in | Session reset, redirect to root with notice |
| GET /settings/tokens | settings/tokens#index | settings/tokens/index.html.erb | Manage personal access tokens (CLI, CI) | Signed-in required | Generate token form, token list with revoke buttons, raw token flash |
| POST /settings/tokens | settings/tokens#create | settings/tokens/index.html.erb | Create new PAT (CLI, CI, custom expiry) | Signed-in required | Form validation, expires_in_days parsing, raw token display |
| DELETE /settings/tokens/:id | settings/tokens#destroy | — | Revoke PAT | Signed-in required | Turbo confirmation, redirect with notice |

## User Journeys

### Browse Repositories
1. Land on GET / (repositories#index) — see grid of repos or empty state
2. Search by name/description/maintainer (instant Turbo Frame update, 300ms debounce)
3. Sort by name, size, or pulls (dropdown → Turbo Frame refresh)
4. Click repo card → GET /repositories/:name

### Inspect & Manage a Repository
1. View repo detail (metadata, tags list)
2. **Optional:** Click "Edit description & maintainer" details summary
   - Edit description, maintainer, tag protection policy (dropdown)
   - If policy is "custom_regex", show regex input (Stimulus toggle)
   - PATCH to update; validate; show errors inline or success notice
3. Copy docker pull command for latest tag (clipboard Stimulus controller)
4. Delete repository (danger zone, Turbo confirmation, requires delete-access)

### View & Delete a Tag
1. Click tag name in repo's tag list → GET /repositories/:name/tags/:tag
2. View manifest (digest, size, architecture, pulls, docker config JSON)
3. View layers (list of blobs with positions, sizes, digests)
4. **Optional:** Click "History" → GET /repositories/:name/tags/:tag/history
   - See audit trail of create/update/delete events with previous & new digests
5. Delete tag (danger zone):
   - If tag is protected: button disabled with tooltip message
   - Else: Turbo confirmation → DELETE → redirect to repo with notice or protection error

### Authentication & Token Management
1. On any page, if not signed in:
   - See "Sign in with Google" button in nav
   - Click → POST /auth/google_oauth2 (OmniAuth redirect)
   - OAuth provider → callback to GET /auth/:provider/callback
   - If success: session created, redirect to / with notice "Signed in as {email}"
   - If failure: redirect to /auth/failure with strategy + message (email_mismatch, invalid_profile, etc.)
2. Signed in: see email + "Tokens" link + "Sign out" button
3. Click "Tokens" → GET /settings/tokens
   - See form to generate new token (name, kind: CLI/CI, expires_in_days)
   - If raw_token in flash: show copy-to-clipboard pre block (one-time display)
   - Table of existing tokens (name, kind, expires, last_used, status: Active/Expired/Revoked)
   - Revoke button (Turbo confirmation) removes token from auth

### View Setup Documentation
1. Click "Help" link in nav → GET /help
2. See multi-section setup guide:
   - Docker daemon insecure registry config
   - Push & pull commands with interpolated registry_host
   - Kubernetes/containerd mirror config
   - Nginx reverse proxy TLS example
   - **Warning box:** Single-platform Docker V2 only, no multi-arch manifests

### Theme & Accessibility
1. Dark mode toggle button in nav (Stimulus theme_controller)
   - Reads/writes localStorage['theme']
   - Applies 'dark' class to <html>
   - Layout.erb includes FOUC prevention script
2. All pages respect `prefers-color-scheme: dark` media query if no localStorage override
3. Focus rings, contrast, ARIA labels on icons/buttons

## Interactive Components

### Search Controller (Stimulus)
- **Targets:** form
- **Actions:** input→search#search, change→search#search
- **Behavior:** Debounced (300ms) form submission to same page with Turbo Frame `repositories`
- **Where:** repositories/index.html.erb (search input + sort dropdown)

### Tag Protection Controller (Stimulus)
- **Targets:** policy, regexWrapper
- **Actions:** change→tag-protection#toggle
- **Behavior:** Shows/hides regex input div based on policy select value === "custom_regex"
- **Where:** repositories/show.html.erb (edit form, collapse open)

### Theme Controller (Stimulus)
- **Targets:** lightIcon, darkIcon
- **Actions:** click→theme#toggle
- **Behavior:** Toggles 'dark' class on <html>, persists to localStorage, hides/shows SVG icons
- **Where:** layouts/application.html.erb (nav dark mode button)

### Clipboard Controller (Stimulus)
- **Targets:** icon, label (optional)
- **Values:** text (string), successDuration (number, default 2000ms)
- **Actions:** click→clipboard#copy
- **Behavior:** Uses navigator.clipboard.writeText, shows "Copied!" feedback + checkmark icon for 2s, reverts
- **Where:** repositories/show.html.erb (docker pull command), tags/show.html.erb (docker pull command)

### ViewComponent Library
- **ButtonComponent:** primary/secondary/outline/danger/ghost/link variants, sm/md/lg sizes, optional icon, disabled state
- **BadgeComponent:** default/success/warning/danger/info/accent variants, optional icon
- **InputComponent:** text/email/password/search types, sm/md/lg sizes, label + required mark, error state with aria-describedby, help text
- **SelectComponent:** multi-option dropdown, size variants, disabled support
- **TextareaComponent:** configurable rows, label, help text, error handling
- **CardComponent:** padding variants (none/md), optional header slot (CardComponent.with_header do)
- **DigestComponent:** renders blob digest with copy-to-clipboard (see below)
- All components use Tailwind Utilities (dark mode class toggling)

### Turbo Frames
- **repositories frame** (repositories/index.html.erb): Replaced on search/sort to refresh repository grid
- **_top:** repository_card.html.erb navigates card clicks to full page (not frame-scoped)

### Turbo Streams
- **index.turbo_stream.erb:** Replaces "repositories" frame on GET /repositories?q=... or sort change

## Edge Cases Worth Testing

- **Empty states:**
  - No repositories (new registry) → show "No repositories yet / Push an image to get started"
  - Search with zero results → show "No results found / Try adjusting your search query"
  - Repo with no tags → show "No tags found / Push an image to create tags"
  - Tag history with no events → show "No history events / No changes have been recorded for this tag yet"
  - No PATs → show empty table

- **Large lists:**
  - 1000+ repositories (no pagination/infinite scroll — **all loaded in memory**)
  - 100+ tags per repo → grid/table render performance, mobile responsiveness
  - 100+ layers per manifest → layer list scrollability
  - Many PATs (expired, revoked, active mixed)

- **Unicode & Non-ASCII:**
  - Repo name with slashes (e.g. "my-org/my-app") → routing, display truncation on cards
  - Tag name with dots, hyphens, underscores, colons (e.g. "v1.2.3-rc.1+build123")
  - Description & maintainer fields with emoji, CJK characters, RTL text → text overflow, line-clamping
  - Search query with Korean/Japanese/Arabic text → LIKE query matching

- **Destructive actions:**
  - Delete repo while tag is being accessed → 404 or stale data in form
  - Delete tag while viewing its history → history page 404, repo page updates
  - Turbo confirmation dialog dismissed → request still goes through if not cancelled properly
  - CSRF token missing/invalid → form submission rejection

- **Auth & Permissions:**
  - Signed-in user with read-only access tries to edit/delete → ForbiddenAction rescue, alert redirect
  - Session expired mid-page → next action triggers Auth::Unauthenticated rescue → redirect to /auth/google_oauth2
  - Multi-window: revoke token in one tab, use in another → 401 on next request
  - OAuth provider down during callback → provider_outage exception, failure page with message

- **Turbo Navigation Pitfalls:**
  - Search form with Turbo Frame reloads page while user scrolling → scroll position lost
  - Back button after Turbo Frame navigation → may restore frame, not full page
  - Nested Turbo Frame clicks (card → _top) on slow network → multiple navigation requests queued
  - theme_controller dark mode + Turbo page cache → FOUC if layout.erb FOUC script doesn't run

- **Dark Mode:**
  - Contrast on badge colors (especially warning/accent) in dark mode
  - Code blocks in dark mode (bg-slate-900, dark:text-blue-300) → code readability
  - Placeholder text in dark inputs → placeholder:text-slate-500 contrast
  - Diagram/JSON in help page rendering in dark vs. light

- **Accessibility:**
  - Focus management: search input + sort dropdown in one form, does focus stay visible?
  - Landmark structure: <main>, <nav>, <section> with aria-labelledby
  - Form labels + required asterisk: aria-label on buttons without text
  - Clipboard copy button: aria-label="Copy command", but no visible text; feedback via "Copied!" label target
  - Turbo Frame ARIA live regions: search result updates announced to screen readers?
  - Danger zone buttons: "Delete Repository", "Delete tag" — clear intent + confirmation

- **Form Validation:**
  - Tag protection regex invalid (unbalanced parens, bad Ruby syntax) → Rails validation error shown inline
  - Token expires_in_days: 0, -1, non-numeric, empty string → parse_expires_in gracefully handles, returns nil
  - Token name empty → model validation error shown in flash
  - Repository description + maintainer very long (1000+ chars) → text overflow, line-clamp-2 on cards

- **Data Rendering:**
  - Manifest.docker_config JSON is nil → "if @manifest.docker_config.present?" guards rendering
  - Manifest.docker_config is invalid JSON → "rescue @manifest.docker_config" falls back to raw string
  - human_size with nil bytes → returns "0 B"
  - short_digest with nil → returns ""
  - Very large files (1 TB+) → human_size format precision (%.1f) shows "1024.0 GB", not capped

- **History timeline:**
  - Multiple events on same tag within 1 second → order by occurred_at DESC, but displayed timestamps truncated to minute
  - Event without previous_digest or new_digest → "if present?" guards prevent nil display
  - Event actor: actor email address shown (PII, but intentional per comment in sessions#create)

- **Tag protection edge cases:**
  - Policy = "none" → all tags deletable
  - Policy = "semver" → only tags matching ^v\d+\.\d+\.\d+(-|\+)? protected, test edge cases (v1, v1.0, v1.0.0-rc, v1.0.0+build)
  - Policy = "all_except_latest" → "latest" tag always deletable, others protected
  - Policy = "custom_regex" with empty pattern → Rails validation error (must be present if policy is custom_regex)
  - Update policy from custom → semver: new regex input hidden, old pattern preserved in DB

- **Mobile responsiveness:**
  - Repositories grid: 1 col mobile, 2 col tablet, 3-4 col desktop
  - Repository show: tags table hidden on mobile, card stack shown (md:hidden + space-y-3)
  - Tag detail: grid cols adjust for desktop (2-4 cols) vs. mobile stacked
  - Help page: code blocks scroll horizontally on small screens, dark mode contrast maintained
  - PAT table: potentially wrapped/squashed on mobile (form flex-wrap, table may overflow)

- **Network & performance:**
  - Slow search request (e.g., large LIKE query): search form debounces 300ms, but no loading spinner shown
  - Turbo Frame replacement mid-flight: old content swapped, new content loaded
  - Clipboard copy on offline: navigator.clipboard fails, error logged (console.error), no user feedback
  - Repository show with 1000 layers: DOM heavy, rendering lag on older devices

## Notes on quirks

1. **No pagination:** repositories#index loads all repositories without limit. Scales poorly beyond 1000 repos. Turbo Frame search is live but debounced.

2. **Search debounce implementation:** search_controller.js has 300ms delay. Rapid typing (e.g., "testing") triggers requests only on pause. No request cancellation if new search before previous completes.

3. **Tag protection policy display:** Disabled delete buttons show `cursor-not-allowed` but are not true <button disabled> — styled span with pointer-events interaction prevented in CSS. Hovering shows `title` tooltip.

4. **Docker config JSON rendering:** `JSON.pretty_generate(JSON.parse(...)) rescue ...` means unparseable JSON falls back to raw string. No syntax highlighting or error messaging.

5. **Digest shortening:** Helper `short_digest()` strips "sha256:" prefix and returns first 12 chars. Collision risk on display, but serves UI brevity.

6. **Session reset on invalid user:** `current_user` helper deletes session[:user_id] if User.find_by(id: ...) returns nil. Next request forces re-auth.

7. **PAT raw token display:** Shown once in flash[:raw_token] after creation. Re-rendering index.html.erb still shows it until next request. **No "copy to clipboard" button on PAT creation page** — user must manually select & copy from <pre> block.

8. **Tag protection custom regex:** Stored in `repository.tag_protection_pattern` column, but validation/enforcement logic lives in `Registry::TagProtected` exception raised by `Repository#enforce_tag_protection!`. UI shows policy dropdown & conditional input, but regex is not tested client-side.

9. **Turbo confirm dialogs:** All destructive actions (delete repo, delete tag, revoke token, sign out) use `data: { turbo_confirm: "..." }`. Browser native confirm() — looks basic, no custom styling.

10. **Dark mode FOUC prevention:** layout.erb includes inline script before stylesheet load. If JS disabled, dark-mode CSS still applies but page flashes unstyled briefly on first paint.

11. **Auth error handling:** Auth::Unauthenticated & Auth::ForbiddenAction raised by authorize_for! are rescued in ApplicationController with redirect behavior. No UI for "you lack permission to edit this repo" beyond generic alert flash.

12. **Clipboard controller fallback:** No fallback for navigator.clipboard (old browsers, private browsing). Error logged but user sees no UI feedback if copy fails.

13. **Help page registry_host:** All code snippets use `<%= @registry_host %>` interpolation. If config is missing, nil renders in pre blocks (looks broken).

14. **Stimulus controller lifecycle:** search_controller clears timeout on disconnect. theme_controller reads localStorage on connect and applies class synchronously. If Turbo replaces nav without full page load, theme_controller may not disconnect/reconnect.

15. **CardComponent header slot:** Optional `with_header` block. If used, wraps title in <div> with implicit padding. Tags show layer #, history shows no header.

16. **Input validation aria-describedby:** error_id takes precedence over help_id. Screen reader announces error message, not help text.

17. **Repository name constraint:** Route `name: /[^\/]+(?:\/[^\/]+)*/` allows multi-segment paths (e.g. "org/team/repo"). All links/forms use `@repository.name` directly without encoding. Search query is % LIKE, could match "/" in repo name.

18. **Revoked vs. Expired tokens:** PAT table shows three statuses: "Revoked" (red), "Expired" (gray), "Active" (green). No indication of difference in UI, just status display. Both are unusable for auth.

