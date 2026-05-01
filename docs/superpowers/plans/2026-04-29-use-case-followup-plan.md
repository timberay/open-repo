# Use-Case Follow-up Plan (2026-04-29)

Follow-up to the 99-use-case full inspection (전수검사) completed on 2026-04-29.

Spec source: `/tmp/uc-inspection/use-cases.md` (99 cases after B-49 struck by convention).

## Status snapshot — after Wave 2

| 상태 | 개수 | 비율 |
|------|------|------|
| Pass ✅ | 87 | 87.9% |
| Partial ⚠️ | 6 | 6.1% |
| Fail ❌ | 0 | 0% |
| N/I ➖ | 4 | 4.0% |
| N/A — | 2 | 2.0% |

Wave 1 (shipped on `main`, commits `e57855a..d1f4cf8`):
- Fail 2건 수정 (B-19, B-25)
- N/I 5건 구현 (B-21, B-40, E-07, E-13, E-47)
- Partial 8건 테스트 보강으로 Pass 승격 (E-16, E-20, E-22, E-26, E-32, E-33, E-38, E-39)
- B-49 spec 제외 (CLAUDE.md "English for code/yaml" 규칙 충돌)

Wave 2 (shipped on `main`, PRs #41 / #42 / #43, commits `9074caf` / `259129a` / `82f30df`):
- W2-A — B-03 (sign-out → /sign_in), B-07 (/sign_in 프로젝트 설명), B-22 (PAT prefix 컬럼)
- W2-B — B-37 / B-39 / B-46 (Help 페이지 PAT / HTTP-vs-HTTPS / docker-login walkthrough), B-38 (V2 401 body `detail.help_url`)
- W2-C — B-30 / B-35 / B-42 (docker login challenge / typo password / re-tag 복구 회귀 보호)

---

## Remaining 22 items

### Partial ⚠️ — 기능은 있고 보강 필요 (16)

#### A. Quick UX wins (작은 view/controller 변경)
| ID | 갭 | 위치 |
|----|------|------|
| B-03 | sign-out destroy 가 `/sign_in` 대신 `root_path` 로 redirect | `app/controllers/auth/sessions_controller.rb:42-45` |
| B-07 | `/sign_in` 페이지에 프로젝트 설명 부재 | `app/views/auth/sessions/new.html.erb:1-7` |
| B-22 | `/settings/tokens` 에 `prefix` 컬럼 부재 | `app/views/settings/tokens/_token_row.html.erb` |

#### B. Help page expansion (단일 view 일괄 보강 가능)
| ID | 갭 | 위치 |
|----|------|------|
| B-37 | 401 응답 / `/help` 가 PAT 생성으로 안내하지 않음 | `app/views/help/show.html.erb` |
| B-38 | 401 본문에 PAT 가이드 포인터 없음 | `app/views/help/show.html.erb`, `app/controllers/v2/base_controller.rb` (error body) |
| B-39 | HTTP vs HTTPS 안내 섹션 부재 | `app/views/help/show.html.erb:11-15` |
| B-46 | sign-in / token-creation / `docker login` 섹션 부재 | `app/views/help/show.html.erb` |

#### C. UX improvements (medium 규모)
| ID | 갭 | 위치 |
|----|------|------|
| B-05 | OAuth failure flash 에 retry 버튼 없음 | `app/controllers/auth/sessions_controller.rb:35-40`, view |
| B-13 | tag detail 에 ENV/CMD/Entrypoint 가 raw JSON 으로만 노출 | `app/views/tags/show.html.erb:23-25,107-114` |
| B-18 | history 에 digest diff 인디케이터 부재 | `app/views/tags/history.html.erb:24-33` |
| B-41 | 토큰 분실 시 복구 절차 안내 UI 부재 | `app/views/settings/tokens/index.html.erb` |

#### D. Pagination/navigation
| ID | 갭 | 위치 |
|----|------|------|
| B-10 | repositories 목록 페이지네이션 부재 | `app/controllers/repositories_controller.rb:5` (Kaminari 이미 추가됨, 적용만) |
| B-16 | 형제 repo nav / breadcrumb 부재 | `app/views/repositories/show.html.erb:3-7` |

#### E. Admin nav (선행 설계 필요)
| ID | 갭 | 위치 |
|----|------|------|
| B-04 | admin 플래그는 세팅되나 admin-only nav 미구현 | `app/views/layouts/application.html.erb` (admin 라우트 자체가 일부 미정 — retention/GC trigger 등) |

#### F. Test reinforcement (코드는 있고 테스트만 추가)
| ID | 갭 | 위치 |
|----|------|------|
| B-30 | 실제 `docker login` 명령 시뮬 통합 테스트 부재 | `test/integration/docker_basic_auth_test.rb` |
| B-35 | 오타 password 시 V2 통합 테스트 부재 | `test/controllers/v2/base_controller_test.rb` 또는 `test/services/auth/pat_authenticator_test.rb` |
| B-42 | 잘못 삭제 후 re-tag 복구 시나리오 테스트 부재 | `test/integration/...` (신규) |
| E-48 | 미존재 repo pull 시 `MANIFEST_UNKNOWN` 대신 `NAME_UNKNOWN` 반환 — Docker spec 양쪽 다 합법, 명세 의도와 차이 | `app/controllers/v2/base_controller.rb:79-83` (judgment call: 변경 또는 명세 일치로 문서화) |

### N/I ➖ — 기능 자체 부재 (4)
| ID | 갭 | 위치 / 노트 |
|----|------|-------------|
| B-43 | 폼 unsaved-changes guard (beforeunload) | `app/javascript/controllers/` (Stimulus) — JS 작업 |
| E-37 | Tar import job/service | `app/jobs/`, `app/services/` 신규 — 큰 feature, 별도 phase 필요 |

(B-38, B-39 는 위 Group B 에 같이 묶음. 나머지 N/I 는 위 Help page expansion 으로 흡수됨.)

### N/A — 코드만으로 판단 불가 (2)
| ID | 갭 |
|----|------|
| B-44 | 대용량 이미지 pull 스트리밍 — 런타임/네트워크 검증 영역 |
| B-45 | docker daemon down — 클라이언트 측 조건 |

→ **Out of scope.** QA 시 수동 확인 또는 e2e + 외부 스크립트 영역.

---

## Proposed waves

### Wave 2 — Quick wins + Help expansion + Test reinforcement (10건)
**예상 PR 1-2개, 약 4-6시간**

권장 분할:
- **W2-A: Quick UX wins** (병렬 가능, 각 view 다름)
  - B-03 (sign-out redirect)
  - B-07 (sign-in 페이지 설명)
  - B-22 (token prefix 컬럼)
- **W2-B: Help page batch** (단일 view 일괄, sequential)
  - B-37, B-38, B-39, B-46 — `app/views/help/show.html.erb` 에 PAT/HTTPS/login 섹션 추가, 401 본문 가이드 포인터 추가
- **W2-C: Test 보강** (각 다른 테스트 파일, 병렬)
  - B-30 (`docker login` 시뮬 테스트)
  - B-35 (typo password V2 테스트)
  - B-42 (re-tag 복구 시나리오 테스트)

**Wave 2 예상 결과:** 77 → 87 Pass

### Wave 3 — UX improvements + pagination + nav (6건)
**예상 PR 1-2개, 약 6-8시간**

- **W3-A: UX polish** (각 view 다름, 병렬)
  - B-05 (failure retry 버튼)
  - B-13 (ENV/CMD/Entrypoint 라벨링)
  - B-18 (digest diff 인디케이터)
  - B-41 (분실 토큰 복구 안내)
- **W3-B: Pagination/nav** (서로 독립, 병렬)
  - B-10 (repositories 페이지네이션)
  - B-16 (sibling repo nav / breadcrumb)

**Wave 3 예상 결과:** 87 → 93 Pass

### Wave 4 — JS guard (1건)
**예상 ~2시간**
- B-43 (Stimulus 컨트롤러로 unsaved-changes guard)

**Wave 4 예상 결과:** 93 → 94 Pass

### Wave 5 — Admin nav (1건, 선행 설계 필요)
**예상 4-6시간 + 설계**

- B-04 — admin nav 가 노출하는 페이지 자체 (retention/GC trigger UI) 가 일부 미정. 4-phase 파이프라인 적용 권장:
  - `/office-hours` → admin 화면 범위 결정
  - `/plan-eng-review` → 라우트/권한 설계
  - `/superpowers:brainstorming` → tech design
  - `/superpowers:writing-plans` → task breakdown

**Wave 5 예상 결과:** 94 → 95 Pass

### Wave 6 — Tar import (1건, 별도 phase project)
**예상 1-2주 (별도 feature)**

- E-37 — 신규 service + job + UI + e2e. CLAUDE.md WORKFLOW 4-phase 의무 적용:
  - Phase 1: `/office-hours` (사용 시나리오 / 가져오기 정책)
  - Phase 2: `/plan-eng-review` (라우트, 백그라운드 작업, 데이터 모델)
  - Phase 3: `/superpowers:brainstorming` (TagEvent.actor=`system:import` 처리, 권한)
  - Phase 4: `/superpowers:writing-plans` (commit 단위 분해)

**Wave 6 예상 결과:** 95 → 96 Pass / N/A 2건 + Edge case (E-48 판단) 외 모두 Pass

### E-48 처리 (judgment)
독립 결정:
- **(a) 변경**: `MANIFEST_UNKNOWN` 반환 — `app/controllers/v2/base_controller.rb:79-83` `NameUnknown` 분기 구분
- **(b) 유지**: `NAME_UNKNOWN` 도 spec 합법, 현재 동작 의도된 것으로 use-case spec 의 예상값을 수정

추천: **(b)** — Docker registry 공식 구현체들도 `NAME_UNKNOWN` 사용. spec 표현만 정정.

---

## Out of scope
- **B-49** (한국어 locale): CLAUDE.md "English for code/markdown/YAML" 규칙 충돌 — spec 에서 제외 완료.
- **B-44** (대용량 pull): 런타임 검증 영역 — manual QA 또는 e2e 외부 스크립트.
- **B-45** (docker daemon down): 클라이언트 측 조건 — server 코드와 무관.

---

## Next action — Wave 2

위 Wave 2 (Quick wins + Help + Tests, 10건) 가 다음 작업.

권고 디스패치 형태 (Wave 1 과 동일 패턴):
```
Wave 2 worktree 에이전트 3개 병렬:
- W2-A: B-03 + B-07 + B-22
- W2-B: B-37 + B-38 + B-39 + B-46  (help view sequential)
- W2-C: B-30 + B-35 + B-42         (test files independent)

완료 후 main merge → push.
```

기대 효과:
- Pass 율 77.8% → 87.9%
- Help 페이지가 처음 사용자 friction 흡수
- PAT 생애주기 (생성/login/오류/복구) UI flow 가 "가이드된" 상태로 완성
