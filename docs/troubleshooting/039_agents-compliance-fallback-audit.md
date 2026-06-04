# 039 AGENTS.md 상태/실패 fallback 감사

## Metadata

- ID: TS-039
- Category: Architecture / Runtime Control / Observability / TestKit
- Owner: VitalServer
- Status: active
- Created: 2026-06-01
- Related:
  - [AGENTS.md](../../AGENTS.md)
  - [TS-032 macOS runtime explicit responsibility review](032_macos-runtime-explicit-responsibility-review.md)
  - [TS-038 guest kernel panic watchdog restart loop](038_guest-kernel-panic-watchdog-restart-loop.md)

## Summary

AGENTS.md 기준으로 runtime/control 관련 apps/packages의 상태 추론, fallback, 실패 은폐 후보를 확장 감사한다.

이 TS는 감사로 시작했지만 현재는 root cause work queue 기준으로 코드를 수정하고 검증하는 active remediation 문서다.

이번 TS의 완료 기준은 단순히 활성 항목을 삭제하는 것이 아니다. 의료제품 수준의 내부 engineering bar를 목표로, 상태 의미 보존, 위험 통제, 검증 증거, 운영 진단 가능성이 함께 닫혀야 한다. 이 문서는 규제 인증 완료를 선언하지 않지만, 수정과 검증은 design control, software validation, risk management 관점에서 추적 가능해야 한다.

## Review Scope

- Initial audit date: 2026-06-01
- Revalidated: 2026-06-03
- Initial branch: `hotfix/recorder-anomaly-details`
- Revalidation branch: `feature/issue-44`
- Scope:
  - `apps/vitalserver-macos-runtime`
  - `apps/vitalserver-runtime-pwa`
  - `packages/vitalserver-testkit`
  - `apps/vitaldb-observer`
  - `packages/vitalserver-devtools`
  - 이 범위 밖의 apps/packages는 이번 pass에서 제외한다.
- Baseline:
  - 직전 AGENTS.md 리뷰에서 30개 항목을 이미 확인했다.
  - 본 문서는 그 이후 추가로 추적할 후보를 등록하고, 2026-06-03 업데이트된 AGENTS.md 기준으로 활성 후보만 남긴다.
  - 기존 번호는 재검토 추적을 위해 유지하고, 삭제된 번호는 Revalidation Pass 2에 기록한다.
- Scale:
  - `apps` / `packages` 내 Swift, TypeScript, TSX, Python 파일 약 3,243개
  - 총 약 687,164 LOC
  - 위 수치는 감사 당시 로컬 측정값이며, 재분류 전 같은 명령으로 재측정한다.

## Symptoms

- UI가 읽기 실패, 누락, decode 실패를 `0`, `[]`, `Unknown`, `Stopped`, `Waiting`, `normal` 같은 값으로 표시하거나 전파할 수 있다.
- Host 런타임이 Guest 상태를 명시 계약이 아니라 probe, 파일, 오래된 상태 문서, 로그성 결과로 추정하는 후보가 있다.
- Observability와 recorder activity가 누락/실패/실제 0을 구분하지 못하는 후보가 있다.
- TestKit과 PWA가 요청 기본값을 직접 만들어 domain state처럼 전달하는 후보가 있다.
- SQLite, JSONL, Redis, 파일 시스템 adapter가 읽기 실패를 빈 값으로 축소하는 후보가 있다.

## Impact

- 실제 장애가 정상, 비어 있음, 아직 없음, 기다리는 중으로 보일 수 있다.
- recovery planner가 명시 상태가 아니라 주변 증상으로 restart/repair 결정을 만들 수 있다.
- PWA와 Swift UI가 같은 원천 데이터를 다르게 해석할 수 있다.
- 장애 재현 시점에 필요한 원인 정보가 사라져 troubleshooting 비용이 커진다.
- AGENTS.md의 핵심 원칙인 "state owner provides explicit state"가 약해진다.

## Medical Product Quality Bar

TS-039는 의료제품 수준의 runtime control 품질 기준으로 다룬다. 이 기준은 FDA QMSR/ISO 13485식 설계관리, ISO 14971식 risk management, software verification and validation 관점을 내부 개발 기준으로 번역한 것이다. 이 문서가 규제 적합성 또는 인허가를 의미하지는 않는다.

이 TS에서 요구하는 engineering bar는 아래와 같다.

- Runtime state, guest state, recorder/bed/anomaly state, event history, update/recovery state는 owner가 명시적으로 제공해야 한다.
- Missing, invalid, failed, permission denied, stale, unavailable, unsupported, zero, empty는 서로 다른 의미로 보존해야 한다.
- Repository, adapter, API, domain, recovery/update 경계는 dependency failure를 success-like empty/default value로 바꾸면 안 된다.
- Destructive action은 missing, invalid, failed, stale, unknown state에서 진행하면 안 된다. 진행하려면 명시 transition rule과 risk evidence가 있어야 한다.
- UI는 explicit state를 표시할 수는 있지만 domain state, action state, recovery decision을 만들면 안 된다.
- 모든 수정은 risk, mitigation, code change, verification evidence, residual risk로 추적 가능해야 한다.

Reference frame:

- FDA Quality Management System Regulation: https://www.fda.gov/medical-devices/postmarket-requirements-devices/quality-system-qs-regulationmedical-device-current-good-manufacturing-practices-cgmp
- FDA General Principles of Software Validation: https://www.fda.gov/media/73141/download
- ISO 14971:2019 risk management overview: https://www.iso.org/standard/72704.html

## Completion Criteria

TS-039는 아래 조건을 모두 만족해야 완료로 본다.

| Gate | Completion condition |
|---|---|
| Inventory closure | 모든 finding이 `fixed`, `not-an-issue`, `duplicate`, `transferred`, `risk-accepted` 중 하나로 닫혀야 한다. `active`, `unknown`, `needs-review`는 0개여야 한다. |
| P0/P1 closure | P0/P1 finding은 원칙적으로 `fixed` 또는 `transferred`만 허용한다. `risk-accepted`는 documented hazard analysis와 verification evidence가 있을 때만 허용한다. |
| State semantics | `missing != empty`, `failed != empty`, `permissionDenied != missing`, `invalid != unknown`, `stale != current`, `zero != notReported`, `unavailable != failed`가 contract/API/UI 전 경계에서 보존되어야 한다. |
| Fallback boundary | Contracts, repository, domain/core, recovery, update, API command, observability 경계에 state-creating fallback이 없어야 한다. |
| Source of truth | 각 상태의 owner와 consumer가 문서와 code contract에 명시되어야 한다. UI 또는 adapter가 owner가 아닌 state를 추론하면 미완료다. |
| API contract | Swift contract, Runtime Control API, OpenAPI, PWA schema가 read state/error semantics를 같은 의미로 표현해야 한다. |
| Vertical slice | 원인군별로 owner, contract, repository/adapter, API, client schema, UI, tests, troubleshooting docs가 함께 닫혀야 한다. 단일 레이어 수정만으로는 완료가 아니다. |
| Verification | missing, invalid, permission denied, dependency failure, readonly/corrupt persistence, stale state, observed zero/empty를 분리 검증하는 자동 테스트가 있어야 한다. |
| Diagnostics | failure가 발생했을 때 operator가 logs/export/API/event를 통해 원인을 확인할 수 있어야 한다. |
| Release gate | regression test, update/rollback smoke, runtime chaos 또는 equivalent scenario가 통과해야 한다. |

완료 선언 문장은 아래 의미를 만족해야 한다.

```text
Runtime-control 관련 코드에서 state owner가 아닌 계층이 상태를 추론하지 않고,
read/decode/permission/dependency failure가 empty/default success로 변환되지 않으며,
recovery/update/observability/API/UI 전 경계에서 missing/invalid/failed/stale/zero/empty
의미가 보존됨을 테스트와 문서로 증명했다.
```

## Finding Resolution States

| State | Meaning | Evidence required |
|---|---|---|
| `fixed` | 코드와 문서가 수정되어 AGENTS.md 위반이 제거됨 | linked commit/PR, test evidence, affected finding IDs |
| `not-an-issue` | 업데이트된 AGENTS.md 기준 위반이 아님 | 짧은 판단 근거, owner boundary 설명 |
| `duplicate` | 다른 finding/root cause에 포함됨 | canonical finding ID |
| `transferred` | 별도 TS/issue에서 더 좁은 범위로 추적함 | transferred TS/issue ID, scope |
| `risk-accepted` | 남는 위험을 의식적으로 수용함 | hazard, mitigation, residual risk, owner approval, expiry/review date |

## Risk Classification

| Class | Scope | Required action |
|---|---|---|
| P0 | data loss, VM disk mutation, update/rollback, install/uninstall, automatic recovery/restart, security-sensitive config | 즉시 수정 또는 destructive action 차단. Risk acceptance는 예외로만 허용한다. |
| P1 | contract/API/repository/observability/read model에서 failure semantics가 손실되는 경우 | vertical slice로 수정하고 regression test를 추가한다. |
| P2 | UI/presentation에서 explicit state를 부정확하게 표시하거나 operator action specificity를 낮추는 경우 | P0/P1 contract가 닫힌 뒤 표시 정책을 정리한다. |
| P3 | display-only label, input preset, documented default처럼 domain state를 만들지 않는 경우 | 문서화하거나 `not-an-issue`로 닫는다. |

## Architectural Invariants

TS-039 수정은 아래 invariant를 깨면 안 된다.

- Host owns runtime/process/filesystem state.
- Guest owns guest-internal observation documents and operation result documents.
- Runtime Control API owns transport contract and must preserve read state/error metadata.
- Core/domain policy consumes complete explicit input only.
- Repository/adapters report typed read/write/decode/permission/persistence failures.
- Watchdog/recovery consumes explicit health/lifecycle contracts, not logs/probes/absence alone.
- UI formats explicit state and may use display labels only after state meaning is already explicit.
- Observed zero/empty data is a valid value, but missing/failed/unavailable is not zero/empty.
- SQLite read model may be rebuildable and best-effort, but read/write degradation must remain observable.

## Root Cause Work Queue

현재 활성 항목은 개별 수정 목록이 아니라 root cause work queue로 다룬다. 같은 원인군을 하나의 vertical slice로 고쳐야 한다.

| Queue | Root cause | Representative IDs | First target |
|---|---|---|---|
| Q1 | Recovery/update/destructive decision이 explicit state 없이 진행될 수 있음 | Closed in passes 23-24 | remaining recovery/update/API command hardening |
| Q2 | Observability/read model failure가 empty/zero/unavailable로 축소됨 | 259, 261, 268, 273-285, 300 | Runtime Control observability contracts and client rendering |
| Q3 | Runtime Control API/contract optionality가 provider failure를 숨김 | 31-47 | contract and OpenAPI read state modeling |
| Q4 | PWA page/domain code가 provider failure를 local state로 보정함 | 1-27, 131-160, 164, 188-200, 210-239 | PWA schema/client/UI state rendering |
| Q5 | Swift presentation/display policy가 read model/action state를 재구성함 | 48-55, 57, 60 | SwiftUI presentation policy after API contract hardening |
| Q6 | TestKit/dev tooling이 missing provider/session state를 success-like result로 축소함 | 8-16, 123-130, 254-257 | TestKit command/result contract |

새 finding은 아래 조건일 때만 추가한다.

- 기존 queue로 설명되지 않는 새로운 root cause가 발견된다.
- P0/P1 위험으로 분류되는 destructive decision, contract loss, observability loss가 발견된다.
- 같은 패턴이 존재하지만 대표 finding이 없어 수정 범위 추적이 불가능하다.

단순 반복, display-only label, input preset, documented default는 새 finding으로 늘리지 않는다.

## Verification Matrix

| Layer | Required tests |
|---|---|
| Contracts | required provider-owned fields, missing vs null vs empty, invalid enum/raw value, backward-compatible explicit migration |
| Core/domain | missing/invalid/stale input does not advance destructive transitions, recovery suppression rules, update preflight blockers |
| Repository/adapter | missing file, permission denied, invalid JSON, partial JSONL, readonly SQLite, corrupt SQLite, wrong Redis type, command output decode failure |
| Runtime Control API | response preserves read state/read issue, command body validation rejects missing target, SSE preserves event id/type/data errors explicitly |
| PWA client/schema | Zod rejects invalid provider contract, read failure is visible, zero/empty is distinct from unavailable/failed |
| Swift UI | presentation does not synthesize domain state, missing/failed explicit states render as operator-visible issues |
| Observability | JSONL and SQLite divergence remains visible, SQLite rebuild/fallback keeps warning evidence, export includes diagnostic sources |
| Update/recovery smoke | update, rollback, clean uninstall, guest panic, readonly disk, missing runtime-config, protected operation recovery suppression |

## Cause Hypothesis

1. 여러 read API가 `Optional`, 빈 배열, 빈 문자열로 실패와 결측을 표현한다.
2. UI 편의 처리가 domain state 보정처럼 동작한다.
3. contract schema가 optional/passthrough 중심이라 provider 계약 위반을 초기에 잡지 못한다.
4. health/recovery 계층이 명시 lifecycle contract보다 probe 결과를 더 신뢰하는 경로가 있다.
5. best-effort persistence와 observability 기록 실패가 사용자 또는 operator에게 충분히 표면화되지 않는다.

## Audit Commands

```sh
rg -n '\?\?|try\?|catch|return \[\]|return nil|Unknown|not reported|default|fallback|passthrough|optional' apps packages
find apps packages -type f \( -name '*.swift' -o -name '*.ts' -o -name '*.tsx' -o -name '*.py' \) -print
```

## Active Finding Inventory

아래 항목은 2026-06-03에 업데이트된 AGENTS.md 기준으로 다시 검토한 뒤 남긴 활성 위반 후보이다. 원래 1-300번 항목 중 표시 전용 fallback, 입력 preset, documented config default, 명시 API default로 볼 수 있는 항목은 삭제했다. 기존 번호는 원본 감사 항목을 추적하기 위해 `#N` 형태로 유지한다.

