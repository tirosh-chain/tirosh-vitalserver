# Observability Events

이 문서는 macOS Helper app의 Observability 화면에서 보는 event와 관측 정보의 의미를
정리합니다. Event는 최신 상태 snapshot을 대체하지 않습니다. 현재 판단은 Status,
Recorders, Beds, Advanced 화면에서 보고, event는 왜 그런 판단이 나왔는지 추적할 때
사용합니다.

## 1. Observation Pipeline

Observability 화면의 pipeline 영역은 관측 데이터가 들어오고 있는지 확인합니다.

| 항목 | 의미 |
|---|---|
| Recorder observer | Redis/proxy 기반 recorder observation snapshot 생성 상태 |
| Guest log sync service | guest/runtime log 동기화 service 상태 |
| Recorder observation | 최신 recorder observation이 기록된 시각 |
| Known recorders | 관측 read model이 알고 있는 VRecorder 수 |
| Known beds | 관측 read model이 알고 있는 bed 수 |
| Recorder anomalies | 현재 관측된 VRecorder/bed anomaly 수 |
| Runtime events (24h) | 최근 24시간 runtime event 수 |

pipeline 항목이 unavailable이면 상태는 임의로 판단하지 않습니다. read issue와 logs를 함께
확인합니다.

## 2. Runtime Events

Runtime events는 host runtime이 남긴 timeline입니다. Observability 화면에서는 기간, event
종류, 표시 개수를 선택해서 볼 수 있습니다.

| event type | 의미 |
|---|---|
| `status-changed` | runtime status가 변경됨 |
| `progress-updated` | workflow step 또는 progress가 갱신됨 |
| `health-observed` | health snapshot이 관측됨 |
| `runtime-status-observed` | runtime status document가 관측됨 |
| `guest-state-observed` | guest runtime state가 관측됨 |
| `runtime-command-started` | CLI/API command 실행 시작 |
| `runtime-command-completed` | CLI/API command 실행 완료 |
| `runtime-command-failed` | CLI/API command 실행 실패 |
| `recovery-planned` | watchdog 또는 repair 복구가 계획됨 |
| `recovery-triggered` | 복구 command가 실행됨 |
| `recovery-completed` | 복구 흐름이 완료됨 |
| `recovery-suppressed` | 조건 때문에 복구가 억제됨 |
| `recovery-deferred` | 다른 작업 또는 guard 때문에 복구가 지연됨 |
| `watchdog-skipped` | watchdog이 실행 조건 미충족으로 건너뜀 |
| `service-restart-dispatched` | service restart command가 dispatch됨 |
| `domain-error-observed` | domain/runtime policy 오류가 관측됨 |
| `vm-error-observed` | VM 오류가 관측됨 |
| `container-observed` | guest container/service observation이 기록됨 |
| `audit-proxy-observed` | audit proxy observation이 기록됨 |
| `vitaldb-observed` | recorder observer snapshot이 기록됨 |
| `vitaldb-observer-unhealthy` | recorder observer가 unhealthy 상태를 보고함 |
| `vitaldb-anomaly-detected` | recorder/bed anomaly가 감지됨 |
| `observability-store-failed` | event 또는 observability store 기록/읽기 실패 |

Event row는 event type, runtime status, operation, message, detail을 표시합니다. Detail에는
VM state, VM errors, failure reasons, active recorder connections, known recorders, online/stale
recorders, anomaly count가 포함될 수 있습니다.

## 3. Recorder Anomalies

Recorder anomaly는 recorder observation에서 감지한 recorder/bed 관련 이상 징후입니다.

| anomaly kind | 의미 |
|---|---|
| `offline` | 기대되거나 알려진 recorder/bed가 현재 online으로 보이지 않음 |
| `duplicate-ip` | 둘 이상의 recorder가 같은 IP로 관측됨 |
| `backend-unavailable` | recorder backend 관측 자체가 불가능함 |
| `stale-recorder` | recorder activity가 오래됨 |
| `observer-unhealthy` | observer가 unhealthy 상태를 보고함 |

| severity | 의미 |
|---|---|
| `info` | 참고용 event |
| `warning` | 운영 확인이 필요한 상태 |
| `critical` | runtime 사용성 또는 관측 신뢰성에 직접 영향 가능 |

## 4. Relationship Events

Recorders/Beds 상세 화면의 relationship history는 VRecorder와 bed의 관계 변화를 보여줍니다.

| event type | 의미 |
|---|---|
| `handoff` | bed가 다른 VRecorder로 넘어감 |
| `duplicateAssignment` | 동일 bed 또는 recorder 관계가 중복 관측됨 |
| `unlinkedBed` | bed는 관측되지만 recorder 관계가 명확하지 않음 |
| `unlinkedRecorder` | recorder는 관측되지만 bed 관계가 명확하지 않음 |
| `staleLink` | recorder-bed 관계가 오래된 관측에 기반함 |

Relationship event는 최신 상태 판단이 아니라 관계 변화의 이력입니다. 최신 상태는
Recorders/Beds 목록의 status와 last seen을 기준으로 확인합니다.

## 5. How To Use Events

- 최신 상태 판단은 Status/Recorders/Beds/Advanced 화면을 먼저 봅니다.
- Events는 원인 추적, 시간 순서 확인, 복구 흐름 검토에 사용합니다.
- Event가 없다는 사실을 healthy로 해석하지 않습니다.
- read issue, permission failure, decode failure는 별도 실패로 다룹니다.
- 지원 요청 시 `/private/tmp/tirosh-vitalserver-uninstall.log`, runtime logs, exported logs와
  함께 event 기간과 filter 조건을 전달합니다.
