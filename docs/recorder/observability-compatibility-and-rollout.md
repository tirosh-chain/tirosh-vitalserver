# Recorder observability 호환성과 배포 순서

## 1. 이 문서가 답하는 질문

Recorder Observer와 Vital Server Helper는 독립적으로 배포됩니다. HTTP path가
같아도 Helper가 특정 document schema를 모르면 요청을 정상 상태로 해석할 수
없습니다. 이 문서는 다음 판단의 기준입니다.

- 어느 Helper가 어느 Recorder contract를 수락하는가
- 0.2.1 Helper와 0.2.6 Recorder 후보를 어떤 순서로 배포하는가
- Helper 화면의 현재 assessment와 incident history를 어떻게 구분하는가
- 배포와 rollback 때 어떤 증거를 확인하는가

초기 데이터 모델의 결정 과정은
[Recorder observability persistence and API implementation plan](observability-persistence-and-api-plan.md),
과거 팀 handoff는
[Recorder observability API and database handoff](observability-recorder-handoff.md)에
남깁니다. 현재 배포 판단은 이 문서와 두 저장소의 contract manifest를
기준으로 합니다.

## 2. 현재 계약

Recorder는 VRCODE별로 다섯 resource를 NDJSON으로 보냅니다.

```text
POST /api/v1/recorders/{vrcode}/observations
POST /api/v1/recorders/{vrcode}/profiles
POST /api/v1/recorders/{vrcode}/boot-events
POST /api/v1/recorders/{vrcode}/diagnostic-events
POST /api/v1/recorders/{vrcode}/kernel-incidents
```

`/api/v1`은 HTTP API version이고 각 줄의 `schemaVersion`은 document contract
version입니다. 두 version은 독립적으로 관리합니다.

| Resource | 기존 buffer에서 허용 | 0.2.6 Recorder 활성 계약 |
|---|---|---|
| observation | v1, v2 | v2 |
| recorder profile | v1 | v1 |
| boot event | v1, v2 | v2 |
| diagnostic event | v1, v2 | v2 |
| kernel incident | v1, v2 | v2 |

Helper 0.2.1에 추가된 Recorder source receipt는 다음과 같습니다.

| Artifact | SHA-256 |
|---|---|
| observation v2 | `d1576c60ba733a38813654b71f10ae9ac0871e88bd91970d8f65f5b1425cc8cf` |
| boot-event v2 | `f60a1fa3170e110383738d5727526cd7fbe51b2aedcef372b3e2456fd168ad3e` |
| source manifest | `16ed54c8752559a911e82b87b19cf2d4f6c28d1974529f0975c1fa9227b2257c` |

Helper가 같은 resource의 v1과 v2를 모두 수락하는 이유는 upgrade 순간에
journal과 Fluent Bit buffer에 과거 v1 문서가 남아 있을 수 있기 때문입니다.
Helper는 v1을 v2로 추측 변환하지 않고 원본 version으로 검증하고 저장합니다.

## 3. 호환성 표

| Helper | Recorder | 결과 |
|---|---|---|
| 0.2.0 이하 | 0.2.5 이하 | 기존 활성 계약 범위에서 동작 |
| 0.2.0 이하 | 0.2.6 후보 | 비호환. observation v2와 boot-event v2가 unsupported contract로 quarantine될 수 있음 |
| 0.2.1 | 0.2.5 이하 | 호환. v1 buffer와 기존 활성 계약을 계속 수락 |
| 0.2.1 | 0.2.6 후보 | 목표 조합. v2 evidence와 incident UI 사용 가능 |

`202 Accepted`는 한 요청의 모든 non-empty line이 accepted, duplicate 또는
quarantined 중 하나로 PostgreSQL에 영속화됐다는 의미입니다. 따라서 HTTP 202만
보고 schema 호환이 성공했다고 판정하지 않습니다. Response의 disposition과
Helper ingress 상태에서 quarantined count 및 failure code를 함께 확인합니다.

## 4. 저장과 조회

수신 문서는 authoritative JSON Schema로 검증한 뒤 PostgreSQL
`recorder_observability` schema의 공통 event store에 JSONB로 보존합니다.
별도의 incident table을 선제적으로 늘리지 않습니다.

- current Detail은 최신 observation, profile과 boot evidence를 typed DTO로
  투영합니다.
- timeline은 최대 24시간, `300|900|3600`초 bucket으로 제한합니다.
- incident history는 최대 30일, page당 최대 100개입니다.
- PWA와 macOS Helper의 기본 Detail 요청은 최근 30일 중 20개 incident를
  표시합니다.
- incident cursor와 정렬 기준은 server `receivedAt`입니다. device time은
  `occurredAt`과 `timeState`로 별도 전달합니다.

incident history에 들어가는 자료는 두 종류입니다.

