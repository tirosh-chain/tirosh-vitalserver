# Runtime Status

Runtime Status는 Helper app에서 운영자가 보는 상태값의 의미를 설명합니다.

상태값은 장애 원인을 확정하는 판정서가 아닙니다. 어느 화면을 먼저 확인해야 하는지 알려주는
점검 정보입니다. 시간 순서와 원인 추적은 [Observability Events](observability-events.md)에서
확인합니다.

## 1. 상태를 어떻게 읽나

Helper app은 상태를 추측하지 않습니다. 상태 소스를 읽지 못하면 정상이나 빈 값으로 바꾸지 않고
별도 오류로 표시합니다.

### 1-1. 먼저 볼 화면

| 화면 | 역할 |
|---|---|
| Status | 전체 health와 주요 연결 상태를 요약 |
| Recorders | VRecorder activity와 bed 연결 상태를 표시 |
| Beds | bed별 activity와 recorder 관계를 표시 |
| Advanced | VM, service, operation, failure reason을 표시 |
| Observability | 상태 변화와 anomaly를 시간 순서로 표시 |
| Logs | 상세 log와 export 자료를 확인 |

Status는 시작점입니다. 세부 원인은 Recorders, Beds, Advanced, Observability, Logs를 함께 봅니다.

### 1-2. 섞으면 안 되는 상태

| 구분 | 의미 |
|---|---|
| `missing` | 필요한 상태나 문서가 없음 |
| `failed` | 읽기, 권한, 연결, 해석 과정이 실패함 |
| `stale` | 상태는 있지만 최신 상태로 보기 어려움 |
| `empty` | 정상적으로 읽었고 결과가 비어 있음 |
| `invalid` | 값이나 문서 모양이 약속과 맞지 않음 |

예를 들어 recorder 목록을 읽지 못한 것은 `empty`가 아닙니다. 상태는 임의로 판단하지 않습니다.

## 2. 전체 health

Overall health는 Helper runtime을 현재 사용할 수 있는지 요약합니다.

| 표시 | 의미 | 다음 확인 |
|---|---|---|
| Healthy | runtime 실행 파일, VM, guest HTTP, host proxy가 사용 가능 | Recorders/Beds에서 실제 관측 상태 확인 |
| Needs attention | 실행은 가능하지만 일부 상태나 관측에 주의가 필요 | Advanced, Observability 확인 |
| Critical | runtime 실행 또는 사용에 직접 장애가 있음 | Advanced failure reasons, Logs 확인 |
| Installing | 최초 설치 패키지가 runtime 파일, VM disk, service, 설정을 배치/등록하는 중 | installer 화면, install log 확인 |
| Initializing | 설치/provision 산출물이 준비됐고 runtime service, guest, HTTP endpoint가 사용 가능 상태로 올라오는 중 | 4~5분 정도 완료 대기, 오래 지속되면 Status failure reasons와 Logs 확인 |
| Updating | update bundle 적용, guest activation, rollback 진행 중 | Update progress, Logs 확인 |
| Recovering | watchdog 또는 repair 흐름이 복구 중 | Advanced, Observability 확인 |
| Not installed | Helper runtime이 설치 또는 실행 가능한 상태가 아님 | 설치 또는 Reset Installer 확인 |
| Unknown | 상태를 읽었지만 표시 가능한 판단으로 확정하지 못함 | status document/read issue 확인 |

`Healthy`라도 recorder나 bed가 모두 정상이라는 뜻은 아닙니다. runtime이 사용 가능하다는 요약이고,
실제 관측 상태는 Recorders/Beds 화면에서 확인합니다.

처음 설치할 때는 VM 생성, service 등록, guest 준비, health 확인이 순서대로 진행됩니다. `Installing`은
설치 작업 자체를 뜻하고, `Initializing`은 설치/provision 산출물이 준비된 뒤 runtime service와 guest가
사용 가능 상태로 올라오는 중이라는 뜻입니다. 이 구간에 Advanced의 일부 service나 HTTP endpoint가
아직 준비되지 않아도 해당 active operation 상태를 우선 표시합니다.

