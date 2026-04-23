# TODOS

Deferred work captured during reviews. Keep entries self-contained: the reader
should understand motivation, current state, and starting point without
re-reading the original review.

## Format

```
### [PRIORITY] Title
**What:** One-line summary of the work.
**Why:** The concrete problem it solves or value it unlocks.
**Pros:** What you gain by doing this.
**Cons:** Cost, complexity, or risk.
**Context:** Background the future reader needs.
**Depends on / blocked by:** Prerequisites.
**Source:** Review date + section that raised this.
```

---

## [P2] JWT signing key rotation procedure

**What:** Stage 1 의 RS256 JWT 서명 키 (config/credentials.yml.enc 에 저장) 를 유출 시 무중단 교체하는 절차 문서화 + 선택적으로 dual-key window 지원 구현.

**Why:** 초기 설계는 정적 키 + 명시적 `iss`/`aud` ENV. 하지만 키가 유출되면 즉시 교체 가능한 경로가 없음. 현재는 교체 시 발급된 JWT 전부 무효화 + 전 CI 재로그인 필요 → 대규모 중단.

**Pros:** 보안 사건 대응력. GitHub/GitLab 수준의 운영 신뢰성.

**Cons:** dual-key 구현은 TokenIssuer+TokenVerifier 에 key-id(kid) 지원 추가 필요. 복잡도 증가.

**Context:** `/plan-eng-review` 2026-04-23 Architecture A3 에서 도출. 설계에 "future work" 로 명시됨. 키 유출이 아직 일어나지 않은 시점에서는 정적 키 단일 구성으로 충분.

**Depends on / blocked by:** Stage 1 배포 완료 후.

**Source:** `/plan-eng-review` on `~/.gstack/projects/timberay-open-repo/tonny-chore-design-review-polish-design-20260423-103952.md`.

---

## [P2] NAT-aware /v2/token throttling for CI

**What:** rack-attack 의 `/v2/token` 제한을 IP 단독에서 `(username, ip)` 쌍 또는 `PAT prefix + ip` 로 변경. 사내 CI 팜이 NAT 뒤 공유 IP 에서 다수 파이프라인을 돌리는 경우에만 필요.

**Why:** 설계의 10/min/IP 는 단일 개발자·CI 머신에는 충분하나, NAT 공유 IP 에서 10+ 파이프라인이 동시 token 교환 시 429 로 막힘.

**Pros:** 대규모 CI 구성 대응. 악의적 IP brute-force 는 여전히 차단됨 (username+ip 쌍이므로 여러 PAT 시도는 여전히 감지).

**Cons:** throttle key 정의 복잡도. 익명 브루트포스 경로(username 없음)는 여전히 ip 기반.

**Context:** `/plan-eng-review` 2026-04-23 Performance P3 에서 도출. Timberay 사내 CI 가 NAT 뒤인지 확인 후 적용. 아니면 defer.

**Depends on / blocked by:** Stage 1 배포 + 실제 CI 운용 시작.

**Source:** `/plan-eng-review` on `~/.gstack/projects/timberay-open-repo/tonny-chore-design-review-polish-design-20260423-103952.md`.

---

## [P2] Tag protection policy change audit

**What:** Add `action='policy_change'` event type to `TagEvent` (with
`previous_policy` / `new_policy` columns) so repository tag protection policy
transitions are recorded the same way tag mutations are.

**Why:** Scenario — a user temporarily sets `tag_protection_policy` to `none`,
deletes a protected release tag, then restores the policy. Today the tag
deletion is recorded but the policy flip is not, so the "who/when/why this
was possible" trail is broken.

**Pros:** Reuses existing `TagEvent` infrastructure. Trivial implementation
(one migration + one hook in `RepositoriesController#update`). Completes the
audit story for the tag protection feature.

**Cons:** Current MVP threat model explicitly excludes actor tracking and
authentication. Without identity, `actor='anonymous'` limits forensic value.
Minor schema-pattern drift: `TagEvent` becomes "tag-or-policy event."

**Context:** Raised in 2026-04-22 eng review (issue 1-E). Explicitly deferred
because the spec's threat model is accident prevention in an internal trusted
network. Revisit when authentication is introduced post-MVP.

**Depends on / blocked by:** None. Could ship independently.

**Source:** `/plan-eng-review` on `docs/superpowers/specs/2026-04-22-tag-immutability-design.md`.

---

## [P2] Policy transition impact preview in Repository edit form

**What:** Before the user submits the repository edit form with a new
`tag_protection_policy`, show a Turbo Stream preview such as
"Saving will protect 7 existing tags (v1.0.0, v1.0.1, ...) and unprotect 0."

**Why:** A user switching `semver` → `none` to delete one tag can silently
remove protection from every other semver tag in the repo. An explicit
preview + confirm prevents unintentional safety-net removal.

**Pros:** UX safety net. Implementation is bounded — policy apply across
`repo.tags.map(&:name)` and render a partial via Turbo Stream on `change`.

**Cons:** Extra UI surface and Stimulus wiring. Current MVP is fine without
it since every tag operation is audited.

**Context:** Raised in 2026-04-22 eng review outside-voice step (subagent
finding #3). Complementary to the policy-change audit TODO above — audit is
reactive, preview is preventive.

**Depends on / blocked by:** None. Pairs well with the audit TODO if both
ship together.

**Source:** `/plan-eng-review` on `docs/superpowers/specs/2026-04-22-tag-immutability-design.md`.

