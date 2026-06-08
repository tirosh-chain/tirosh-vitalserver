# Status Reference

이 문서는 macOS Helper app에서 운영자가 직접 보는 상태값의 의미를 정리합니다. 상태는
장애 원인을 확정하는 판정서가 아니라, 어느 화면을 먼저 확인해야 하는지 알려주는 점검
정보입니다.

Runtime event history, observation pipeline, recorder anomaly timeline은
[Observability Events](observability-events.md)에서 따로 다룹니다.

## 1. Helper App Status Surfaces

| 화면 | 표시하는 상태 |
|---|---|
| Status | overall health, VitalServer reachability, Runtime Control PWA reachability, data directory, recorder summary |
| Recorders | VRecorder별 online/stale/offline 상태, IP, 연결 bed, 마지막 관측 시각, anomaly count |
| Beds | bed별 online/stale/offline 상태, 연결 VRecorder, patient 연결 여부, observation count |
| Advanced | VM/service 상태, operation, runtime version, failure reasons, service control |

Status 화면은 요약 화면입니다. 세부 원인은 Recorders, Beds, Advanced, Observability, logs를
함께 봅니다.

## 2. Overall Health

| 표시 | 의미 | 다음 확인 |
|---|---|---|
| Healthy | runtime 실행 파일, VM, guest HTTP, host proxy가 현재 기준에서 사용 가능 | Recorders/Beds에서 실제 관측 상태 확인 |
| Needs attention | 실행은 가능하지만 일부 의존성, 관측, 또는 상태 문서가 주의 상태 | Advanced와 Observability 확인 |
| Critical | runtime 실행 또는 사용에 직접 장애가 있음 | Advanced의 failure reasons와 logs 확인 |
| Installing | 설치 또는 초기 runtime 구성이 진행 중 | 완료 대기, 실패 시 install log 확인 |
| Updating | update bundle apply, guest activation, rollback 등 변경 작업 진행 중 | 진행 메시지와 logs 확인 |
| Recovering | watchdog 또는 repair 흐름이 복구 중 | Advanced와 Observability 확인 |
| Not installed | Helper runtime이 설치/실행 가능한 상태가 아님 | 설치 또는 Force Clean Uninstaller 절차 확인 |
| Unknown | 상태 소스를 읽었지만 표시 가능한 판단으로 확정하지 못함 | status document/read error 확인 |

`missing`, `invalid`, `failed`, `stale`, `empty`는 같은 의미가 아닙니다. UI는 이 값들을
성공이나 기본값으로 합치지 않습니다.

## 3. Runtime Services

Advanced 화면의 service health는 macOS launchd와 runtime read model에서 온 상태를 표시합니다.

| 서비스 | 의미 |
|---|---|
| VM service | local VM runtime lifecycle |
| Host proxy service | macOS nginx host proxy |
| Guest log sync service | guest/runtime log 동기화 |
| Sleep prevention service | runtime 운용 중 macOS sleep 방지 |
| Watchdog service | runtime 상태 관측과 복구 판단 |

| 표시 | 의미 |
|---|---|
| Running | launchd가 service를 loaded 상태로 보고함 |
| Stopped | launchd가 service를 loaded 상태로 보고하지 않음 |
| Read failed | service 상태 읽기에 실패함 |
| Permission denied | 권한 문제로 service 상태를 읽지 못함 |
| Unknown | 계약에 없는 service 상태가 들어옴 |
| Updating | update 중이라 service 상태 대신 operation 상태를 우선 표시 |
| Unavailable | 해당 service 상태를 표시할 명시 값이 없음 |

service 상태가 `Stopped`라도 항상 장애를 뜻하지는 않습니다. 현재 operation, overall health,
HTTP reachability를 같이 봅니다.

## 4. VRecorder Status

Recorders 화면은 recorder observer와 audit proxy에서 만든 관측 read model을 표시합니다.

| 표시 | 의미 |
|---|---|
| Online | 최신 관측 window에서 VRecorder activity가 확인됨 |
| Stale | VRecorder가 알려져 있지만 최근 activity가 오래됨 |
| Offline | VRecorder가 알려져 있으나 현재 online으로 보이지 않음 |
| Not observed | 기대 또는 과거 기록은 있으나 현재 관측 문서에 없음 |
| Unknown | 계약에 없는 recorder 상태가 들어옴 |

Recorders 화면의 주요 열은 `VRecorder`, `Status`, `IP`, `Bed`, `Last seen`, `Anomaly`입니다.
`History` 토글을 켜면 최신 관측에 없는 과거 recorder도 볼 수 있습니다.

## 5. Bed Status

Beds 화면은 bed와 VRecorder의 최신 관계를 표시합니다.

| 표시 | 의미 |
|---|---|
| Online | 최신 관측 window에서 bed activity가 확인됨 |
| Stale | bed가 알려져 있지만 최근 activity가 오래됨 |
| Offline | bed가 알려져 있으나 현재 online으로 보이지 않음 |
| Not observed | 기대 또는 과거 기록은 있으나 현재 관측 문서에 없음 |
| Unknown | 계약에 없는 bed 상태가 들어옴 |

Beds 화면의 주요 열은 `Bed ID`, `Name`, `VRecorder`, `Status`, `Last seen`, `Anomaly`입니다.
상세 영역은 patient 연결 여부, first seen, observation count, duplicate observation count를
표시합니다.

## 6. Read Failures

상태는 임의로 판단하지 않습니다. 상태 소스를 읽지 못하면 별도 오류로 표시합니다.

| 표시 위치 | 의미 |
|---|---|
| Status document read error | `runtime-status.json`을 읽거나 해석하지 못함 |
| Guest runtime state read error | guest runtime state 계약을 읽거나 해석하지 못함 |
| Data directory stats failed | 설정된 Vital files directory 통계를 읽지 못함 |
| Recorder observation read issue | recorder/bed 관측 snapshot을 읽지 못함 |
| Runtime event read issue | runtime event history를 읽지 못함 |

read failure는 empty success가 아닙니다. 실패 상태가 보이면 로그 export와 함께 지원 담당자에게
전달합니다.
