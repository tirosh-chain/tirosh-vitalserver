# Observability Events

Observability Events는 “지금 상태가 왜 이렇게 보이는지”를 시간 순서로 확인하는 자료입니다.

최신 상태 판단은 Status, Recorders, Beds, Advanced 화면에서 먼저 봅니다. Event는 최신 상태
snapshot을 대체하지 않습니다. Event는 원인 추적과 지원 요청에 필요한 흐름을 보여줍니다.

## 1. 언제 보나

상태가 바뀌었거나, recorder/bed 관측이 이상하거나, update/repair 흐름을 추적해야 할 때 봅니다.

| 상황 | 확인할 것 |
|---|---|
| 상태가 갑자기 Critical이 됨 | runtime event와 failure reason의 시간 순서 |
| recorder가 stale/offline으로 보임 | recorder anomaly와 마지막 관측 시각 |
| bed와 recorder 관계가 바뀜 | relationship history |
| repair 또는 watchdog이 실행됨 | recovery event와 suppressed/deferred 여부 |
| 상태 화면을 읽지 못함 | read issue와 observability store failure |

Event가 없다는 사실을 healthy로 해석하지 않습니다. Event 저장소를 읽지 못한 것과 실제 event가
없는 것은 다른 의미입니다.

## 2. 관측 pipeline

Pipeline 영역은 관측 데이터가 들어오고 있는지 보여줍니다.

| 항목 | 의미 |
|---|---|
| Recorder observer | service/proxy 기반 recorder observation snapshot 생성 상태 |
| Guest log sync service | guest/runtime log 동기화 service 상태 |
| Recorder observation | 최신 recorder observation이 기록된 시각 |
| Known recorders | 관측 read model이 알고 있는 VRecorder 수 |
| Known beds | 관측 read model이 알고 있는 bed 수 |
| Recorder anomalies | 현재 관측된 VRecorder/bed anomaly 수 |
| Runtime events | 선택한 기간의 runtime event 수 |

pipeline 항목이 unavailable이면 상태를 임의로 판단하지 않습니다. read issue와 Logs를 함께 확인합니다.

## 3. Runtime event

Runtime event는 host runtime이 남긴 timeline입니다. update, recovery, health observation,
runtime command 흐름을 시간 순서로 볼 수 있습니다.

### 3-1. 자주 보는 event

| event type | 의미 |
|---|---|
| `status-changed` | runtime status가 변경됨 |
| `progress-updated` | workflow step 또는 progress가 갱신됨 |
| `health-observed` | health snapshot이 관측됨 |
| `runtime-command-started` | CLI/API command 실행 시작 |
| `runtime-command-completed` | CLI/API command 실행 완료 |
| `runtime-command-failed` | CLI/API command 실행 실패 |
| `recovery-planned` | watchdog 또는 repair 복구가 계획됨 |
| `recovery-triggered` | 복구 command가 실행됨 |
| `recovery-completed` | 복구 흐름이 완료됨 |
| `recovery-suppressed` | 조건 때문에 복구가 억제됨 |
| `recovery-deferred` | 다른 작업 때문에 복구가 지연됨 |
| `watchdog-skipped` | watchdog이 실행 조건 미충족으로 건너뜀 |
| `observability-store-failed` | event 또는 observability store 기록/읽기 실패 |

Update 실패 후 rollback이 실행되면 update failure event와 rollback event가 모두 남아야 합니다. Rollback
health wait가 성공했다고 해서 앞선 update failure event를 지우거나 성공으로 해석하지 않습니다. 같은
시간대에 `prepare-update-shutdown`, `apply-bundle`, `rollback`, `health-observed` event를 함께 봅니다.

### 3-2. 관측 event

아래 event는 runtime 주변 상태가 관측되었음을 나타냅니다.

| event type | 의미 |
|---|---|
| `runtime-status-observed` | runtime status document가 관측됨 |
| `guest-state-observed` | guest runtime state가 관측됨 |
| `container-observed` | guest container/service observation이 기록됨 |
| `audit-proxy-observed` | audit proxy observation이 기록됨 |
| `vitaldb-observed` | recorder observer snapshot이 기록됨 |
| `vitaldb-observer-unhealthy` | recorder observer가 unhealthy 상태를 보고함 |
| `vitaldb-anomaly-detected` | recorder/bed anomaly가 감지됨 |
| `domain-error-observed` | runtime policy 오류가 관측됨 |
| `vm-error-observed` | VM 오류가 관측됨 |
| `service-restart-dispatched` | service restart command가 dispatch됨 |

Event row에는 event type, runtime status, operation, message, detail이 표시됩니다. Detail에는 VM state,
failure reasons, active recorder connections, known recorders, anomaly count가 포함될 수 있습니다.

## 4. Recorder anomaly

Recorder anomaly는 recorder/bed 관측에서 감지한 이상 징후입니다.

| anomaly kind | 의미 |
|---|---|
| `offline` | 기대되거나 알려진 recorder/bed가 현재 online으로 보이지 않음 |
| `duplicate-ip` | 둘 이상의 recorder가 같은 IP로 관측됨 |
| `backend-unavailable` | recorder backend 관측 자체가 불가능함 |
| `stale-recorder` | recorder activity가 오래됨 |
| `observer-unhealthy` | observer가 unhealthy 상태를 보고함 |

### 4-1. Severity

| severity | 의미 |
|---|---|
| `info` | 참고용 event |
| `warning` | 운영 확인이 필요한 상태 |
| `critical` | runtime 사용성 또는 관측 신뢰성에 직접 영향 가능 |

anomaly가 있다고 해서 곧바로 원인이 확정되는 것은 아닙니다. Recorders/Beds 화면의 status,
last seen, relationship history를 함께 봅니다.

## 5. 관계 변화

Relationship history는 VRecorder와 bed의 관계 변화를 보여줍니다.

| event type | 의미 |
|---|---|
| `handoff` | bed가 다른 VRecorder로 넘어감 |
| `duplicateAssignment` | 동일 bed 또는 recorder 관계가 중복 관측됨 |
| `unlinkedBed` | bed는 관측되지만 recorder 관계가 명확하지 않음 |
| `unlinkedRecorder` | recorder는 관측되지만 bed 관계가 명확하지 않음 |
| `staleLink` | recorder-bed 관계가 오래된 관측에 기반함 |

Relationship event는 최신 상태 판단이 아니라 관계 변화의 이력입니다. 최신 상태는 Recorders/Beds
목록의 status와 last seen을 기준으로 확인합니다.

## 6. 지원 요청에 활용하기

지원 요청 시에는 event 내용만 전달하지 말고, 같은 화면을 다시 볼 수 있는 조건을 함께 전달합니다.

| 자료 | 이유 |
|---|---|
| 문제가 발생한 시간대 | event 기간 filter를 맞추기 위해 |
| 선택한 event type/filter | 같은 event 목록을 재현하기 위해 |
| runtime logs 또는 exported logs | event와 실제 service log를 비교하기 위해 |
| installer 또는 uninstaller log | 설치/정리 실패와 runtime 문제를 구분하기 위해 |

read issue, permission failure, decode failure는 별도 실패로 다룹니다.