- [#1] `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: VitalServer URL이 `status.proxyPort`, `settings.proxyPort`, 앱 기본 포트 순서로 합성된다. Runtime endpoint state를 UI가 보정한다.
- [#2] `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: Remote Console URL도 설정 누락 시 기본 포트로 구성된다. 설정 누락과 실제 기본값을 구분하지 못한다.
- [#3] `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: data directory 통계의 `fileCount`가 누락 시 `0`으로 표시된다. 미관측과 실제 빈 디렉터리가 섞일 수 있다.
- [#4] `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: active recorder connections가 누락 시 `0`으로 표시된다. provider 미응답과 실제 연결 0이 섞일 수 있다.
- [#5] `apps/vitalserver-runtime-pwa/src/pages/status/StatusPage.tsx`: resource usage 누락/invalid object가 `Unknown`으로만 축소된다. read failure와 not reported가 분리되지 않는다.
- [#8] `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: `beds`와 `sessions`가 status 누락 시 빈 배열로 처리된다. 읽기 실패와 실제 없음이 동일해진다.
- [#9] `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: start 가능 여부가 local selected bed count와 busy flag로 결정된다. TestKit service readiness owner가 아닌 UI가 operation state를 판단한다.
- [#10] `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: scenario/signal request가 UI string cast에 의존한다. request contract validation보다 UI 타입 단언이 앞선다.
- [#14] `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: enabled 누락이 `false`로 표시된다. disabled와 status read failure가 섞인다.
- [#15] `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: service state 누락이 `Unknown`으로 표시된다. missing, failed, unsupported를 구분하지 못한다.
- [#16] `apps/vitalserver-runtime-pwa/src/pages/testkit/TestKitPage.tsx`: sessions/beds count가 fallback 빈 배열 길이에 의존한다. read issue가 count 0으로 흐를 수 있다.
- [#17] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: activity points 누락 또는 invalid bucket seconds가 빈 series로 변환된다.
- [#18] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: parse 가능한 latest timestamp가 없으면 빈 series가 된다. invalid data와 no activity가 섞인다.
- [#19] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: `points ?? []`가 activity read failure를 빈 activity로 축소할 수 있다.
- [#20] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: timestamp 정렬 fallback이 `0`에 의존한다. invalid timestamp ordering이 암묵적으로 만들어진다.
- [#21] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: bucket seconds 누락이 `60`으로 보정된다. provider contract 누락과 실제 1분 bucket이 섞인다.
- [#22] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: invalid bucket timestamp가 skip된다. contract failure가 사용자에게 보이지 않는다.
- [#23] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: bucket 초기값이 message/byte/room count `0`으로 만들어진다. synthetic bucket과 observed zero가 구분되지 않는다.
- [#24] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: missing message/byte/room count가 `0`으로 합산된다.
- [#25] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: empty bucket이 빈 chart로 반환된다. no observations와 unavailable이 섞일 수 있다.
- [#26] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: missing time bucket을 zero bucket으로 채운다. chart rendering에는 유효할 수 있지만 synthetic state flag가 없다.
- [#27] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/recorders/recorderActivity.ts`: invalid timestamp parse가 `null`로 축소된다. invalid timestamp reason이 사라진다.
- [#31] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: capabilities contract가 optional 중심이다. provider가 capability state를 누락해도 schema가 통과할 수 있다.
- [#32] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: settings contract가 optional 중심이다. settings read failure와 unset setting이 UI에서 뒤섞일 수 있다.
- [#33] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: container observation fields가 optional이다. container read contract 위반을 조기에 막지 못한다.
- [#34] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: recorder activity observation count fields가 optional이다. missing count와 zero count가 downstream에서 섞일 수 있다.
- [#35] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: recorder identity/status fields가 optional이다. identity 없는 recorder record가 UI까지 도달할 수 있다.
- [#36] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: bed identity/status fields가 optional이다. bed relationship state의 owner contract가 약하다.
- [#37] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: anomaly kind/severity/timestamp/subject/message가 optional이다. anomaly로 등록된 원인이 불완전해질 수 있다.
- [#38] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: overview status/settings/release/install/vitalRecorder가 optional이다. overview contract failure가 빈 section으로 흐를 수 있다.
- [#39] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: runtime event document의 event type/timestamp/source/status가 optional이다. event identity contract가 약하다.
- [#40] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: event history의 events/matchingCount가 optional이다. read issue와 empty event list가 섞인다.
- [#41] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: activity bucket/point counts가 optional이다. recorder activity graph가 provider contract 누락을 보정하게 된다.
- [#42] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: VitalDB recorder record identity/status/counts/activity가 optional이다. recorder list에서 누락을 정상 데이터로 렌더링할 수 있다.
- [#43] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: VitalDB bed record identity/status/counts가 optional이다. bed list에서 contract failure가 표면화되지 않을 수 있다.
- [#44] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: activity history source/bucketCount가 optional이다. activity provenance가 약해진다.
- [#45] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: log text가 optional이다. log read failure와 empty log가 분리되지 않을 수 있다.
- [#46] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: export destination이 optional이다. export command result contract가 약하다.
- [#47] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`: update summary가 optional이다. update flow state owner가 명확하지 않다.
- [#48] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeStatusPanel.swift`: remote client host가 public host 누락 시 local hostname 또는 `localhost`로 보정된다.
- [#49] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeStatusPanel.swift`: resource usage nil이 progress `0`으로 렌더링된다. 미측정과 0% 사용량이 시각적으로 섞인다.
- [#51] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: recorder IP/bed/lastSeen 누락이 `unknown`으로 축소된다.
- [#52] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: latest activity가 array last element에 의존한다. provider ordering contract가 명시되지 않으면 UI가 latest를 추정한다.
- [#53] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: total packet과 latest bucket 계산이 UI에서 수행된다. activity summary owner 경계가 흐리다.
- [#54] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: empty activity timeline/buckets가 "no activity"로 보인다. read failure가 별도 필드 없으면 사라진다.
- [#55] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeRecordersPanel.swift`: missing metadata가 `unknown`으로 표시된다. missing과 failed가 분리되지 않는다.
- [#57] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: linked recorder가 current recorder list에서 client-side join으로 계산된다. relationship owner contract가 약하다.
- [#60] `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Views/RuntimeBedsPanel.swift`: linked recorder status/IP를 UI가 current recorders에서 추론한다.
- [#123] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: persisted session scenario 누락이 `normal`로 보정된다.
- [#124] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: missing recorders/messages/cleanup state가 empty/zero로 보정된다.
- [#125] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: connected/joinSent/messages/bytes missing이 false/zero로 보정된다.
- [#126] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/store.py`: event payload 누락이 empty list로 보정된다.
- [#127] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: recorder management provider가 없으면 cleanup이 success-like empty tuple로 끝날 수 있다.
- [#128] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: bed management provider가 없으면 bed cleanup이 success-like empty tuple로 끝날 수 있다.
- [#129] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: session save failure가 event로만 남고 API command result에 명시 실패로 반영되지 않을 수 있다.
- [#130] `packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session/manager.py`: session delete persistence failure가 event로만 남을 수 있다.
- [#131] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: beds query data가 없으면 `[]`로 필터링된다. read failure와 empty list가 UI 흐름에서 같아질 수 있다.
- [#132] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: bedID가 없는 bed record는 `identifiedBeds`에서 제외된다. identity contract failure가 목록에서 사라질 수 있다.
- [#134] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: online/stale/assignment summary를 UI가 bed record 필드로 재계산한다. summary owner가 provider인지 UI인지 흐려진다.
- [#135] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: assignment count가 `Boolean(bed.vrcode)`로 계산된다. relationship contract가 아니라 문자열 존재 여부로 상태를 만든다.
- [#139] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: table anomaly count가 누락 시 `0`으로 표시된다.
- [#142] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: observationCount 누락이 `0`으로 표시된다.
- [#143] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: invalid/missing timestamp가 sort value `0`이 된다. ordering failure가 오래된 데이터처럼 보일 수 있다.
- [#144] `apps/vitalserver-runtime-pwa/src/pages/beds/BedsPage.tsx`: `shorten()`이 missing value를 `Unknown`으로 만든다. identity missing을 정상 display text로 축소한다.
- [#146] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: missing recorder data가 `null` 후 `[]`로 흐른다. unavailable과 empty list가 섞일 수 있다.
- [#147] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: `presentInLatestObservation !== false`는 missing flag를 current로 취급한다.
- [#149] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: known/current/online/stale summary를 UI가 재계산한다. provider summary와 UI summary가 갈라질 수 있다.
- [#150] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: anomaly summary가 currentAnomalyCount missing을 `0`으로 합산한다.
- [#153] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: table anomaly count가 누락 시 `0`으로 표시된다.
- [#155] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: detail observationCount 누락이 `0`으로 표시된다.
- [#156] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: activity readError가 있어도 chart rendering은 계속된다. incomplete와 valid chart data 경계가 약하다.
- [#157] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: vrcode 없는 recorder record는 목록에서 제외된다. identity contract failure가 UI에서 사라진다.
- [#158] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: missing/invalid lastSeenAt가 sort timestamp `0`이 된다.
- [#159] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: search filter가 missing fields를 제거한다. field-level read issue가 검색 결과에서 숨겨진다.
- [#160] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: current/history toggle이 provider state가 아니라 UI flag로 current set을 만든다.
- [#164] `apps/vitalserver-runtime-pwa/src/pages/recorders/RecordersPage.tsx`: activityHistory가 optional prop이다. missing history와 no history가 chart layer에서 섞일 수 있다.
- [#188] `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: log text missing이 empty string으로 처리된다.
- [#190] `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: empty log text가 "No log lines"로 표시된다. read succeeded empty와 response missing이 섞인다.
- [#191] `apps/vitalserver-runtime-pwa/src/pages/logs/LogsPage.tsx`: canExportLogs missing이 disabled 상태로 표시된다. capability read failure와 unsupported capability가 구분되지 않는다.
- [#192] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: empty settings draft로 먼저 렌더링된다. settings load 전 draft가 domain-like form state를 만든다.
- [#194] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: minimumDiskGiB missing이 input min `1`로 보정된다.
- [#195] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: custom advertised URL 해제 시 publicHost를 empty string으로 만든다. absent와 explicit empty가 같은 request가 된다.
- [#196] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: custom advertised URL 해제 시 publicPort를 proxyPort draft로 보정한다. derived state가 UI에 생긴다.
- [#197] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: default advertised URL text가 `draft.proxyPort || 80`에 의존한다.
- [#198] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: startOnBoot disabled 조건이 settings capability와 service capability를 UI에서 조합한다.
- [#200] `apps/vitalserver-runtime-pwa/src/pages/settings/SettingsPage.tsx`: runtime control port change redirect가 fixed 1초 timeout에 의존한다. apply completion state와 server readiness가 분리되지 않는다.
- [#210] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: successful HTTP 여부가 regex로 판단된다. HTTP state owner 대신 display parser가 reachability를 추정한다.
- [#212] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: `failed` string을 unreachable로 해석한다. string contract가 typed status를 대체한다.
- [#213] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: runtime URL host가 browser location 또는 `127.0.0.1`로 추정된다.
- [#214] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: runtime URL port가 missing 시 app default proxy port로 대체된다.
- [#215] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/http.ts`: runtime control URL이 missing port 시 current origin 또는 local default로 대체된다.
- [#221] `apps/vitalserver-runtime-pwa/src/domain/runtime-control/formatting/vitalRecorder.ts`: source가 vitalDBObservation이 아니면 metric 전체를 `NOT_REPORTED`로 처리한다. unavailable reason이 metric 단위로 사라진다.
- [#261] `apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeObservabilityReader.swift`: if projection load fails but current observation exists, state is still loaded with readError. partial failure semantics need explicit UI handling.
- [#276] `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: duplicate recorder observations are collapsed by preferredRecorder. duplicate state can disappear unless anomaly policy preserves it.
- [#277] `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: duplicate bed observations are collapsed by preferredBed.
- [#281] `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: missing latest recorder maps to offline.
- [#282] `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: projected activity timeline missing becomes empty array.
- [#284] `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: missing latest bed maps to offline.
- [#285] `apps/vitalserver-macos-runtime/Sources/RuntimeControl/RuntimeControlReadModels.swift`: present but not online bed maps to stale without explicit stale owner field.

## Revalidation Pass 2

분류일: 2026-06-03

업데이트된 AGENTS.md의 Fallback Boundaries, Purity Boundaries, Layer Boundaries를 기준으로 1-300번을 재검토했다.

| Result | Count | Original IDs | Meaning |
|---|---:|---|---|
| Active | 228 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-300 | 상태 owner가 아닌 계층이 상태를 추론하거나, read/decode/permission/persistence 실패를 빈 값, `0`, `Unknown`, 성공 비슷한 결과로 축소할 수 있어 계속 추적한다. |
| Removed | 72 | 6-7, 11-13, 28-30, 50, 56, 58-59, 61, 133, 136-138, 140-141, 145, 148, 151-152, 154, 161-163, 171, 174-178, 183-187, 189, 193, 199, 201-209, 211, 216-220, 222-225, 227-229, 231-233, 235-237, 248, 250-251 | 업데이트된 AGENTS.md에서 허용한 표시 전용 fallback, 입력 preset, documented config default, 명시 API default, 또는 domain state를 만들지 않는 UI selection/display 처리로 판단해 활성 목록에서 삭제했다. |

경로만 이동된 항목은 삭제하지 않고 새 경로로 갱신했다.

- 31-47: `apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts`
- 62-70: `apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp/Presentation/Policies/RuntimeStatusDisplayPolicy.swift`
- 91-97: `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/*`
- 98-100: `apps/vitalserver-macos-runtime/Sources/HostInfrastructure/*`
- 299: `apps/vitalserver-macos-runtime/Sources/Core/Policy/RuntimeUpdatePreflightPolicy.swift`

## Resolution Pass 3

분류일: 2026-06-03

Q1 P0 recovery planner vertical slice를 먼저 닫았다. VM restart가 guest readiness, missing VM IP, container failure 같은 guest-facing state에 의존할 때는 explicit VM lifecycle document가 필요하다. `RuntimeServiceState.readFailed`, `permissionDenied`, `unknown`은 service restart로 보정하지 않고 recovery blocker로 보고한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 75, 76, 288 | `RuntimeRecoveryPlan.blockers` 추가, missing lifecycle/service read failure blocker 추가, `RuntimeWatchdogRecoveryPolicy`가 blocker reason을 operator-facing reason으로 노출. |
| Active after pass | 225 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-287, 289-300 | #79 등 HTTP status 문자열/typed probe semantics 문제는 별도 active finding으로 유지한다. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeRecoveryPlannerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRecoveryPolicyTests
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
```

## Resolution Pass 4

분류일: 2026-06-03

Q1 P0 recovery planner의 HTTP probe semantics를 분리했다. `RuntimeRecoveryPlanner`는 HTTP 값을 `successful`, `unsuccessful`, `readFailed`로 분류하고, `"failed"`, `"invalid-response"` 같은 non-numeric probe/read failure를 restart action으로 보정하지 않는다. `bootstrap-pending`과 `missing-vm-ip`는 guest pending state로 유지해 lifecycle deferral 규칙을 보존한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 79 | non-numeric HTTP probe/read failure를 `RuntimeRecoveryPlan.blockers`로 보고하고, `RuntimeWatchdogRecoveryPolicy`가 blocker reason을 unrecoverable reason으로 노출. |
| Active after pass | 224 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-287, 289-300 | #289 등 다른 HTTP status parser는 별도 active finding으로 유지한다. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeRecoveryPlannerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRecoveryPolicyTests
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
```

## Resolution Pass 5

분류일: 2026-06-03

Q1 P0 watchdog recovery policy에서 empty failureReasons contract inconsistency를 닫았다. `RuntimeHealthSnapshotPolicy`는 명시 실패 상태가 있는데 `failureReasons`가 비어 있는 snapshot을 healthy로 보지 않고 `runtime-health-snapshot-missing-failure-reasons` issue로 보고한다. Watchdog recovery decision은 이 issue를 recover plan으로 넘기지 않고 unrecoverable reason으로 노출한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 286 | `RuntimeHealthSnapshotPolicy.missingFailureReasonIssue` 추가, `RuntimeWatchdogRecoveryPolicy` issue handling 추가, HostCLI watchdog runner가 explicit lifecycle input을 유지하도록 테스트 갱신. |
| Active after pass | 223 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 287, 289-300 | `vmState`만으로 failureReasons 누락을 판단하지 않는다. healthy observation 후 lifecycle finalization 같은 transient runner contract를 보존한다. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRunnerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthWaitRunnerTests
```

## Resolution Pass 6

분류일: 2026-06-03

Q1 P0 watchdog suppression policy에서 preservation-sensitive failure reason 누락을 닫았다. 자동 복구 suppression은 이제 `snapshot.vmErrors`뿐 아니라 `snapshot.failureReasons`의 `requiresDataPreservationBeforeRecovery` contract도 확인한다. VM storage/disk 보존이 필요한 failure reason은 VM restart plan으로 넘어가지 않고 suppression reason으로 유지된다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 287 | `RuntimeWatchdogRecoveryPolicy.automaticRecoverySuppressionReason`이 preservation-sensitive `RuntimeFailureReason`을 확인하도록 확장. |
| Active after pass | 222 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-300 | Destructive recovery suppression is now based on both VM error and failure reason contracts. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
```

## Resolution Pass 7

분류일: 2026-06-03

Q1 P0 update preflight storage requirement에서 missing size와 unchanged rootfs 의미를 분리했다. `RuntimeUpdatePreflightPolicy.storageRequirement`는 더 이상 optional installed/incoming rootfs size를 받지 않고, `RuntimeUpdateRootfsStorageInput.unchanged` 또는 `.replacing(installedRootfsBytes:incomingRootfsBytes:)`를 받는다. 따라서 rootfs 변경 없음은 명시 상태이고, rootfs size read failure는 caller에서 throw되어 `0`으로 계산될 수 없다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 299 | Optional size inputs 제거, `RuntimeApplyBundlePreflightRunner`가 rootfs replacement 시 non-optional file sizes를 읽어 policy에 전달. |
| Active after pass | 221 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-298, 300 | Update storage preflight no longer converts missing rootfs size to zero. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeUpdatePreflightPolicyTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeApplyBundlePreflightRunnerTests
```

## Resolution Pass 8

분류일: 2026-06-03

Q1 P0 runtime health waiter의 failure reason preservation을 닫았다. Required service pending 상태와 snapshot failure reason을 같은 attempt의 explicit reason set으로 병합하고, guest bootstrap failure는 service pending보다 먼저 early failure로 반환한다. Timeout result는 마지막 attempt만 반환하지 않고 관측된 distinct reason들을 순서 보존 set으로 누적한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 293, 294 | `RuntimeHealthWaiter`가 pending service reasons와 snapshot reasons를 병합하고, timeout에 accumulated unique reasons를 반환. |
| Active after pass | 219 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-292, 295-298, 300 | Health wait timeout now preserves earlier distinct failure states. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthWaiterTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthWaitRunnerTests
```

## Resolution Pass 9

분류일: 2026-06-03

Q1 P0 guest worker evaluator에서 missing result와 pending/running worker state를 분리했다. Activation, shutdown, datastore repair evaluator decision에 `missing(message:)` case를 추가하고, waiters는 missing을 계속 대기할 수 있더라도 decision type에서는 pending/running과 구분한다. 사용자-facing progress message는 유지해 운영 로그 churn은 만들지 않았다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 296, 297, 298 | `GuestActivationDecision`, `GuestShutdownDecision`, `DatastoreRepairDecision`에 missing case 추가. |
| Active after pass | 216 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-292, 295, 300 | Missing guest worker result no longer shares the same decision case as pending/running worker progress. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter GuestActivationEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter GuestShutdownEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter DatastoreRepairEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter GuestActivationWaiterTests
swift test --package-path apps/vitalserver-macos-runtime --filter DatastoreRepairWaiterTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeGuestActivationRunnerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeGuestShutdownRunnerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeDatastoreRepairResultWaiterTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeDatastoreRepairRunnerTests
```

## Resolution Pass 10

분류일: 2026-06-03

Q1 P0 guest bootstrap observation semantics를 닫았다. `GuestBootstrapEvaluator`는 더 이상 missing bootstrap result를 nil failure reason으로 축약하지 않고 `GuestBootstrapAssessment.missing`, `.unavailable`, `.notCurrentBoot`, `.noFailure`, `.failed`로 구분한다. `RuntimeHealthInput`은 optional failure reason 대신 assessment를 받으며, `RuntimeVMHealthPolicy`는 guest HTTP 실패 상태에서 missing/unavailable bootstrap result를 typed VM error와 failure reason으로 노출한다. 정상 bootstrapping lifecycle에서는 missing result를 failure로 승격하지 않는다. Watchdog recovery는 bootstrap observation issue가 있으면 VM restart plan을 만들지 않고 unrecoverable reason으로 남긴다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 82, 292, 295 | `GuestBootstrapAssessment` 추가, `RuntimeHealthInput.guestBootstrapAssessment` 적용, `RuntimeVMError`/`RuntimeFailureReason`에 bootstrap result missing/unavailable contract 추가. |
| Active after pass | 213 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-81, 83-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-291, 300 | Missing bootstrap result is explicit state and no longer aliases with no bootstrap failure. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter GuestBootstrapEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter ContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRecoveryPolicyTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthCheckerTests
```

## Resolution Pass 11

분류일: 2026-06-03

Q1 P0 apply-bundle rootfs size read semantics를 닫았다. Rootfs replacement preflight는 installed/incoming rootfs size를 non-optional `fileSize` read로 가져오고, read failure를 `0`으로 로그하거나 storage requirement 계산으로 넘기지 않는다. Rootfs가 bundle에 없는 경우만 `.unchanged` explicit state로 처리한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 87 | `RuntimeApplyBundlePreflightRunner` rootfs size read failure propagation regression test 추가. |
| Active after pass | 212 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 80-81, 83-86, 88-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-291, 300 | Rootfs size read failure now remains a failed preflight dependency, not zero-byte input. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeApplyBundlePreflightRunnerTests
```

## Resolution Pass 12

분류일: 2026-06-03

Q1 P0 Host proxy nginx PID read semantics를 닫았다. `RuntimeHealthChecker`의 `try?` 기반 trimmed text read helper를 제거하고, expected nginx PID read를 `RuntimeProxyNginxPIDReadResult.loaded/missing/empty/readFailed`로 모델링했다. `RuntimeHostProxyPortCleaner`는 PID read failure에서 listener cleanup을 진행하지 않고 명시 실패로 중단한다. Missing/empty PID는 read failure와 구분되며, command-line ownership 확인 경로는 유지된다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 80 | `readInstalledProxyNginxPID()` typed result 추가, `RuntimeHostProxyPortCleaner.expectedProxyNginxPID` typed contract 적용. |
| Active after pass | 211 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 81, 83-86, 88-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 289-291, 300 | PID file read failure no longer aliases with missing/empty before cleanup or listener ownership checks. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthCheckerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHostProxyPortCleanerTests
```

## Resolution Pass 13

분류일: 2026-06-03

Q1 P0 guest runtime/HTTP observation semantics를 닫았다. `RuntimeHealthInput`은 더 이상 `vmIP`, `guestHTTP`, `guestRuntimeStatePresent`, `guestRuntimeStateFresh` 조합으로 상태를 압축하지 않고 `RuntimeGuestRuntimeStateInput.fresh/missing/invalid/stale`와 `RuntimeGuestHTTPStatusInput.reportedStatus/missing/probeFailed`를 받는다. `RuntimeVMHealthPolicy`는 non-numeric HTTP probe failure, missing guest HTTP, missing VM IP, missing/invalid/stale runtime state를 각각 별도 VM error와 failure reason으로 보존한다. Guest bootstrap failure도 current boot의 explicit failure면 HTTP 2xx와 독립적으로 실패로 유지하고, 이전 boot 결과는 `.notCurrentBoot`로만 무시한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 4 | 81, 289, 290, 291 | Guest runtime/HTTP read result를 typed Core input으로 전달하고, runtime state missing/invalid/stale와 HTTP missing/probeFailed를 분리했다. |
| Active after pass | 207 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 83-86, 88-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 300 | Missing/invalid/stale/probe-failed state no longer aliases with string fallback or inferred HTTP failure. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthCheckerTests
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
swift test --package-path apps/vitalserver-macos-runtime --filter HostCLITests
swift test --package-path apps/vitalserver-macos-runtime --filter ContractsTests
git diff --check
```

## Resolution Pass 14

분류일: 2026-06-03

Q1 P0 container observation read semantics를 닫았다. `RuntimeContainerObservation`은 `auditProxyStatusReadError`, `runtimeStateFileMetadataError`, `composeServicesReadError`를 보존한다. `RuntimeHealthChecker`는 fresh runtime state의 missing `containerServices`, stale/invalid/missing runtime state, runtime-state mtime read failure, audit proxy command/decode failure를 빈 배열이나 nil 성공으로 축소하지 않는다. mtime read failure는 stale이 아니라 invalid runtime state로 전달한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 83, 84, 85 | `RuntimeContainerObservation` read-error fields 추가, `composeServices()` typed result 추가, runtime-state mtime read result와 audit proxy status decode result를 명시화했다. |
| Active after pass | 204 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 86, 88-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 300 | Container observation can now distinguish observed empty services from missing/unavailable/decode-failed dependencies. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthCheckerTests
swift test --package-path apps/vitalserver-macos-runtime --filter ContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
swift test --package-path apps/vitalserver-macos-runtime --filter HostCLITests
git diff --check
```

## Resolution Pass 15

분류일: 2026-06-03

Q1 후보 #86을 재분류해 active inventory에서 삭제했다. `RuntimeLifecycle+Workflows.runtimeStatusPrinter()`의 `vmIP: { statusReporter.loadStatus()?.vmIP ?? "not reported" }`는 `RuntimeStatusPrinter`가 `printStatus()`에서 사람에게 출력하는 display label이다. 이 값은 Host command, recovery, update, API contract, observability persistence 입력으로 소비되지 않는다. AGENTS.md의 allowed fallback인 display labels에 해당한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Deleted as allowed display label | 1 | 86 | `RuntimeStatusPrinter`의 출력 전용 label이며 state owner contract나 operation transition을 만들지 않는다. |
| Active after pass | 203 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 88-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 300 | P0 queue no longer includes display-only fallback labels. |

검증:

```sh
rg -n "not reported|RuntimeStatusPrinter|vmIP" apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeLifecycle+Workflows.swift apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeStatusPrinter.swift
```

## Resolution Pass 16

분류일: 2026-06-03

Q1 P0 guest runtime config defaults를 닫았다. Install config writer는 admin password 누락을 default admin으로 보정하지 않고 `missingArgument`로 중단한다. `GuestRuntimeConfigDocument.load`는 missing `runtime-config.json`을 `.default` document로 바꾸지 않고 `missingFile`로 보고한다. Guest config decode는 required field decode로 누락 필드를 실패로 보존하고 있음을 focused test로 재확인했다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed/Revalidated | 3 | 88, 89, 90 | `RuntimeGuestConfigWriter` requires explicit `adminPassword`, `GuestRuntimeConfigDocument.load` throws on missing file, required-field decode test remains. |
| Active after pass | 200 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 77-78, 91-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 300 | Security-sensitive runtime config no longer creates default domain state from missing install/config files. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeGuestConfigWriterTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeConfigureRunnerTests
swift test --package-path apps/vitalserver-macos-runtime --filter HostCLITests
swift test --package-path apps/vitalserver-macos-runtime --filter CoreTests
swift test --package-path apps/vitalserver-macos-runtime --filter ContractsTests
git diff --check
```

## Resolution Pass 17

분류일: 2026-06-03

Q1 P0 recovery restart effect semantics를 닫았다. `RuntimeRecoveryPlan`은 이제 boolean restart effects만 반환하지 않고 `RuntimeRecoveryRestartReason` 목록을 함께 반환한다. VM restart에 따른 proxy restart는 `vmRestartRequiresProxyRestart` reason으로 명시되며, proxy service/liveness/readiness로 인한 proxy restart도 각각 typed reason으로 보존된다. Watchdog runner는 recovery plan log와 `recoveryPlanned` event에 restart reason code를 포함한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 77, 78 | `RuntimeRecoveryRestartReason` 추가, planner restart effect reasons 추가, watchdog recovery plan log/event reason codes 추가. |
| Active after pass | 198 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 91-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-285, 300 | Proxy restart is no longer an unlabelled boolean side effect of VM restart or host proxy probe booleans. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeRecoveryPlannerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRecoveryPolicyTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRunnerTests
```

## Resolution Pass 18

분류일: 2026-06-03

Q1 P0 TestKit API command body semantics를 닫았다. `RuntimeTestKitAPIRouter`는 pause/resume/stop/delete command에서 empty body나 nil/blank `sessionID`를 accepted target으로 넘기지 않는다. 해당 command는 `decodedBody`와 `requiredSessionID`를 통해 명시 target body를 요구하며, 누락/invalid body는 `badRequest`로 반환된다. TestKit router도 `RuntimeControlHTTPQueryError`를 400으로 분리해 bad request와 handler failure를 구분한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 254, 255, 256 | TestKit session command body validation 추가, `optionalDecodedBody` 제거, query error badRequest mapping 추가, missing/null/blank sessionID rejection test 추가. |
| Active after pass | 195 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 91-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-253, 257-285, 300 | API command target omission no longer becomes an accepted optional session operation. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
```

## Resolution Pass 19

분류일: 2026-06-03

Q1 P0 settings start-on-boot read semantics를 닫았다. `SystemRuntimeSettingsReader`는 `launchctl print-disabled system` 실패를 silent nil로 축소하지 않고 `RuntimeSettingsReadIssue(source: "startOnBoot", message: ...)`로 남긴다. `startOnBootConfigurable=false`는 유지하지만 read failure 원인이 Settings read issues에 표시된다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 103 | Settings reader launchctl runner 주입, startOnBoot read failure issue 추가, deterministic failure test 추가. |
| Active after pass | 194 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 91-102, 104-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-253, 257-285, 300 | Settings UI can see launchctl read failure separately from an intentionally unsupported start-on-boot control. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeSettingsReaderTests
```

## Pass 20 - Status read probe/service failure contract

분류일: 2026-06-03

Q1/P1 status read boundary에서 `curl` probe failure와 `launchctl` service read failure를 string/Bool fallback으로 축소하던 문제를 닫았다. `RuntimeStatus`는 `RuntimeStatusReadIssue`와 typed service state fields를 운반하고, `SystemRuntimeStatusReader`는 Host command 결과를 `RuntimeServiceState` 또는 status read issue로 보존한다. Swift UI와 Remote Console은 typed service state/read issue를 표시하며, read issue만 있는 경우 service repair를 추론하지 않고 로그 확인으로 안내한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 104, 105 | RuntimeStatus read issues/service states 추가, curl/launchctl command runner 주입, Swift UI/Remote Console rendering 갱신, focused contract/reader/policy tests 추가. |
| Active after pass | 192 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 91-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-247, 249, 252-253, 257-285, 300 | Status consumers can now distinguish not loaded, read failed, permission denied, and HTTP probe command failure without relying on legacy Bool/String fields. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeSettingsReaderTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeStatusDisplayPolicyTests
```

## Pass 21 - API stream capability routing

분류일: 2026-06-03

Runtime Control API stream routing에서 unsupported stream capability가 optional `nil`로 표현되던 문제를 닫았다. Endpoint metadata가 `RuntimeControlAPIStreamCapability`를 명시적으로 소유하고, router는 `.supported` endpoint에서만 stream builder를 호출한다. VitalDB recorders/recorder/relationships endpoints는 stream-capable endpoint가 아니라는 사실을 명시 contract로 노출한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 240 | RuntimeControlAPIEndpoint.streamCapability 추가, router stream 분기에서 optional nil 제거, unsupported VitalDB stream capability regression test 추가. |
| Active after pass | 191 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 91-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-285, 300 | Stream-capable and non-stream endpoints are now explicit endpoint metadata, not an optional route-builder side effect. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
```

## Pass 22 - Current VitalDB observation source absence

분류일: 2026-06-03

Current VitalDB observation fallback에서 guest runtime state 또는 runtime status 문서 결측이 조용히 무시되던 문제를 닫았다. `RuntimeVitalDBCurrentObservationProvider.live`는 `runtimeState=missing`, `runtimeStatus=missing`을 read issue로 남기고, fallback source를 사용할 때도 이전 source 결측을 보존한다. projection failure와 current source absence는 서로 다른 read issue로 함께 표시된다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 266, 267 | Missing guest runtime state/status를 current observation read issues에 추가, status fallback and unavailable/failure regression tests 추가. |
| Active after pass | 189 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-74, 91-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | Current observation provider now preserves missing source state instead of treating fallback/unavailable as clean absence. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeObservabilityReaderTests
```

## Pass 23 - Observation Health Source Contract

분류일: 2026-06-03

Q1 P0 observation health source semantics를 닫았다. `RuntimeHealthInput`과 `RuntimeRecoveryInput`은 container/VitalDB observation을 Optional document가 아니라 `RuntimeObservationInput.notReported/missing/readFailed/loaded`로 받는다. Missing/readFailed observation source는 typed failure reason으로 노출되고, watchdog은 해당 issue를 자동 recovery plan으로 진행하지 않는다. VM restart 판단은 loaded container observation의 explicit critical container failure에만 반응한다. Duplicate/offline/stale recorder anomaly는 observation document에 operator-visible data로 남기되 runtime restart reason에서는 제외되는 기준을 policy/test로 명시했다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 4 | 71, 72, 73, 74 | `RuntimeObservationInput` 추가, observation missing/readFailed failure reason 추가, watchdog observation source blocker 추가, recorder anomaly runtime-health/operator-visible split test 추가. |
| Active after pass | 185 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 62-70, 91-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | Observation source absence no longer aliases with no failure, and missing observation cannot create a destructive restart decision. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthEvaluatorTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeRecoveryPlannerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeWatchdogRecoveryPolicyTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeHealthCheckerTests
swift test --package-path apps/vitalserver-macos-runtime --filter ContractsTests
```

## Pass 24 - Swift Status Display Explicitness

분류일: 2026-06-03

Q1 P0 Swift status display policy의 state/action fallback을 닫았다. `RuntimeStatusDisplayPolicy`는 missing runtime state를 더 이상 `Starting`으로 보정하지 않고 `Unknown`으로 표시한다. Host proxy/HTTP nil, numeric failure, probe failure는 `Not reported`/`Unavailable`/`Failed`/`Unreachable`로 분리된다. `actionNeeded`는 service bool 또는 HTTP 문자열만으로 repair action을 만들지 않고 explicit failure reason/read issue만 표시한다. Recommended action은 domain recovery action label을 보존한다. Recorder summary는 status copy mutation 대신 explicit container/VitalDB observation input을 사용하고, missing recorder IP를 `Unknown`이 아닌 `Not reported`로 표시한다. VitalServer uptime은 status `startedAt` fallback을 사용하지 않으며, missing compose service와 running-without-health는 healthy로 승격하지 않는다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 9 | 62, 63, 64, 65, 66, 67, 68, 69, 70 | Runtime status display policy fallback 제거, `RuntimeVitalRecorderSummary(containerObservation:vitalDBObservation:)` 추가, focused display tests 추가. |
| Active after pass | 176 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 91-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | Swift UI now formats explicit state without inventing runtime readiness, recovery action, recorder state, or healthy compose state. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeStatusDisplayPolicyTests
```

## Pass 25 - JSONL Runtime Event Read Issues

분류일: 2026-06-03

P1 observability event history에서 JSONL read issue를 숨기던 convenience 경로를 제거했다. `JSONLRuntimeEventRepository`와 `CompositeRuntimeEventRepository`는 read issue를 전달하는 `query` 경로만 노출한다. JSONL rotation file size lookup은 missing size attribute를 `0`으로 보정하지 않고 explicit error로 중단한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 91, 92, 93 | JSONL/Composite `recent(limit:)` 제거, tests를 `query`로 전환, JSONL file size missing attribute fallback 제거. |
| Active after pass | 173 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 94-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | Runtime event JSONL read issues can no longer be discarded by a public recent-events path. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter HostInfrastructureTests
```

## Pass 26 - SQLite Observability Read Issues

분류일: 2026-06-03

P1 observability read model에서 SQLite projection read failure를 `nil`/empty result로 축소하던 경로를 닫았다. `SQLiteRuntimeObservabilityStore`와 `SQLiteVitalDBObservationRepository`는 best-effort latest/list API를 더 이상 노출하지 않고, runtime events는 `RuntimeEventPage.readError`를 보존하는 `query` 경로만 제공한다. VitalDB observation, recorder activity, assignment, relationship projection row decode는 필수 column 누락과 invalid enum value를 typed error로 보고한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 4 | 94, 95, 96, 97 | SQLite `recent`/`bestEffort*` public API 제거, projection row required column/enum decode 추가, corrupt SQLite payload/relationship row regression tests 추가. |
| Active after pass | 169 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 98-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | SQLite projection read/decode failure can no longer disappear through nil/empty convenience paths. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter HostInfrastructureTests
```

## Pass 27 - File and Storage Usage Read Semantics

분류일: 2026-06-03

P1 storage/read model adapter에서 filesystem metadata와 capacity read failure를 `0`으로 축소하던 경로를 닫았다. `SystemRuntimeFileStore`는 missing file size, missing directory flag, missing regular-file flag를 typed error로 보고한다. Recursive file size 계산은 observed zero-byte file과 missing file size metadata를 분리한다. `SystemRuntimeStorageUsageProvider`는 total capacity 또는 available capacity가 누락되면 loaded usage를 만들지 않고 `.unavailable`을 반환하며, resource value read failure는 `.failed`로 보존한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 98, 99, 100 | `SystemRuntimeFileStoreError` 추가, file/directory resource-value fallback 제거, storage capacity DTO와 missing available capacity regression tests 추가. |
| Active after pass | 166 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 101-102, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | File metadata and capacity dependency failure can no longer become observed zero-size/zero-available storage state. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter HostInfrastructureTests
```

## Pass 28 - Runtime Settings Provider Field Semantics

분류일: 2026-06-03

P1 settings read boundary에서 vmConfig provider field 누락을 default settings로만 축소하던 경로를 닫았다. `SystemRuntimeSettingsReader`는 vmConfig `network.mode`를 explicit enum으로 적용하고, bridged mode에서 `bridgedInterface`가 누락되면 read issue를 남긴다. `autoRecoveryEnabled`와 `preventSystemSleep`도 누락 시 default value를 표시하더라도 provider contract issue를 `RuntimeSettings.readIssues`로 보존한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 101, 102 | vmConfig network/app setting field read issue 추가, invalid network mode and missing provider field regression tests 추가. |
| Active after pass | 164 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 106-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | Runtime settings defaults can remain display/config defaults, but provider-owned field absence is no longer silent. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeSettingsReaderTests
```

## Pass 29 - Adapter Log and Process Output Read Semantics

분류일: 2026-06-03

P1 adapter diagnostics boundary에서 invalid UTF-8과 missing permission metadata를 empty/default value로 축소하던 경로를 닫았다. `SystemRuntimeHostFileReader`는 log tail bytes가 valid UTF-8이 아니면 replacement text를 만들지 않고 read failure로 표시한다. `RuntimeCommandResult`는 stdout/stderr decode issue를 `outputIssues` contract로 운반하며 legacy payload는 empty issues로 decode한다. `ProcessRunner`는 invalid stdout/stderr bytes를 empty string만으로 반환하지 않고 output issue를 기록한다. Log export archive failure summary도 output issue를 포함하며, staging item POSIX permission metadata 누락은 permission `0`으로 보정하지 않고 explicit exporter error로 실패한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 3 | 106, 107, 108 | `RuntimeCommandOutputIssue` contract 추가, invalid UTF-8 log/process output tests 추가, log export output issue summary test 추가, POSIX permission fallback 제거. |
| Active after pass | 161 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 109-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | Operator diagnostics no longer lose invalid text output/read metadata as empty strings or replacement text. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeFileReaderTests
swift test --package-path apps/vitalserver-macos-runtime --filter ProcessRunnerTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeLogExporterTests
```

## Pass 30 - TestKit Adapter Read Issue Semantics

분류일: 2026-06-03

P1 TestKit adapter boundary에서 endpoint/API/service read failure가 `lastError` 문자열 fallback만으로 남던 경로를 닫았다. `RuntimeTestKitStatus`는 `readIssues`를 운반하고 legacy payload는 empty issues로 decode한다. `MacTestKitController`는 missing API endpoint, unreachable API, container API read failure, missing service observation/state/health, invalid UTF-8 HTTP error body를 source별 read issue로 보고한다. Unhealthy API status는 이전 `lastError`를 재사용하지 않고 현재 service/API state로부터 message를 만든다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 4 | 109, 110, 111, 112 | `RuntimeTestKitReadIssue` contract 추가, controller read issue propagation, invalid UTF-8 HTTP body handling, focused TestKit controller/contract tests 추가. |
| Active after pass | 157 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 113-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | TestKit adapter status no longer relies on stale/local `lastError` fallback as the only failure carrier. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter MacTestKitControllerTests
```

## Pass 31 - VitalDB Observer Source Read Issues

분류일: 2026-06-03

P1 VitalDB observer source boundary에서 audit/proxy/bed/Redis read failure가 empty activity,
empty proxy connection list, raw bed value, partial Redis key list로 축소되던 경로를 닫았다.
`ObservationDocument`는 `readIssues`를 운반하고 Swift `VitalDBObservationDocument`, Runtime Control
OpenAPI, PWA generated/schema contract가 같은 필드를 보존한다. Collector는 malformed audit event,
invalid timestamp, missing vrcode, invalid numeric payload, missing/malformed access log, invalid UTF-8,
malformed bed JSON을 source별 read issue로 기록한다. Redis adapter는 wrong type, non-string member,
malformed SCAN response를 더 이상 empty/partial success로 반환하지 않고 `RedisProtocolError`로 실패한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 10 | 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 | Observer `readIssues` contract 추가, collector source issue propagation, Redis protocol error hardening, Swift/PWA/OpenAPI parity, focused collector/Redis/contract tests 추가. |
| Active after pass | 147 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164-170, 172-173, 179-182, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | VitalDB observer source read/parse failures no longer alias with observed empty recorder activity/proxy state or partial Redis key scans. |

검증:

```sh
.venv/bin/python -m pytest apps/vitaldb-observer/tests
.venv/bin/ruff check apps/vitaldb-observer
.venv/bin/python -m mypy apps/vitaldb-observer
swift test --package-path apps/vitalserver-macos-runtime --filter VitalDBObservationDocumentTests
swift test --package-path apps/vitalserver-macos-runtime --filter HostInfrastructureTests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test
```

## Pass 32 - PWA Observability Explicit Read Rendering

분류일: 2026-06-03

P1 PWA Observability page에서 Runtime events, VitalDB observation, guest log sync service read state가
`0`, empty list, `Stopped`, `Unavailable`로 축소되던 경로를 닫았다. Page 내부에
`RuntimeEventsRead`와 `VitalDBObservationRead`를 두고 query missing, failed, unavailable, notReported,
loaded를 분리한다. Runtime event response가 `events`를 제공하지 않으면 empty list가 아니라 incomplete
response error로 표시한다. VitalDB snapshot failed/unavailable/notReported는 anomaly absence와 분리하고,
observation `readIssues`가 있으면 "No recorder anomalies"를 표시하지 않는다. Event item은 operation과
source를 합치지 않고 별도로 표시하며, message 누락을 event type으로 숨기지 않는다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 12 | 165, 166, 167, 168, 169, 170, 172, 173, 179, 180, 181, 182 | PWA Observability explicit read-state helpers, source/missing/failure rendering, no-message/source tests, runtime event missing-response tests 추가. |
| Active after pass | 135 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 241-247, 249, 252-253, 257-265, 268-285, 300 | PWA Observability no longer turns provider omission/read failure/source read issue into observed zero/empty UI state. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test
```

## Pass 33 - Runtime Control API Stream/Query Boundary Semantics

분류일: 2026-06-03

P1 Runtime Control API boundary에서 VitalDB observation stream, SSE frame encoding, query parsing이 provider/read
state를 축소하던 경로를 닫았다. `/vitaldb/observations/stream`은 더 이상
`snapshot.observation`만 전송하지 않고 JSON encoded `RuntimeVitalDBObservationSnapshot`을 전송해
`state`와 `readError`를 보존한다. SSE frame codec은 missing id/event/data와 invalid UTF-8 payload를
empty/default frame으로 만들지 않고 typed encoding error로 실패한다. Error response body는 fallible
`try?` encoding 대신 deterministic JSON string encoder를 사용해 nil/empty body가 되지 않는다. Runtime
event query는 duplicate parameter, value 없는 parameter, unknown event type을 bad request로 거절한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 8 | 241, 242, 243, 244, 245, 246, 247, 249 | VitalDB observation stream snapshot payload 적용, SSE encoding error 추가, deterministic error response body, duplicate/missing-value/unknown-type query rejection tests 추가. |
| Active after pass | 127 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 252-253, 257-265, 268-285, 300 | Runtime Control API no longer turns observation read failure into null-only stream state or malformed API inputs into accepted defaults. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
```

## Pass 34 - Runtime Observability Reader Source/ReadError Semantics

분류일: 2026-06-03

P1 `SystemRuntimeObservabilityReader`에서 current observation provider 선택과 VitalDB recorder/relationship read
failure 보존을 명시화했다. Production reader는 더 이상 initializer 내부에서 `.live(paths:)`를 암묵 선택하지
않고 `SystemRuntimeObservabilityReader.live(paths:)` factory를 통해 live source를 명시한다. Recorder history는
top-level `readError`를 추가해 observation/current/activity projection read failure가 `recorders=[]` 또는
`activityHistory.unavailable`로만 보이지 않게 했다. Relationship history는 assignment/event projection
`readError` 의미를 Runtime Control API/OpenAPI 문서에 명시했다. Current observation이 SQLite projection보다
우선되는 freshness policy도 문서화했다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 6 | 258, 260, 262, 263, 264, 265 | Explicit live reader factory, `RuntimeVitalRecorderHistory.readError`, OpenAPI/PWA generated contract parity, reader/chaos/settings tests 갱신. |
| Active after pass | 121 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 252-253, 257, 259, 261, 268-285, 300 | Runtime observability reader no longer hides projection/current source selection or recorder/relationship projection read failures as empty history. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeObservabilityReaderTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeSettingsReaderTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeChaosScenarioTests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 35 - Runtime Vital Recorder Activity Point Decode Semantics

분류일: 2026-06-03

P1 `RuntimeVitalRecorderActivityPoint` decode boundary에서 activity metric 누락을 `0` 또는 empty bucket list로
보정하던 경로를 닫았다. `roomCount`, `messagesPerSecond`, `bytesPerSecond`, `buckets`는 recorder activity
read model의 필수 contract이므로 missing payload는 decode failure로 드러난다. `0`은 provider가 명시적으로
보고한 측정값일 때만 의미가 있다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 4 | 269, 270, 271, 272 | Activity point custom decode에서 required decode 적용, complete/missing payload regression test 추가. |
| Active after pass | 117 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 252-253, 257, 259, 261, 268, 273-285, 300 | Missing recorder activity metrics no longer become observed zero values or empty bucket observations. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
```

## Pass 36 - Runtime Control Error Response Body Encoding

분류일: 2026-06-03

P1 Runtime Control/TestKit API error response body encoding에서 fallible `try? JSONEncoder().encode(...)` 경로를
제거했다. `RuntimeControlErrorResponseEncoder`가 string-only deterministic JSON body를 생성하며, Runtime
Control router, TestKit router, HTTP wire codec이 같은 encoder를 사용한다. 따라서 error response가 nil/empty
body로 축소되지 않고, operator-facing message escaping도 같은 규칙을 따른다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 257 | Shared deterministic `RuntimeControlErrorResponseEncoder`, Runtime/TestKit/wire codec 적용, JSON escaping regression test 추가. |
| Active after pass | 116 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 252-253, 259, 261, 268, 273-285, 300 | TestKit/API bad request and handler failure responses can no longer lose their typed error body. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
```

## Pass 37 - Runtime Control Request Body Decode Error Semantics

분류일: 2026-06-03

P1 Runtime Control API body decode boundary에서 모든 decode failure를 generic `Invalid request body`로 축소하던
경로를 닫았다. `RuntimeControlHTTPQueryError.invalidBody`는 이제 원인 message를 운반하며, `decodedBody`는
대상 request type과 decode failure details를 bad request body에 보존한다. TestKit session command validation도
nil/blank `sessionID`를 generic invalid body가 아니라 `sessionID is required`로 보고한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 253 | `invalidBody(message:)` 적용, decoded body failure detail test, TestKit sessionID validation message test 갱신. |
| Active after pass | 115 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 252, 259, 261, 268, 273-285, 300 | API body decode/validation failures keep actionable cause text instead of collapsing into a generic invalid-body label. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
```

## Pass 38 - Runtime Log Helper Message Request Semantics

분류일: 2026-06-03

P1 Runtime log request boundary에서 missing `helperMessage` query/body field를 empty string으로 보정하던 경로를
닫았다. Swift 내부 `RuntimeLogTextRequest.helperMessage`는 optional로 absence와 explicit empty string을
구분하고, query parser는 field absence를 `nil`, explicit `helperMessage=`를 `""`로 보존한다. Host log reader로
넘길 때는 legacy host-client signature 연결부에서만 `nil`을 empty string으로 변환하며, append-only helper
message log가 log source의 SoT라는 문서를 유지한다. OpenAPI/PWA POST body contract는 Pass 57에서 required
nullable field로 강화되어 body field absence를 더 이상 valid request로 받지 않는다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 252 | `RuntimeLogTextRequest.helperMessage: String?`, query parser nil preservation test, OpenAPI/PWA schema/generated parity. |
| Active after pass | 114 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 226, 230, 234, 238-239, 259, 261, 268, 273-285, 300 | Missing helperMessage is no longer indistinguishable from an explicit empty helperMessage request. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 39 - PWA Host Log Request Helper Message Absence

분류일: 2026-06-03

P1 PWA host log hook에서 `helperMessage: ""`를 항상 전송하던 경로를 닫았다. Pass 57 이후 Runtime log POST
body는 required nullable `helperMessage`를 보존하므로, `useHostLogs`는 legacy helper message 값이 없을 때
`helperMessage: null`을 전송한다. Console client는 explicit empty helperMessage request를 여전히 표현할 수
있지만, hook-level host log read는 absence나 empty string을 만들지 않는다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 226 | `useHostLogs` required-null helperMessage request, hook expectation update, focused hook test and PWA check 통과. |
| Active after pass | 113 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 230, 234, 238-239, 259, 261, 268, 273-285, 300 | PWA host log reads no longer manufacture an explicit empty helperMessage request. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/console/hooks.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 40 - TestKit Session Command Target Ownership

분류일: 2026-06-03

P1 TestKit session command target에서 PWA가 blank session id를 `null`로 보정하거나 hook mutation이
`sessionID: null` request를 만들 수 있던 경로를 닫았다. Swift TestKit command DTO도 `sessionID`를 non-optional
contract로 바꿔 null/missing body는 decode failure, blank string은 validation failure가 된다. PWA request schema,
request builder, hook mutation type, OpenAPI/generated type을 같은 non-null session target contract로 맞췄다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 230, 234 | TestKit session command DTO non-optional, PWA schema/builder/hook non-null target, blank sessionID validation test, OpenAPI/generated parity. |
| Active after pass | 111 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 238-239, 259, 261, 268, 273-285, 300 | PWA no longer delegates missing/blank session target resolution to the API or TestKit manager. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/console/requestBuilders.test.ts src/console/hooks.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 41 - PWA Console Request Boundary Semantics

분류일: 2026-06-03

P1 PWA console client에서 body 없는 command와 JSON body command, missing query와 explicit undefined query가
섞이던 경로를 닫았다. Console client는 JSON body가 있을 때만 `Content-Type`과 request body를 붙이고,
runtime event query에 explicit `undefined` field가 들어오면 validation error로 멈춘다. Observability page는
event type filter가 선택된 경우에만 query field를 만든다. `repairProxy`는 Swift API contract에 맞춰
`proxyPort`를 필수 인자로 고정했다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 238-239 | PWA console client request builder, runtime event query validation, observability query construction, focused console client tests. |
| Active after pass | 109 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 259, 261, 268, 273-285, 300 | PWA request boundary no longer silently drops explicit undefined query values or marks bodyless commands as JSON-body requests. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/infrastructure/console-api/runtimeControlApiClient.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 42 - Runtime VitalDB Observation Snapshot Ownership

분류일: 2026-06-03

P1 observability reader contract에서 optional observation projection이 snapshot state/readError의 owner처럼 동작하던
방향을 닫았다. `RuntimeControlClient`와 `RuntimeObservabilityReading`은 snapshot을 primary read contract로 두고,
`loadVitalDBObservation()`은 snapshot에서 observation만 꺼내는 compatibility projection이 된다.
`RuntimeVitalDBObservationSnapshot.fromOptional()`도 loaded observation에 동반된 `readError`를 보존한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 259 | Snapshot-first protocol defaults, loaded snapshot readError preservation contract test, focused Swift contract/reader tests. |
| Active after pass | 108 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 268, 273-285, 300 | Snapshot state/readError are no longer reconstructed from optional observation at the client/reader default boundary. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeObservabilityReaderTests
```

## Pass 43 - VitalDB Bed Assignment Status Contract

분류일: 2026-06-03

P1 relationship projection에서 bed assignment status raw string을 `.unknown`으로 보정하던 경로를 닫았다.
HostInfrastructure의 `VitalDBBedAssignmentRecord.status`를 `VitalDBBedAssignmentStatus` enum으로 바꾸고,
SQLite read는 `requiredEnum`으로 invalid status를 projection read failure로 보고한다. Runtime adapter는 typed
status를 명시 switch로 `RuntimeVitalBedStatus`에 매핑한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 268 | Typed HostInfrastructure assignment status, no raw-value fallback in adapter, invalid status repository test. |
| Active after pass | 107 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 273-285, 300 | Invalid assignment status no longer becomes `.unknown`; it is a typed projection read failure. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter SQLiteVitalDBObservationRepositoryTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeObservabilityReaderTests
```

## Pass 44 - Composite Runtime Event Secondary Append Failure

분류일: 2026-06-03

P1 runtime event repository에서 primary JSONL append 성공 후 secondary SQLite append 실패가 로그만 남고 성공처럼
반환되던 경로를 닫았다. `CompositeRuntimeEventRepository`는 primary event를 보존한 뒤 secondary append 실패를
`CompositeRuntimeEventRepositoryError.secondaryAppendFailed`로 반환한다. best-effort 호출자는 기존처럼 로그로
관측하지만, non-best-effort 호출자는 secondary observability 손실을 명시 실패로 받는다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 300 | Typed secondary append failure, primary JSONL preservation assertion, focused composite repository test. |
| Active after pass | 106 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 273-285 | Secondary observability append loss no longer returns success. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter SQLiteRuntimeObservabilityStoreTests/testCompositeRepositoryReportsSecondaryAppendFailureWithoutLosingPrimaryEvent
```

## Pass 45 - Vital Recorder Summary Optional Metrics

분류일: 2026-06-03

P1 `RuntimeVitalRecorderSummary`가 missing audit proxy status나 missing VitalDB observation을 observed zero로
내보내던 경로를 닫았다. Summary count fields와 `activeConnections`는 provider가 값을 보고했을 때만
존재한다. Swift display policy와 PWA formatter는 missing count를 `Not reported`로 표시하고, reported zero는
그대로 `0`으로 표시한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 274-275 | Optional summary metrics, Swift contract/display tests, PWA active connection formatter test, API docs update. |
| Active after pass | 104 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 273, 276-285 | Summary read model no longer emits observed-zero counts for unavailable providers. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeStatusDisplayPolicyTests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/status/StatusPage.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 46 - Vital Recorder Activity History Source

분류일: 2026-06-03

P1 recorder activity history에서 activity projection read failure와 construction path의 projection 미제공이
같은 `unavailable` source로 보이던 경로를 닫았다. `RuntimeVitalRecorderActivityHistorySource.notProvided`를
추가해, activity projection을 읽다가 실패한 `unavailable`과 caller가 projection을 제공하지 않은 `notProvided`를
분리했다. OpenAPI/PWA schema와 API 문서를 함께 갱신했다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 273 | `notProvided` source, Swift contract tests, RuntimeObservabilityReader tests, PWA API type generation check. |
| Active after pass | 103 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 276-285 | Activity history source now distinguishes not-provided projection from projection read failure. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeObservabilityReaderTests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 47 - Vital Recorder Timestamp Ordering

분류일: 2026-06-03

P1 recorder/bed read model에서 latest ordering과 duplicate preference가 timestamp string lexical order에 의존하던
경로를 닫았다. `compareReportedTimestamp`는 ISO8601 instant를 먼저 파싱해 비교하고, timezone offset이 다른
timestamp도 실제 시각 기준으로 정렬한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 278 | ISO8601 instant comparison, timezone offset ordering contract test. |
| Active after pass | 102 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 276-277, 279-285 | Recorder ordering no longer depends on lexical timestamp strings. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
```

## Pass 48 - Vital Recorder Last-Seen Ownership

분류일: 2026-06-03

P1 recorder/bed read model builder가 provider-owned `lastSeenAt` 부재를 observation timestamp로 보정하던 경로를
닫았다. Observation count는 유지하지만, recorder/bed `firstSeenAt`과 `lastSeenAt`은 provider가 explicit
lastSeenAt을 보고했을 때만 갱신한다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 2 | 279, 283 | Builder no longer promotes observation timestamp into lastSeenAt, contract test for missing recorder/bed lastSeenAt. |
| Active after pass | 100 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 276-277, 280-282, 284-285 | Read model no longer infers lastSeenAt from observation observedAt. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
```

## Pass 49 - Vital Recorder Latest Field Ownership

분류일: 2026-06-03

P1 recorder history builder가 latest observation에 존재하는 recorder의 missing IP/version/bed fields를 과거
observation 값으로 보정하던 경로를 닫았다. Recorder가 latest observation에 존재하면 latest payload가 해당 field의
owner이며, nil field는 nil로 유지한다. Historical value는 recorder가 latest observation에 없을 때만 historical
record context로 남긴다.

| Result | Count | Original IDs | Evidence |
|---|---:|---|---|
| Fixed | 1 | 280 | Latest-present recorder no longer inherits previous IP/version/bed/lastSeen fields, contract test. |
| Active after pass | 99 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 276-277, 281-285 | Latest recorder field ownership no longer falls back to previous observation fields. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
```

## Pass 50 - Vital Recorder/Bed Status and Activity Presence

P1 VitalDB recorder/bed history read model에서 current observation 결측과 observed offline state가 같은
`offline` 값으로 합쳐지던 경로를 닫았다. `RuntimeVitalRecorderStatus`와 `RuntimeVitalBedStatus`에
`notObserved`를 추가해서 history에는 있으나 latest VitalDB observation에는 없는 recorder/bed를 명시한다.
Bed는 current observation에 존재하면서 `online == false`인 경우만 `offline`으로 유지하고, stale owner field가
없는 상태에서 `stale`을 만들지 않는다.

Recorder activity projection도 missing과 observed-empty가 구분되도록 `activityTimeline`을 optional contract로
바꿨다. Swift/PWA presentation은 nil timeline을 `not reported`로 표시하고, 빈 배열만 “최근 data activity 없음”으로
표시한다. API OpenAPI/schema/generated TypeScript enum과 status formatter도 같은 vocabulary로 맞췄다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 4 | 281, 282, 284, 285 | Latest absence no longer maps to offline, missing activity timeline no longer becomes empty, bed offline no longer maps to stale without owner field. |
| Inventory correction | 1 | 283 | Already fixed in Pass 48; removed from the active range that still listed `281-285`. |
| Active after pass | 94 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261, 276-277 | Recorder/bed current state vocabulary now preserves not-observed/offline/stale distinctions. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 51 - Vital Recorder/Bed Duplicate Observation Visibility

P1 VitalDB recorder/bed history read model에서 같은 recorder vrcode 또는 bedID를 가진 source observation이
`Dictionary(... uniquingKeysWith:)`에서 collapse될 때 duplicate state가 사라지는 문제를 닫았다.
Aggregate identity는 그대로 하나로 유지하되, `RuntimeVitalRecorderRecord.duplicateObservationCount`와
`RuntimeVitalBedRecord.duplicateObservationCount`를 추가해 collapse된 extra source record 수를 계약으로 운반한다.

Swift/PWA details 화면은 duplicate count를 표시한다. OpenAPI/schema/generated TypeScript에도 같은 field를
추가했다. `0`은 duplicate source observation이 없었다는 관측값이며, missing/read failure의 대체값이 아니다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 2 | 276, 277 | Duplicate recorder/bed source observations no longer disappear when the aggregate record chooses the preferred current value. |
| Active after pass | 92 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221, 261 | Duplicate source state is now explicit in read model and UI details. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlAPITests
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 52 - Loaded VitalDB Observation With Read Issue

P1 VitalDB observation snapshot이 `state=loaded`와 `readError`를 동시에 운반하는 partial failure를 PWA가
loaded success로 축소하던 경로를 닫았다. `selectVitalDBObservationRead()`는 loaded observation에도
snapshot `readError`를 유지하고, Observability pipeline은 `Ready with issues`/`Unhealthy with issues`로
표시한다. Recorder anomaly section은 snapshot read issue와 observation `readIssues`를 함께 표시하고,
read issue가 있는 loaded observation을 “No recorder anomalies”로 축소하지 않는다.

Swift ObservabilityPanel은 이미 `vitalDBObservationSnapshot.readError`를 별도 read issue로 표시하고 있었으므로
이번 pass는 PWA presentation parity를 맞춘다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 261 | Loaded snapshot readError is now visible in PWA Observability instead of being dropped. |
| Active after pass | 91 | 1-5, 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | No active observability/read-model P1 item remains. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 53 - PWA Status Page Missing Provider Fields

P1 PWA StatusPage가 missing endpoint/resource fields를 app defaults, `0`, or `Unknown`으로 보정하던 경로를
닫았다. VitalServer URL은 `RuntimeStatus.proxyPort`가 있을 때만 링크로 표시하고, Remote Console URL은
`RuntimeSettings.runtimeControlPort`가 있을 때만 표시한다. 더 이상 settings proxy port나 app default port로
runtime endpoint state를 추정하지 않는다.

Data directory stats는 file count와 size를 분리해 `File count not reported`/`Size not reported`를 표시한다.
Resource usage는 missing, invalid, incomplete를 `Not reported`, `Invalid resource usage`,
`Incomplete resource usage`로 구분한다. Active recorder connections는 Pass 45에서 이미 `Not reported`로
수정됐으므로 active inventory에서 함께 제거했다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 4 | 1, 2, 3, 5 | StatusPage no longer infers endpoint URLs, directory file count, or resource usage state. |
| Inventory correction | 1 | 4 | Active recorder connections missing-as-zero was already fixed in Pass 45. |
| Active after pass | 86 | 8-10, 14-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Status page endpoint/resource fallbacks removed. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 54 - PWA TestKit Status Presence and Typed Requests

P1 PWA TestKitPage가 missing TestKit status를 empty beds/sessions, disabled=false, `Unknown`, or local-only
start readiness로 보정하던 경로를 닫았다. `beds`와 `sessions`는 status payload가 있을 때만 arrays로 소비하고,
payload가 없으면 `TestKit bed/session state is not reported`로 표시한다. Enabled/status/service/url/target/count도
`Not reported`를 사용해 disabled/empty와 구분한다.

TestKit command buttons are enabled only when the service reports `enabled === true` and `state === "running"`;
selected bed count remains only an input completeness check. Scenario/signal request는 typed option guards를 통해
state를 갱신하므로 start request에서 UI string cast가 필요 없어졌다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 6 | 8, 9, 10, 14, 15, 16 | TestKit page no longer converts missing status to empty state, and request options are typed before mutation. |
| Active after pass | 80 | 17-27, 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | TestKit status presence and request option boundaries are explicit. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 55 - PWA Recorder Activity Read Issues

P1 PWA recorder activity formatter가 missing/invalid activity input을 empty chart 또는 zero bucket으로 축소하던
경로를 닫았다. 기존 chart-friendly `buildRecorderActivityBuckets()`는 유지하되 내부적으로
`readRecorderActivityBuckets()`를 사용하고, UI는 returned `issues`를 `Recorder activity data is incomplete`로
표시한다.

Activity timeline missing, invalid point timestamp, missing point counts, invalid embedded bucket timestamp,
missing/invalid bucket seconds, missing bucket counts를 issue로 운반한다. Embedded bucket source가 제공된 경우
그 source가 invalid하더라도 parent point count로 fallback하지 않는다. Filled time gaps remain chart artifacts but now
carry `synthetic: true`, so synthetic zero buckets are not indistinguishable from observed zero buckets in code.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 11 | 17-27 | Recorder activity formatter now returns explicit read issues and synthetic bucket flags instead of silent empty/zero fallback. |
| Active after pass | 69 | 31-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Activity formatter fallback bucket closed. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/recorders/recorderActivity.test.ts src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 56 - PWA Capabilities Contract Requiredness

P1 PWA capabilities schema가 optional boolean 중심이라 provider omission을 valid capability payload로 받아들이던
경로를 닫았다. `runtimeCapabilitiesSchema`는 Runtime Control API가 소유한 모든 capability boolean을 required로
검증한다. Partial `{ canUseTestTools: true }` 같은 payload는 schema 단계에서 reject되며, tests/mocks는 full
capability contract를 사용한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 31 | Capability provider omission no longer passes PWA schema validation. |
| Active after pass | 68 | 32-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Capabilities contract requiredness is explicit. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts src/console/hooks.test.tsx src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 57 - PWA Runtime Settings Contract Requiredness

P1 PWA settings schema가 optional field 중심이라 partial `{ proxyPort: 18080 }` 같은 payload를 valid
RuntimeSettings처럼 받아들이던 경로를 닫았다. `RuntimeSettings`는 Swift settings read model과 같은 full
settings snapshot contract로 고정하고, OpenAPI/generated TypeScript/zod schema/test fixtures가 모두 같은
required fields를 사용한다. Settings apply request도 partial patch가 아니라 current settings snapshot에서
수정한 full settings document를 전송한다.

SettingsPage는 settings가 아직 load되지 않았을 때 apply 가능한 domain-like draft를 만들지 않고, apply는 loaded
settings가 있을 때만 진행된다. `runtimeSettingsPolicy`는 complete settings input만 검증하며, missing 값 보정을
검증 정책 안에서 수행하지 않는다.

추가로 이미 closed 상태인 #226의 POST body parity를 정정했다. `/host/logs/read` body는 Swift/PWA request
shape 테스트와 OpenAPI에서 `helperMessage`를 required nullable field로 표현하며, PWA hook은 legacy helper
message 값이 없을 때 `helperMessage: null`을 명시적으로 보낸다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 32 | RuntimeSettings omission no longer passes PWA schema/type validation or settings apply request construction. |
| Contract correction | 1 | 226 | Already-closed host log request now uses required nullable `helperMessage` in POST body parity. |
| Active after pass | 67 | 33-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | RuntimeSettings and host log POST body requiredness are explicit. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas.test.ts src/domain/runtime-control/settings/runtimeSettingsPolicy.test.ts src/pages/settings/runtimeSettingsForm.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts src/console/hooks.test.tsx src/pages/pages.test.tsx src/app/App.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/settings/runtimeSettingsForm.test.ts src/domain/runtime-control/settings/runtimeSettingsPolicy.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 58 - PWA Container Observation Contract Requiredness

P1 PWA container observation schema가 `auditProxyHTTP`, `containerLogsPresent`, `composeServices` 같은 Swift
non-optional owner fields를 optional로 받아들이던 경로를 닫았다. Container observation 자체는 status/overview에서
optional일 수 있지만, 한 번 provider가 observation object를 제공하면 core owner fields는 required로 검증한다.

OpenAPI/PWA generated type/zod schema는 `RuntimeContainerObservation` core fields, nested
`RuntimeAuditProxyStatusDocument`, `RuntimeRecorderConnectionObservation`, `RuntimeContainerServiceObservation`
required fields를 Swift contract에 맞췄다. `auditProxyStatusReadError`, `runtimeStateFileMetadataError`,
`composeServicesReadError`도 API schema에 추가해 read/decode/metadata failure를 passthrough가 아니라 명시
contract로 보존한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 33 | Partial container observation no longer passes PWA schema/generated contract validation. |
| Active after pass | 66 | 34-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Container observation object requiredness now matches Swift/OpenAPI/PWA parity. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/pages/pages.test.tsx src/app/App.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 59 - PWA VitalDB Recorder Activity Observation Requiredness

P1 PWA `VitalDBRecorderActivityObservation` schema가 `windowSeconds`, `messageCount`, `byteCount`,
`roomCount`, `messagesPerSecond`, `bytesPerSecond`를 optional로 받아들이던 경로를 닫았다. Recorder activity가
제공된 경우 provider-owned counts/rates는 missing일 수 없으며, 실제 0과 provider omission은 schema 단계에서
분리된다.

Swift/observer contract에 존재하는 `buckets`도 OpenAPI/PWA schema/generated type에 추가했다. Bucket item은
`bucketStartedAt`, `bucketSeconds`, `messageCount`, `byteCount`, `roomCount`를 required로 검증한다. first/last
timestamp는 Swift optional field이므로 optional nullable로 유지한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 34 | VitalDB recorder activity observation counts/rates/buckets no longer pass as omitted provider fields. |
| Active after pass | 65 | 35-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Recorder activity observation counts/rates/buckets now preserve missing vs zero semantics. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 60 - PWA VitalDB Recorder Identity Status Requiredness

P1 PWA `VitalDBRecorderObservation` schema가 raw recorder identity/status fields를 optional로 받아들이던 경로를
닫았다. Swift `VitalDBRecorderObservation`에서 provider-owned non-optional field인 `vrcode`, `online`, `stale`는
OpenAPI/PWA generated type/zod schema에서 required로 검증한다. Recorder metadata/timestamps/activity는 기존
contract대로 optional nullable 또는 optional object로 유지한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 35 | VitalDB recorder identity/status omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 64 | 36-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Recorder identity/status missing is a contract failure, not UI-renderable data. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 61 - PWA VitalDB Bed Identity Status Requiredness

P1 PWA `VitalDBBedObservation` schema가 raw bed identity/status fields를 optional로 받아들이던 경로를 닫았다.
Swift `VitalDBBedObservation`에서 provider-owned non-optional field인 `bedID`, `online`은 OpenAPI/PWA generated
type/zod schema에서 required로 검증한다. Bed name, linked recorder, timestamps, patient connection state는 기존
contract대로 optional nullable로 유지한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 36 | VitalDB bed identity/status omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 63 | 37-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Bed identity/status missing is a contract failure, not UI-renderable data. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 62 - PWA VitalDB Anomaly Requiredness

P1 PWA `VitalDBAnomalyObservation` schema가 anomaly identity, kind, severity, timestamp, subject, message를
optional로 받아들이던 경로를 닫았다. Swift `VitalDBAnomalyObservation`의 모든 fields는 provider-owned
non-optional diagnostic contract이므로 OpenAPI/PWA generated type/zod schema에서 required로 검증한다.

이 변경으로 anomaly가 존재하지만 원인 메시지나 대상이 누락된 payload는 UI에서 불완전한 anomaly로 표시되지 않고
contract boundary에서 실패한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 37 | VitalDB anomaly identity/cause fields omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 62 | 38-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Anomaly payloads must carry complete diagnostic identity and cause fields. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 63 - PWA Runtime Overview Section Requiredness

P1 PWA `RuntimeControlOverview` schema가 top-level `status`, `settings`, `release`, `install`,
`vitalDBObservationSnapshot`, `vitalRecorder` sections를 optional로 받아들이던 경로를 닫았다. Swift
`RuntimeControlOverview`에서 이 sections는 non-optional owner contract이므로 OpenAPI/PWA generated type/zod
schema에서 required로 검증한다.

`vitalDBObservation`은 Swift optional field이므로 optional/null을 유지한다. 대신 snapshot object 자체와
`vitalDBObservationSnapshot.state`는 required로 강화해 latest observation read state가 빈 object로 통과하지
않게 했다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 38 | Runtime overview no longer accepts missing required read-model sections as a valid PWA payload. |
| Active after pass | 61 | 39-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Overview section absence is now a contract failure rather than an empty UI section. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 64 - PWA Runtime Event Identity Requiredness

P1 PWA `RuntimeEventDocument` schema가 event identity/diagnostic owner fields를 optional로 받아들이던 경로를
닫았다. Swift `RuntimeEventDocument`의 non-optional fields인 `schemaVersion`, `id`, `source`, `eventType`,
`timestamp`, `product`, `message`, `runtimeVersion`, `failureReasons`는 OpenAPI/PWA generated type/zod schema에서
required로 검증한다.

Original finding의 `status` sub-claim은 Swift owner contract상 optional `RuntimeStatusLevel?`이므로 required로
바꾸지 않았다. `status` absence는 valid event state이며, UI가 필요하면 missing status를 explicit display state로
처리해야 한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 39 | Runtime event identity/diagnostic field omission no longer passes PWA schema/generated contract validation; status remains owner-optional. |
| Active after pass | 60 | 40-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Runtime event identity is now required at the PWA contract boundary. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 65 - PWA Runtime Event History Events Requiredness

P1 PWA `RuntimeEventHistory` schema가 `events` field를 optional로 받아들이던 경로를 닫았다. Swift
`RuntimeEventHistory.events`는 non-optional owner field이므로 OpenAPI/PWA generated type/zod schema에서
required로 검증한다. `events: []`는 valid empty history이고, field absence는 contract failure다.

Original finding의 `matchingCount` sub-claim은 Swift owner contract상 optional pagination metadata이므로 required로
바꾸지 않았다. Consumers must preserve missing matchingCount separately from a reported zero count.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 40 | Runtime event history events omission no longer passes PWA schema/generated contract validation; matchingCount remains owner-optional. |
| Active after pass | 59 | 41-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Event history absence and observed empty history are distinct at the contract boundary. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 66 - PWA Runtime Vital Recorder Activity Point Requiredness

P1 PWA `RuntimeVitalRecorderActivityPoint` and `RuntimeVitalRecorderActivityBucket` schema가 chart/count fields를
optional로 받아들이던 경로를 닫았다. Swift read model decode가 이미 `observedAt`, `windowSeconds`,
`messageCount`, `byteCount`, `roomCount`, `messagesPerSecond`, `bytesPerSecond`, `buckets`와 bucket fields를
complete payload로 요구하므로 OpenAPI/PWA generated type/zod schema도 같은 required contract로 맞췄다.

Recorder activity tests now use full valid activity fixtures. Malformed input tests still exercise boundary-invalid
payloads, but they use explicit `malformedActivityPoints` casting so invalid data is not presented as normal typed
domain input.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 41 | Runtime Vital Recorder activity point/bucket counts no longer pass as omitted provider fields. |
| Active after pass | 58 | 42-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Activity chart input now preserves missing vs zero at the contract boundary. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/domain/runtime-control/recorders/recorderActivity.test.ts src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 67 - PWA Vital Recorder Record Requiredness

P1 PWA `RuntimeVitalRecorderRecord` schema가 recorder read-model identity/status/count fields를 optional로
받아들이던 경로를 닫았다. Swift `RuntimeVitalRecorderRecord`에서 non-optional인 `vrcode`, `status`,
`observationCount`, `duplicateObservationCount`, `currentAnomalyCount`, `presentInLatestObservation`은
OpenAPI/PWA generated type/zod schema에서 required로 검증한다.

`activityTimeline`은 Swift optional field이고 nil이 “activity not reported” state로 사용되므로 optional로 유지한다.
Valid page/test fixtures now include complete recorder count fields and full activity point payloads.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 42 | Vital Recorder read-model identity/status/count omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 57 | 43-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Recorder read-model identity/status/counts are now explicit provider contract fields. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/domain/runtime-control/recorders/recorderActivity.test.ts src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 68 - PWA Vital Bed Record Requiredness

P1 PWA `RuntimeVitalBedRecord` schema가 bed read-model identity/status/count fields를 optional로 받아들이던
경로를 닫았다. Swift `RuntimeVitalBedRecord`에서 non-optional인 `bedID`, `status`, `observationCount`,
`duplicateObservationCount`, `currentAnomalyCount`는 OpenAPI/PWA generated type/zod schema에서 required로
검증한다.

Bed name, linked recorder, patient connection, timestamps, latest anomaly severity는 Swift optional contract이므로
optional nullable로 유지한다. Valid page/test fixtures now include duplicate bed observation counts.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 43 | Vital Bed read-model identity/status/count omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 56 | 44-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Bed read-model identity/status/counts are now explicit provider contract fields. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 69 - PWA Vital Recorder Activity History Requiredness

P1 PWA `RuntimeVitalRecorderHistory` schema가 recorder/beds list와 activity history provenance를 optional로
받아들이던 경로를 닫았다. Swift `RuntimeVitalRecorderHistory`는 `recorders`, `beds`,
`activityHistory`를 non-optional로 제공하고, no data는 missing이 아니라 explicit empty array로 표현한다.

`RuntimeVitalRecorderActivityHistory.source`와 `bucketCount`도 required로 맞췄다. Projection이 아직 제공되지
않거나 사용할 수 없는 경우에도 provider는 `notProvided`/`unavailable` source와 bucket count를 명시해야 하며,
PWA는 `{}` activity metadata를 정상 payload로 받아들이지 않는다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 44 | Vital Recorder history list omission and activity provenance omission no longer pass PWA schema/generated contract validation. |
| Active after pass | 55 | 45-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Observed empty recorder/bed lists are now distinct from missing provider fields, and activity projection source/count are explicit. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 70 - PWA Host Log Text Response Requiredness

P1 PWA `RuntimeLogTextResponse` schema가 successful log read response에서 `text` 누락을 허용하던 경로를 닫았다.
Swift `RuntimeLogTextResponse.text`는 non-optional이며, read failure는 successful empty response가 아니라 API error
또는 typed contract error로 남아야 한다.

OpenAPI/PWA generated type/zod schema 모두 `text`를 required로 맞췄고, console client는 `{}` log response를
`RuntimeControlContractError`로 거부한다. Empty log는 `text: ""`로만 표현된다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 45 | Host log read success response omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 54 | 46-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Missing log text is now distinct from observed empty log text. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 71 - PWA Host Log Export Result Requiredness

P1 PWA `RuntimeLogExportResult` schema가 successful log export response에서 `destination` 누락을 허용하던
경로를 닫았다. Swift `RuntimeLogExportResult.destination`은 non-optional이고 exporter는 archive move 완료 후
destination URL을 반환한다.

OpenAPI/PWA generated type/zod schema 모두 `destination`을 required로 맞췄고, console client는 `{}` export
result를 `RuntimeControlContractError`로 거부한다. Export failure는 successful response omission이 아니라
API/command failure로 남아야 한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 46 | Host log export success response omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 53 | 47-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Missing export destination is now distinct from completed export destination. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 72 - PWA Update Bundle Summary Response Requiredness

P1 PWA `RuntimeUpdateBundleSummaryResponse` schema가 successful update bundle summary response에서 `summary`
누락을 허용하던 경로를 닫았다. Swift `RuntimeUpdateBundleSummaryResponse.summary`는 non-optional이며, bundle
summary를 만들 수 없는 경우는 successful empty response가 아니라 API/contract failure로 남아야 한다.

OpenAPI/PWA generated type/zod schema 모두 `summary`를 required로 맞췄고, console client는 `{}` summary
response를 `RuntimeControlContractError`로 거부한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 47 | Update bundle summary success response omission no longer passes PWA schema/generated contract validation. |
| Active after pass | 52 | 48-49, 51-55, 57, 60, 123-132, 134-135, 139, 142-144, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Missing update summary is now distinct from completed summary text. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 73 - PWA Beds Page Missing Data and Required Field Display

P1 PWA `BedsPage`가 missing query data를 `[]`로 필터링해 empty bed list처럼 렌더링하던 경로를 닫았다.
성공 상태인데 `data`가 없으면 `Bed history response is incomplete` contract error로 표시하고, provider가 보낸
observed empty array만 `No beds have been observed.`로 표시한다.

Pass 68 이후 `RuntimeVitalBedRecord.bedID`, `observationCount`, `duplicateObservationCount`,
`currentAnomalyCount`는 schema/generated type에서 required이므로 UI의 `hasBedID` filter, missing identity
`Unknown` fallback, count `?? 0` fallback을 제거했다. Invalid/missing `lastSeenAt` sort value도 `0` timestamp로
만들지 않고 valid timestamp 뒤로 보낸다.

Provider-owned bed summary/assignment summary를 UI가 재계산하는 #134/#135는 `/vitaldb/beds` API가 아직 array
response만 제공하는 구조적 문제이므로 active로 유지한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 6 | 131, 132, 139, 142, 143, 144 | Missing bed query data no longer renders as empty list; bed identity/count required fields are displayed without state-creating fallback; invalid/missing sort timestamps no longer become epoch-like `0`. |
| Active after pass | 47 | 48-49, 51-55, 57, 60, 123-130, 134-135, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Bed provider summary ownership remains active in #134/#135. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
```

## Pass 74 - TestKit Session Store and Cleanup Failure Visibility

P1 TestKit persisted session decode/defaulting과 cleanup/persistence failure hiding 경로를 닫았다.
`session_snapshot_from_record`와 nested recorder decode는 persisted JSON에서 필수 session/request/recorder fields가
누락되면 `normal`, `0`, `false`, `[]`로 보정하지 않고 decode failure로 남긴다.

`JsonFileVirtualRecorderSessionStore`는 corrupt JSON, non-object payload, invalid `sessions` shape, malformed record를
empty session list로 바꾸지 않는다. Manager startup의 stored session load failure도 `{}`로 축소하지 않고 throw한다.

Session save/delete persistence failure는 event-only warning이 아니라 command failure로 전파된다. VitalServer recorder
or bed cleanup을 요청했는데 recorder management provider가 없으면 success-like empty cleanup result가 아니라
`cleanup_errors`/`cleanupErrors`에 명시된다.

Pass 73의 active count를 재검산해 46에서 47로 바로잡았다. #123-#130 8개를 닫은 뒤 active finding은 39개다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 8 | 123-130 | Persisted TestKit session missing/default semantics, missing cleanup provider, and session store save/delete failures no longer collapse into normal/zero/empty/event-only success paths. |
| Active after pass | 39 | 48-49, 51-55, 57, 60, 134-135, 146-147, 149-150, 153, 155-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Remaining active items are PWA recorder/beds summary/UI ownership, Swift presentation policy, and later PWA/API display-state gaps. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH uv run pytest packages/vitalserver-testkit/tests/unit/adapters/test_session_store.py packages/vitalserver-testkit/tests/unit/application/test_virtual_recorder_sessions.py
PATH=/opt/homebrew/bin:$PATH uv run ruff check packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/application/recorder_session packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/adapters/outbound/session_store.py packages/vitalserver-testkit/tests/unit/adapters/test_session_store.py packages/vitalserver-testkit/tests/unit/application/test_virtual_recorder_sessions.py
```

## Pass 75 - Vital Recorder History Provider Summary Contract

P1 PWA Beds/Recorders page가 list rows에서 summary/current/anomaly counts를 재계산하던 경로를 닫았다.
`RuntimeVitalRecorderHistory.summary`를 Swift provider-owned contract로 추가했고, OpenAPI/PWA generated type/zod
schema에서 required로 검증한다.

Summary는 `knownRecorders`, `currentRecorders`, `onlineRecorders`, `staleRecorders`, `recorderAnomalies`,
`knownBeds`, `onlineBeds`, `staleBeds`, `bedAssignments`, `bedAnomalies`를 제공한다. Current recorder summary는
`presentInLatestObservation == true` record만 기준으로 계산하고, bed assignment/anomaly summary는 `notObserved`
bed를 제외한 current bed 기준으로 계산한다.

PWA `BedsPage`는 `/vitaldb/recorders` history response의 `beds + summary`를 소비한다. `RecordersPage`는
missing history data를 empty list로 렌더링하지 않고 contract error로 표시하며, `presentInLatestObservation === true`
만 current row로 취급한다. Required `vrcode`/count fields는 UI에서 filter 또는 `?? 0` fallback 없이 표시한다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 10 | 134, 135, 146, 147, 149, 150, 153, 155, 157, 158 | Provider-owned history summary replaces UI summary reconstruction; missing recorder data no longer renders as empty list; required recorder identity/count fields are displayed without state-creating fallback; invalid/missing sort timestamps no longer become epoch-like `0`. |
| Active after pass | 29 | 48-49, 51-55, 57, 60, 156, 159-160, 164, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Remaining PWA recorder items are activity/readError and display-filter semantics; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts src/infrastructure/console-api/runtimeControlApiClient.test.ts src/console/hooks.test.tsx src/pages/pages.test.tsx
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeControlContractsTests
```

## Pass 76 - PWA Recorder Activity History Read Error Boundary

P1 PWA `RecordersPage`가 `activityHistory.readError`를 표시하면서도 chart를 계속 렌더링하던 경로를 닫았다.
`RuntimeVitalRecorderHistory.activityHistory`는 Pass 69 이후 required contract이므로 `RecorderDetails` prop도 required로
바꿨다.

Activity projection read failure가 있으면 `Recorder activity history is incomplete` error state만 표시하고
`RecorderActivityChart`를 렌더링하지 않는다. Missing activity and no reported activity remain distinct through
`activityTimeline === undefined` and provider-owned `activityHistory.source/readError`.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 2 | 156, 164 | Activity read failure no longer coexists with chart rendering, and activityHistory is no longer an optional presentation prop. |
| Active after pass | 27 | 48-49, 51-55, 57, 60, 159-160, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Remaining PWA items are display-filter semantics and other page/API state gaps; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
```

## Pass 77 - PWA Recorder Search and History Toggle Reclassification

P1 PWA `RecordersPage`의 #159/#160을 업데이트된 AGENTS.md 기준으로 재검토해 `not-an-issue`로 닫았다.

#159 search filter는 provider state를 만들거나 read failure를 success-like value로 바꾸지 않는다. `vrcode`는 required
contract이고, `lastIP`, `version`, `bedID`, `bedName`은 optional/not-reported display fields다. 검색은 사용자가
입력한 query와 현재 표시 가능한 labels를 비교하는 presentation filter로 남는다.

#160 current/history toggle도 provider state를 만들지 않는다. Pass 75 이후 current set은 UI가 추론하지 않고
provider-owned `presentInLatestObservation === true` contract를 표시 필터로만 사용한다. Toggle은 same read model의
view mode이며 domain/read model state transition이 아니다.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Not an issue | 2 | 159, 160 | Search and history toggle are presentation filters over explicit provider fields, not state-creating fallback. |
| Active after pass | 25 | 48-49, 51-55, 57, 60, 188, 190-192, 194-198, 200, 210, 212-215, 221 | Remaining PWA items are logs/update/backups/settings/action state gaps; Swift presentation items remain P2. |

검증:

```sh
git diff --check
```

## Pass 78 - PWA Logs Page Missing Text Boundary

P1 PWA `LogsPage`가 missing log query data를 `""`로 보정해 empty log와 같은 UI path로 렌더링하던 경로를 닫았다.
`RuntimeLogTextResponse.text`는 Pass 70 이후 required contract이므로, loaded query 상태에서 `data`가 없으면
`Log response is incomplete` contract error를 표시한다.

실제 empty log는 provider가 `text: ""`를 반환한 경우에만 `No log lines are available for this source.`로 표시한다.
Missing response data and successful empty log text are now separate states.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 2 | 188, 190 | Missing log query data no longer becomes empty log text; explicit empty text remains a successful empty log display. |
| Active after pass | 23 | 48-49, 51-55, 57, 60, 191-192, 194-198, 200, 210, 212-215, 221 | Remaining PWA items are capability/settings/update/HTTP display-state gaps; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
```

## Pass 79 - PWA Log Export Capability State Boundary

P1 PWA `LogsPage`가 `capabilities.data?.canExportLogs !== true` 하나로 capability loading, read failure,
missing response data, unsupported capability를 모두 disabled state로 축소하던 경로를 닫았다.

Log export capability is now rendered from explicit query/contract states:
loading shows `Loading export capability...`, read failure shows `Failed to read export capability`, missing capability data
shows `Export capability response is incomplete`, and provider-owned `canExportLogs: false` shows an unsupported-capability
message. The export controls remain disabled, but the disabled state is now backed by an explicit reason instead of optional
field fallback.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 191 | Capability read failure, missing capability data, and unsupported export capability no longer share the same disabled-only UI state. |
| Active after pass | 22 | 48-49, 51-55, 57, 60, 192, 194-198, 200, 210, 212-215, 221 | Remaining PWA items are settings/update/HTTP display-state gaps; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx
```

## Pass 80 - PWA Settings Draft Load Boundary

P1 PWA `SettingsPage`가 settings load 전에 `emptyRuntimeSettingsDraft`를 form state로 만들고 `""`/`false` values를
runtime settings처럼 렌더링하던 경로를 닫았다.

The settings draft is now nullable and is created only after provider-owned settings data exists. Missing settings data renders
`Settings response is incomplete` and no settings form controls. Read failure still renders `Failed to read settings`, and the
Apply control remains disabled without manufacturing draft values.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 192 | Settings load absence no longer creates empty domain-like form state. |
| Active after pass | 21 | 48-49, 51-55, 57, 60, 194-198, 200, 210, 212-215, 221 | Remaining PWA items are settings field fallback, update, and HTTP display-state gaps; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx src/pages/settings/runtimeSettingsForm.test.ts
```

## Pass 81 - PWA Settings Field and Control State Boundary

P1 PWA `SettingsPage`의 remaining settings field/control fallback 묶음을 닫았다.

`minimumDiskGiB`와 settings minimum disk text now use the required provider field directly instead of optional `?? 1`
fallback. Disabling custom advertised URL no longer mutates the draft `publicHost`/`publicPort`; the request mapper still
derives the disabled advertised URL command state explicitly when applying. Default advertised URL preview no longer falls back
to port `80` when the draft proxy port is missing/invalid; it renders `Proxy port is not available.` instead.

`startOnBoot` enablement is now computed by pure `startOnBootControlState` from explicit `startOnBootConfigurable`,
capability read state, and `canControlRuntimeServices`, and the disabled UI shows the concrete reason.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 5 | 194-198 | Settings form fields and start-on-boot control state no longer create fallback values or anonymous disabled state. |
| Active after pass | 16 | 48-49, 51-55, 57, 60, 200, 210, 212-215, 221 | Remaining PWA items are runtime-control redirect/update/HTTP display-state gaps; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx src/pages/settings/runtimeSettingsForm.test.ts
```

## Pass 82 - PWA Settings Apply Redirect Boundary

P1 PWA `SettingsPage`가 settings apply 성공 후 fixed 1초 timeout으로 새 Runtime Control port에 자동 이동하던 경로를
닫았다.

Apply completion is no longer treated as new server readiness. When the Remote Console port changes, the page records the target
URL and renders an explicit `Remote Console` link with text telling the operator to open it after the Runtime Control API is
available on the new port. No timer-based redirect or readiness guess remains in the Settings page.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 200 | Settings apply success and new-port API readiness are now separate states. |
| Active after pass | 15 | 48-49, 51-55, 57, 60, 210, 212-215, 221 | Remaining PWA items are HTTP formatting/display-state gaps and one command-result display fallback; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/pages.test.tsx src/pages/settings/runtimeSettingsForm.test.ts
```

## Pass 83 - PWA HTTP Status and URL Ownership Boundary

P1 PWA `formatting/http.ts`가 HTTP probe strings를 regex로 success/failure state로 해석하고, host/port가 없는 Runtime URL을
browser location 또는 local default로 추정하던 경로를 닫았다.

`formatHTTPStatus` now formats explicit provider text only and returns `Not reported` for missing text. It no longer converts
`HTTP 200` to `Reachable` or `failed` to `Unreachable`. Advanced service health no longer marks HTTP probe rows healthy from
string parsing; it displays probe text with neutral/missing tone unless a provider-owned boolean exists.

Runtime URL construction now requires explicit `{ host, port }`. Status shows a VitalServer link only when `settings.publicHost`
and `settings.publicPort` are both available, and Remote Console shows a port label rather than inventing a host. Settings
previews also avoid browser-host/default-port URL synthesis.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 5 | 210, 212-215 | PWA no longer derives reachability or URL host/port from raw strings, current browser origin, or app defaults. |
| Active after pass | 10 | 48-49, 51-55, 57, 60, 221 | Remaining PWA item is Vital Recorder unavailable-reason display; Swift presentation items remain P2. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/domain/runtime-control/formatting/formatting.test.ts src/pages/pages.test.tsx src/pages/status/StatusPage.test.ts src/pages/settings/runtimeSettingsForm.test.ts
```

## Pass 84 - PWA Vital Recorder Unavailable Metric Reason

P1 PWA `formatting/vitalRecorder.ts`가 non-`vitalDBObservation` source를 모든 observation metric에서 generic
`Not reported`로 표시하던 경로를 닫았다.

Observation metrics now keep source-level reason visible: missing summary source renders `Vital Recorder source not reported`,
and provider-owned `source: "unavailable"` renders `VitalDB observation unavailable`. Reported audit-proxy active connection
counts remain displayable independently.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 1 | 221 | Vital Recorder observation metrics no longer lose unavailable-source reason at the metric formatter boundary. |
| Active after pass | 9 | 48-49, 51-55, 57, 60 | No active PWA P1 item remains; remaining findings are Swift presentation P2 display-policy items. |

검증:

```sh
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm run check
PATH=/opt/homebrew/bin:$PATH /opt/homebrew/bin/npm test -- --run src/pages/status/StatusPage.test.ts src/pages/pages.test.tsx
```

## Pass 85 - Swift Presentation Display Ownership Boundary

P2 Swift presentation leftovers were closed across `RuntimeStatusPanel`, `RuntimeRecordersPanel`, `RuntimeBedsPanel`, and
`RuntimeRecorderActivityChartDataBuilder`.

Status no longer creates remote client host from local hostname/`localhost`; service links are shown only when `publicHost` is
explicit. Resource usage with missing percent no longer renders a 0% progress bar. Recorder/Bed optional metadata now uses
field-specific not-reported labels instead of generic `Unknown`.

Recorder activity latest sample, latest bucket, total packets, selected-period availability, and read failure handling now come
from `RuntimeRecorderActivityChartDataBuilder.display(...)`; the View renders explicit display states instead of deriving them
from array order and local reductions. Bed details no longer join against current recorder records to infer linked recorder
status/IP; those values stay not reported until a provider-owned bed relationship contract supplies them.

| Result | Count | IDs | Notes |
|---|---:|---|---|
| Fixed | 9 | 48-49, 51-55, 57, 60 | Swift presentation no longer creates host, resource, recorder metadata, activity summary, or bed-linked-recorder state from local fallback/join logic. |
| Active after pass | 0 | - | TS39 active finding queue is closed for the current AGENTS.md audit snapshot. |

검증:

```sh
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeRecorderActivityChartDataBuilderTests
swift test --package-path apps/vitalserver-macos-runtime --filter RuntimeViewModelCapabilityTests
git diff --check
```

## Priority Buckets

1. P0: destructive/recovery/update decision에 영향을 주는 항목
   - Closed in passes 23-24; no active P0 item remains.
2. P1: observability/read model에서 실패를 빈 값으로 만드는 항목
   - Closed in passes 42-52; no active P1 read-model item remains.
3. P1: TestKit persistence/provider fallback이 command result failure를 숨기는 항목
   - Closed in pass 74; no active TestKit P1 item remains.
4. P1: PWA contract/schema와 page state가 provider failure를 숨기는 항목
   - Closed in passes 68-84; no active PWA P1 item remains.
5. P2: Swift presentation/display policy가 read model이나 action state를 재구성하는 항목
   - Closed in pass 85; no active Swift P2 item remains.

## Triage Direction

1. Close P0 destructive decision risk first.
   - Recovery/restart decisions
   - Runtime health/readiness
   - Update, rollback, install, uninstall
   - Disk/data preservation blockers
2. Close P1 observability and contract loss by vertical slice.
   - Runtime event read semantics
   - VitalDB observation, recorder, bed, anomaly read semantics
   - SQLite/JSONL/Redis/file read failure propagation
   - Runtime Control API and PWA schema parity
3. Fix UI only after upstream state is explicit.
   - PWA and Swift UI must render explicit read result states.
   - UI must not synthesize domain state, action state, or recovery decisions.
4. Remove or document P2/P3 display behavior.
   - `Unknown`, `not reported`, `-`, empty labels, and disabled controls can remain only when backed by explicit state.
   - Display-only fallback must be named as display fallback and kept out of contracts/read models.

## Fix Principles

- Replace `T?`, `[]`, `0`, and empty string fallback with typed read results where the value crosses a layer boundary.
- Let provider contracts represent:
  - available value
  - missing provider state
  - stale provider state
  - permission/read failure
  - decode/contract failure
  - unsupported feature
  - observed zero/empty value
- Keep UI as formatter only. It may choose labels, but it must not create runtime state.
- Recovery planner must consume explicit lifecycle/health contracts, not infer state from probes alone.
- If a fallback is retained for display only, name it as display fallback and keep it out of domain/read models.
- Avoid compatibility branches for unreleased behavior unless a migration is explicitly defined.

## Prevention Checklist

- New runtime contracts must include tests for missing, invalid, failed, and zero/empty states separately.
- Schema tests must fail when required provider-owned state is omitted.
- UI tests must verify that read failures are visible and not rendered as empty/zero states.
- Recovery planner tests must assert that missing explicit state does not trigger destructive action.
- Observability adapters must surface read/decode/persistence issues through result types.

## Next Steps

- No active finding remains in the current TS39 audit queue.
- If AGENTS.md changes again or new TS39 findings are discovered, append them as a new revalidation pass instead of editing
  historical pass results.
- Add new findings only when a new root cause or P0/P1 risk is found.