| Source | 표시되는 incident |
|---|---|
| kernel incident | panic, Oops, watchdog, lockup, unknown |
| boot-event v2의 active assessment signal | boot-loop, repeated-undervoltage, ledger-continuity |

observation v2의 `incidentState`와 `evidenceHealth`는 현재 상태를 설명합니다.
반면 incident history는 과거에 수신된 명시적 event/signal의 목록입니다. 현재
assessment가 `none`이어도 과거 incident history는 남을 수 있고, history가
비어 있어도 현재 evidence health가 `degraded`일 수 있습니다.

## 5. 화면에서 읽는 법

Recorder Detail의 주요 값은 다음처럼 구분합니다.

| 표시 | 의미 |
|---|---|
| Evidence health | Recorder가 ledger, power summary, journal과 pstore를 마지막으로 읽은 bounded 상태 |
| Incident assessment | 현재 observation이 보고한 boot-loop 및 반복 저전압 assessment |
| Active Recorder incidents | 현재 assessment 중 warning 또는 critical인 명시 signal |
| Recent reported incidents | 최근 30일 동안 Helper가 수신한 kernel/boot incident history |
| Boot `nonOrderable` | epoch/ordinal 근거가 없어 boot 순서를 안전하게 비교할 수 없음 |

`boot-loop`은 연속된 unexpected boot boundary 분류이고
`repeated-undervoltage`는 여러 boot에서 저전압 evidence가 반복됐다는
분류입니다. 어느 것도 전원 어댑터, 케이블, 하드웨어 reset, kernel hang 가운데
하나를 단독 원인으로 확정하지 않습니다. Helper는 Recorder가 보낸 evidence와
policy result를 표시하며 UI에서 새로운 root cause를 추측하지 않습니다.

## 6. 배포 절차

### 6-1. Helper를 먼저 올립니다

1. 0.2.1 release manifest와 Recorder Ingress image `0.2.1`을 함께 배포합니다.
2. Guest bootstrap과 Compose readiness를 확인합니다.
3. Recorder Ingress contract manifest가 observation v2와 boot-event v2 digest를
   포함하는지 확인합니다.
4. 기존 Recorder가 보내는 v1 문서가 accepted 또는 duplicate로 계속 처리되는지
   확인합니다.

Helper 0.2.1은 과거 v1을 계속 수락하므로 이 단계는 Recorder를 아직 올리지
않아도 수행할 수 있습니다.

### 6-2. Recorder 한 대를 canary로 올립니다

1. 동일 source commit으로 0.2.6 이상의 새 Recorder package를 발행합니다.
2. 한 장비에 설치하고 package version, Observer, maintenance와 publisher
   상태를 검증합니다.
3. Profile의 활성 contract receipt가 Helper manifest와 같은지 확인합니다.
4. observation v2와 boot-event v2가 quarantine 없이 accepted되는지 확인합니다.
5. Recorder Detail에서 evidence health, incident assessment, boot state와 recent
   incident query가 `unavailable`이 아닌지 확인합니다.

### 6-3. 나머지 장비로 확대합니다

canary의 publisher buffer가 지속 증가하지 않고 Helper quarantine이 증가하지
않으며 current Detail이 갱신될 때에만 순차 배포합니다. 장비별로 package
version, artifact SHA-256, 설치 시각과 검증 결과를 남깁니다.

## 7. Rollback

Helper 0.2.1은 v1과 v2를 함께 수락하므로 Recorder를 이전 version으로 되돌려도
Helper를 먼저 rollback할 필요가 없습니다. 반대로 Helper를 0.2.0 이하로 먼저
되돌리면 아직 buffer에 남은 v2 문서가 quarantine될 수 있습니다.

안전한 rollback 순서는 Recorder 발행을 v1 활성 계약으로 되돌리거나 v2 publisher
유입을 멈춘 뒤 buffer 상태를 확인하고, 마지막에 Helper를 되돌리는 것입니다.
quarantine, cursor와 Recorder buffer를 호환성 문제 해결 전에 삭제하지 않습니다.

## 8. Release 상태

2026-07-24에 `make dist/pkg/dev/verify`로
`VitalServerHelper-0.2.1-dev.pkg`의 contract review, PWA test/build, clean
Ubuntu golden rootfs, Docker Compose readiness와 golden disk runtime boot
smoke를 검증했습니다.

이 artifact는 개발용 `VM_CODESIGN_IDENTITY=-`로 만든 unsigned PKG입니다. 안정
배포본은 release branch, 배포용 signing identity, artifact digest와 실제 설치
acceptance를 별도로 통과해야 합니다. Recorder 0.2.6도 현재 source candidate이므로
version과 artifact를 확정하기 전 현장 배포 대상으로 보지 않습니다.
