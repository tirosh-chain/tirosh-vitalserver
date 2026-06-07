# Runtime Status

이 문서는 운영자가 관측하는 runtime 상태와 이벤트의 의미를 정리합니다. 내부 state
machine, guard, workflow sequencing은 dev 문서의 영역입니다.

## Status Sources

| Source | 위치 또는 인터페이스 | 의미 |
|---|---|---|
| status file | `/Library/Application Support/VitalServerHelper/status/runtime-status.json` | 최신 runtime 상태 snapshot |
| Helper UI/API | Runtime Control 화면과 API | status file과 관측 read model을 사람이 읽기 쉽게 표시 |
| event history | runtime event read model | 상태 변경, 진행률, health, recovery, command 결과 이력 |
| logs | `/Library/Application Support/VitalServerHelper/logs/` | 원인 추적용 실행 로그 |

## Status Levels

| 상태 | 운영 의미 |
|---|---|
| `installing` | 설치 또는 초기 runtime 구성이 진행 중 |
| `updating` | update bundle apply, guest activation, rollback 관련 작업이 진행 중 |
| `recovering` | watchdog 또는 repair 흐름이 복구를 수행 중 |
| `healthy` | 현재 관측 기준에서 runtime이 정상 |
| `degraded` | 일부 기능이나 의존성이 실패했지만 전체 runtime 판단은 critical이 아님 |
| `critical` | runtime 사용에 직접적인 장애가 있거나 복구/조치가 필요 |
| `unknown` | 알 수 없는 상태 값이 들어왔으며 최신 계약과 맞지 않을 수 있음 |

`missing`, `invalid`, `failed`, `stale`, `empty`는 같은 의미가 아닙니다. release
표시에서도 이 값들을 성공이나 기본값으로 합치지 않아야 합니다.

## Operations

`runtime-status.json`의 `operation`은 현재 상태가 어떤 작업 흐름에서 기록되었는지
나타냅니다.

| operation 예 | 의미 |
|---|---|
| `install` | 설치 흐름 |
| `health` 또는 `status` | 상태 확인 또는 health check |
| `watchdog` | watchdog 관측 또는 복구 판단 |
| `apply-bundle` | product update bundle 적용 |
| `activate-guest-update` | guest update activation |
| `rollback` | rollback |
| `repair-datastore`, `repair-vm-disk`, `repair-proxy`, `repair-services` | 명시적 repair 흐름 |
| `start-services`, `stop-services`, `uninstall` | service lifecycle 또는 제거 작업 |

## Progress Events

진행 중 작업은 `progress`로 현재 step과 phase를 남깁니다.

| 필드 | 의미 |
|---|---|
| `phase` | `preparing`, `running`, `waiting`, `recovering`, `completed`, `failed` 등 진행 구간 |
| `step` | 현재 workflow step |
| `stepStatus` | `pending`, `started`, `completed`, `failed`, `skipped` |
| `message` | 사람이 읽는 진행 메시지 |
| `reasonCodes` | 자동 처리나 troubleshooting에 사용할 수 있는 이유 코드 |

## Runtime Events

event history는 상태 snapshot을 대체하지 않습니다. 최신 판단은 status source를 보고,
events는 왜 그렇게 되었는지 추적할 때 사용합니다.

| event type 예 | 의미 |
|---|---|
| `status-changed` | runtime status가 변경됨 |
| `progress-updated` | 진행률 또는 workflow step이 갱신됨 |
| `health-observed` | health snapshot이 관측됨 |
| `runtime-command-started`, `runtime-command-completed`, `runtime-command-failed` | CLI/API command 실행 결과 |
| `recovery-planned`, `recovery-triggered`, `recovery-completed` | watchdog 또는 repair 복구 흐름 |
| `recovery-suppressed`, `recovery-deferred`, `watchdog-skipped` | 복구가 조건 때문에 실행되지 않음 |
| `domain-error-observed`, `vm-error-observed` | domain 또는 VM 오류가 관측됨 |
| `container-observed`, `vitaldb-observed`, `vitaldb-anomaly-detected` | container/VitalDB 계층 관측 이벤트 |

## Interpretation Rules

- `runtime-status.json`은 최신 상태 snapshot입니다.
- event history는 원인 추적과 timeline 확인을 위한 이력입니다.
- stale status를 healthy로 대체하지 않습니다.
- missing file, decode failure, permission failure는 서로 다른 실패입니다.
- UI/API는 상태를 표시할 수 있지만 domain 상태를 새로 만들거나 추론하지 않습니다.
- 내부 전이 규칙과 chaos test matrix는 dev 문서에서 관리합니다.