## 3. Runtime service

Runtime service 상태는 Advanced 화면에서 봅니다. 이 값은 macOS launchd와 runtime read model에서
온 상태를 표시합니다.

### 3-1. 표시되는 service

| service | 의미 |
|---|---|
| VM service | local VM runtime lifecycle |
| Host proxy service | macOS nginx host proxy |
| Guest log sync service | guest/runtime log 동기화 |
| Sleep prevention service | runtime 운용 중 macOS sleep 방지 |
| Watchdog service | runtime 상태 관측과 복구 판단 |

### 3-2. service 상태값

| 표시 | 의미 |
|---|---|
| Running | launchd가 service를 loaded 상태로 보고함 |
| Stopped | launchd가 service를 loaded 상태로 보고하지 않음 |
| Read failed | service 상태 읽기에 실패함 |
| Permission denied | 권한 문제로 service 상태를 읽지 못함 |
| Installing | 설치 중이라 service 상태보다 operation 상태를 우선 표시 |
| Initializing | 초기 기동 중이라 service 상태보다 operation 상태를 우선 표시 |
| Updating | update 중이라 service 상태보다 operation 상태를 우선 표시 |
| Unavailable | 표시할 명시 값이 없음 |
| Unknown | 계약에 없는 service 상태가 들어옴 |

service가 `Stopped`라도 항상 장애는 아닙니다. install, initialization, update, repair, stop/start 같은
operation 중인지 함께 확인합니다. 단, `Read failed`와 `Permission denied`는 설치 중에도 별도 실패로 남겨
표시합니다.

## 4. Recorder와 Bed

Recorders/Beds 화면은 recorder observer와 audit proxy에서 만든 관측 결과를 표시합니다.

### 4-1. VRecorder 상태

| 표시 | 의미 |
|---|---|
| Online | 최신 관측 window에서 VRecorder activity가 확인됨 |
| Stale | VRecorder는 알려져 있지만 최근 activity가 오래됨 |
| Offline | VRecorder는 알려져 있으나 현재 online으로 보이지 않음 |
| Not observed | 과거 기록은 있으나 최신 관측 문서에 없음 |
| Unknown | 계약에 없는 recorder 상태가 들어옴 |

Recorders 화면에서는 `VRecorder`, `Status`, `IP`, `Bed`, `Last seen`, `Anomaly`를 함께 봅니다.
`History` 토글을 켜면 최신 관측에 없는 과거 recorder도 볼 수 있습니다.
`Data updated`는 recorder/bed 상태 snapshot이 갱신된 시각이고, `Last seen`은 해당 VRecorder가
마지막으로 보낸 activity 시각입니다. 둘은 다릅니다. Data updated가 오래되면 화면 전체가 stale일 수
있고, Last seen만 오래되면 특정 VRecorder activity 문제일 수 있습니다.
Anomaly는 개수만으로 원인을 확정하지 않고, 가장 최근 anomaly 종류와 메시지를 먼저 확인합니다.

### 4-2. Bed 상태

| 표시 | 의미 |
|---|---|
| Online | 최신 관측 window에서 bed activity가 확인됨 |
| Stale | bed는 알려져 있지만 최근 activity가 오래됨 |
| Offline | bed는 알려져 있으나 현재 online으로 보이지 않음 |
| Not observed | 과거 기록은 있으나 최신 관측 문서에 없음 |
| Unknown | 계약에 없는 bed 상태가 들어옴 |

Beds 화면에서는 `Bed ID`, `Name`, `VRecorder`, `Status`, `Last seen`, `Anomaly`를 함께 봅니다.
상세 영역에는 patient 연결 여부와 first seen/last seen 시간이 표시될 수 있습니다.
Bed 상세의 `VRecorder status`, `VRecorder IP`, `VRecorder last seen`은 bed가 연결된 VRecorder
read model에서 온 명시 상태입니다. Bed 화면은 VRecorder 상태를 임의로 추정하지 않습니다.

### 4-3. Stale과 Offline을 볼 때

`Stale`은 activity가 오래되었다는 뜻이고, `Offline`은 현재 online으로 보이지 않는다는 뜻입니다.
둘 다 바로 장애 원인을 확정하지 않습니다.

먼저 last seen, 연결 bed/VRecorder, Observability anomaly, Logs를 함께 확인합니다.

## 5. 읽기 실패

read failure는 empty success가 아닙니다. 상태 소스를 읽지 못하면 별도 오류로 표시합니다.

| 표시 위치 | 의미 |
|---|---|
| Status document read error | `runtime-status.json`을 읽거나 해석하지 못함 |
| Guest runtime state read error | guest runtime state 계약을 읽거나 해석하지 못함 |
| Data directory stats failed | 설정된 Vital files directory 통계를 읽지 못함 |
| Recorder observation read issue | recorder/bed 관측 snapshot을 읽지 못함 |
| Runtime event read issue | runtime event history를 읽지 못함 |

읽기 실패가 보이면 Logs 화면에서 export zip을 만들고, 필요한 경우 Observability event 기간과 함께
지원 담당자에게 전달합니다.

## 6. Settings 적용 뒤 Critical

Settings 화면에서 설정을 적용한 직후 `Critical` 또는 `Recovering`이 되면, 설정값 validation 실패와
VM restart 실패를 구분합니다.

Settings apply는 변경된 설정에 따라 VM runtime restart requirement를 먼저 판단합니다. CPU,
memory, disk 증가, network mode, bridged interface, Vital files directory 변경은 VM runtime restart가
필요합니다. URL, admin password, start on boot, auto recovery, sleep prevention, Redis backup
retention 변경은 VM runtime restart requirement를 만들지 않습니다.

`Restart VM runtime when required`가 꺼져 있고 VM runtime restart가 필요한 설정을 저장하면 상태는
`configure` operation의 degraded message로 "VM runtime restart required"를 표시할 수 있습니다.
이 경우 설정 저장 실패가 아니라, 현재 실행 중인 VM에는 아직 반영되지 않았다는 뜻입니다.

| 확인 항목 | 의미 |
|---|---|
| `runtime-events.jsonl`의 `configure` 직후 event | 설정 apply가 실제로 runtime restart를 요청했는지 확인 |
| `vm-lifecycle.json` | VM이 `stopping`, `stopped`, `failed` 중 어디에 머물렀는지 확인 |
| `launchd.out.log`의 guest shutdown 로그 | Docker/containerd stop, filesystem remount, poweroff 실패 여부 확인 |
| failure reasons | `host-proxy-http-*`, `audit-proxy-http-failed`, `guest-runtime-state-stale`이 연쇄인지 확인 |

증상이 `configure` 직후 VM stop 요청, guest runtime state stale, host proxy HTTP 실패 순서로 이어지면
Host proxy만 복구할 문제가 아닐 수 있습니다. VM shutdown 과정에서 guest service 또는 filesystem
I/O가 아직 남아 있으면 디스크 오류가 드러나거나 악화될 수 있습니다.

예방 원칙은 Settings restart, Update, Stop/Repair service가 같은 VM shutdown contract를 사용하게
하는 것입니다. Host는 VM 내부 상태를 추측하지 않고, guest가 명시적으로 shutdown 준비와 poweroff
요청 상태를 보고한 뒤 Host service stop/restart를 진행해야 합니다.

Settings apply가 guest shutdown worker를 공유하더라도 update bundle 적용으로 보지 않습니다. Settings
restart progress는 `configure` operation으로 해석하고, update bundle 적용은 `apply-bundle` operation과
Update 탭의 progress로 따로 확인합니다.
