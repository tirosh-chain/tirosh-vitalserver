# 030 Runtime 상태를 Host/UI가 추정하거나 암묵 보정함

> ID: TS-030
> Category: Runtime health / Update
> Owner: macOS runtime
> Status: resolved

## Symptoms

Runtime 상태가 실제 상황과 다르게 보이거나, update 진행 상태가 로그 내용에 따라 뒤늦게 바뀝니다.

대표 증상:

- `vmState`, `vmErrors`가 status document에 없는데 Swift UI가 별도 값으로 표시합니다.
- guest bootstrap 실패가 명시 result 없이 `bootstrap.log` 문구로 분류됩니다.
- update 진행 문구가 `command.log`의 과거 라인을 파싱해 복원됩니다.
- 같은 상태를 Swift UI, Remote Console, event log가 서로 다르게 보여줍니다.
- `RuntimeStatus.isReady`처럼 모델 안의 computed property가 여러 신호를 묶어 상태를 암묵적으로 판단합니다.
- UI가 `nil` 상태를 설치 여부 같은 다른 필드로 보정해 실제로 제공되지 않은 값을 표시합니다.
- `"missing-vm-ip"`, `"bootstrap-pending"`, `"not evaluated"` 같은 문자열이 여러 레이어에 흩어져 상태처럼 사용됩니다.
- progress/event 기록이 현재 status document 없이 임시 health snapshot을 만들어 상태를 채웁니다.
- 내부 enum을 API read model로 변환할 때 알 수 없는 값을 `warning`, `staleLink` 같은 구체 상태로 바꿉니다.
- `runtime-observation.json`이 없거나 stale인데 `vm-ip` 파일로 guest endpoint를 직접 probing해 상태를 채웁니다.
- container health가 보고되지 않았는데 `stable`로 분류됩니다.
- read model이 제공되지 않은 경로/식별자를 빈 문자열로 채워 UI나 API consumer가 값이 있는 것처럼 처리합니다.
- timestamp가 없을 때 `""`로 치환해 정렬하거나 최신 값을 고릅니다.
- status document가 이미 제공해야 하는 `vmIP`, `guestHTTP`, VitalDB observation을 raw `runtime-observation.json`으로 보정합니다.
- 선택되지 않은 backup/update bundle을 빈 문자열 sentinel로 보관해 UI와 command 실행 경로가 같은 값을 다르게 해석합니다.
- backup/Redis backup 목록을 읽지 못했는데 `[]`로 바꿔 “백업 없음”처럼 표시합니다.
- 배포되지 않은 구버전 layout을 추정해 runtime install path에서 legacy log migration을 수행합니다.
- 상태 fallback이 아닌 진단용 추가 로그 소스를 `fallback`으로 이름 붙여 의미를 흐립니다.
- status/progress/event 기록 실패를 `try?`로 무시해 상태 기록 자체의 장애를 숨깁니다.
- runtime config 읽기 실패를 자동복구/수면방지 기본값으로 조용히 대체합니다.
- event 저장은 성공했지만 SQLite observation projection 실패를 `try?`로 무시해 Remote Console 관측 데이터 누락 원인을 숨깁니다.
- Vital Files 폴더 목록을 읽지 못했는데 `[]`로 바꿔 “폴더 없음”처럼 표시합니다.
- Data directory 통계를 읽지 못했는데 `0 files · 0 B` 또는 `Unknown`처럼 표시합니다.
- Settings 값인 host proxy port를 StatusReader가 launchd plist/default 값으로 추정합니다.
- status document를 읽거나 decode하지 못했는데 `nil`로 바꿔 “상태 없음”처럼 표시합니다.
- guest `runtime-observation.json`을 읽거나 decode하지 못했는데 resource usage 미보고처럼 표시합니다.
- settings 파일을 읽거나 decode하지 못했는데 기본 설정값으로 조용히 대체합니다.
- guest 작업 result 파일을 읽거나 decode하지 못했는데 “아직 result 없음”처럼 대기합니다.
- Redis backup result 파일을 읽거나 decode하지 못했는데 “guest worker 대기 중”처럼 대기합니다.
- VM pid 파일을 읽거나 parse하지 못했는데 “프로세스 없음”처럼 종료 성공으로 처리합니다.
- `runtime-version.json`을 읽거나 parse하지 못했는데 “missing-version”과 같은 값으로 표시합니다.
- Host proxy launchd plist에서 port를 읽지 못했는데 default port만 사용하고 config 문제를 숨깁니다.
- Guest runtime-state 파일의 modification date를 읽지 못했는데 stale 상태만 표시하고 invalid 원인을 숨깁니다.
- Runtime events JSONL 파일을 읽거나 decode하지 못했는데 빈 이벤트 목록처럼 보입니다.
- VitalDB recorder observation이 없는데 recorder-ingress connection 목록을 recorder 상태 요약으로 승격합니다.
- VitalDB recorder observation이 없는데 UI가 recorder/bed/anomaly 수를 `0`으로 표시합니다.
- Host proxy listener scan이 실패했는데 listener 없음처럼 처리되어 port 충돌 진단 근거가 사라집니다.
- Backup archive 크기 계산이 실패했는데 `Unknown` 크기로 표시되어 목록 조회 실패와 실제 unknown size가 섞입니다.
- Container log 파일은 존재하지만 size/mtime metadata를 읽지 못했는데 단순 미보고 값처럼 표시됩니다.

## Impact

상태 판단이 분산되면 장애가 발생했을 때 원인이 흐려집니다.

- 상태의 책임 주체가 불명확해집니다.
- HTTP probe, launchd log, command log, guest result가 서로 다른 결론을 만들 수 있습니다.
- 예외 케이스가 생길 때마다 fallback과 방어로직이 늘어납니다.
- update flow가 실제 contract보다 복잡해지고, 실패를 실패로 남기지 못합니다.
- 상태 판단 기준이 모델, health evaluator, UI policy에 나뉘면 어떤 기준이 authoritative한지 알기 어렵습니다.

## Cause

상태를 제공해야 하는 계층이 명시 값을 제공하지 않을 때, Host/UI가 주변 신호로 상태를 추정했습니다.

문제의 패턴:

```text
status document has no vmState/vmErrors
host probes HTTP or reads logs
host reconstructs VM state/errors
UI displays inferred state as if it were reported state
```

로그는 진단 자료이고, 상태 전이 contract가 아닙니다. HTTP probe도 특정 endpoint의 관측값일 뿐 VM 내부 상태 전체를 대표하지 않습니다.

같은 성격의 문제는 로그 파싱뿐 아니라 computed property와 UI fallback에서도 발생합니다. 상태가 아닌 필드를 조합해서 새로운 상태를 만들거나, 값이 없을 때 보기 좋은 값으로 채우면 consumer가 provider의 contract 부재를 숨기게 됩니다.

## Checks

아래 코드가 다시 생기면 이 케이스를 의심합니다.

```sh
rg -n "LegacyBootstrapLogEvaluator|LegacyCommandProgressParser|legacyCommandProgressLine" apps/vitalserver-macos-runtime
rg -n "inferredVMState|inferredVMErrors|vmDiagnosticErrors\\(" apps/vitalserver-macos-runtime
rg -n "\\.isReady|\\\"not evaluated\\\"|not-evaluated" apps/vitalserver-macos-runtime/Sources
rg -n "vmState.*runtimeInstalled|runtimeInstalled.*vmState|missing-vm-ip|bootstrap-pending" apps/vitalserver-macos-runtime/Sources
rg -n "\\.isHealthy|lightweightRuntimeHealthSnapshot|progressHealthSnapshot" apps/vitalserver-macos-runtime/Sources
rg -n "\\?\\? \\.staleLink|\\?\\? \\.warning|\\?\\? \\\"unknown\\\"|\\.unknown\\(\\\"unknown\\\"\\)|\\.unknown\\(\\\"command\\\"\\)" apps/vitalserver-macos-runtime/Sources
rg -n "guestRuntimeState\\(\\)\\?\\.vmIP|readTrimmed\\(.*vmIPFile\\)|statusCode\\(url: \\\"http://\\\\\\(vmIP\\\\\\)" apps/vitalserver-macos-runtime/Sources
rg -n "containerHealthState\\(.*\\).*\\.stable|return \\.stable" apps/vitalserver-macos-runtime/Sources/Core/Health
rg -n "\\?\\? \\\"\\\"|lastSeenAt \\?\\? \\\"\\\"" apps/vitalserver-macos-runtime/Sources/RuntimeControl apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp
rg -n "document\\?\\.(vmIP|guestHTTP|redisUIHTTP|swaggerUIHTTP).*\\?\\?|freshestVitalDBObservation|guestState\\?\\.vitalDBObservation" apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter
rg -n "selected.*Path\\.isEmpty|selected.*Path = \\\"\\\"" apps/vitalserver-macos-runtime/Sources/MacRuntimeControlApp
rg -n "try\\?.*contentsOfDirectory|try\\?.*childDirectories|\\?\\? \\[\\]" apps/vitalserver-macos-runtime/Sources
rg -n "migrateLegacy|legacy-.*log|legacyDirectory" apps/vitalserver-macos-runtime/Sources
rg -n "RuntimeLogExportFallback|fallbackLogItems|rotatedFallbackSets|fallbackItems" apps/vitalserver-macos-runtime/Sources apps/vitalserver-macos-runtime/Tests
rg -n "try\\? (writeStatus|writeProgress|recordObservedEvent|writeRuntimeStatus|operations\\.writeStatus)" apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime
rg -n "try\\? VMRuntimeConfig\\.load|autoRecoveryEnabled\\(\\).*return true|preventSystemSleepEnabled\\(\\).*return true" apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime
rg -n "try\\? observabilityStore\\.append" apps/vitalserver-macos-runtime/Sources
rg -n "func vitalFileFolders\\(root: String\\) -> \\[VitalFilesFolder\\]|vitalFileFolders.*return \\[\\]" apps/vitalserver-macos-runtime/Sources
rg -n "dataDirectoryStats|directoryStats\\(" apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter/RuntimeStatusReader.swift
rg -n "loadBaseStatus\\(\\)\\.proxyPort|proxyPort\\(paths\\.proxyLaunchDaemon\\)|RuntimeStatusReader.*proxyLaunchDaemon" apps/vitalserver-macos-runtime/Sources
rg -n "try\\? JSONDecoder\\(\\)\\.decode\\(RuntimeStatusDocument|try\\? Data\\(contentsOf:.*runtimeStatus|statusRepository\\.load\\(\\)" apps/vitalserver-macos-runtime/Sources
rg -n "try\\? JSONDecoder\\(\\)\\.decode\\(GuestRuntimeStateDocument|guestRuntimeStateDocument\\(.*\\) -> GuestRuntimeStateDocument\\?" apps/vitalserver-macos-runtime/Sources
rg -n "try\\? .*RuntimeSettings|VMConfigDocument\\.load\\(|GuestRuntimeConfig\\.load\\(|proxyPort\\(plistPath" apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter
rg -n "load(UpdateActivation|UpdateShutdown|DatastoreRepair).*\\(\\) -> .*Document\\?|try\\? JSONDecoder\\(\\)\\.decode\\(.*ResultDocument" apps/vitalserver-macos-runtime/Sources
rg -n "loadRedisBackupResult|RedisBackupResultDocument|redis backup guest worker" apps/vitalserver-macos-runtime/Sources
rg -n "readPid\\(|try\\? fileStore\\.readData\\(pidFile\\)|pid_t\\(" apps/vitalserver-macos-runtime/Sources
rg -n "readVersionValue|runtime-version\\.json|try\\? JSONSerialization\\.jsonObject" apps/vitalserver-macos-runtime/Sources
rg -n "installedProxyPort\\(|VITALSERVER_PROXY_PORT|defaultProxyPort" apps/vitalserver-macos-runtime/Sources
rg -n "guestRuntimeStateFresh|modificationDate\\(installedPaths\\.runtimeState\\)|guest-runtime-state-stale" apps/vitalserver-macos-runtime/Sources
rg -n "JSONLRuntimeEventRepository|try\\? Data\\(contentsOf:|compactMap.*decode\\(RuntimeEventDocument" apps/vitalserver-macos-runtime/Sources
rg -n "lsof.*LISTEN|hostProxyListenerScanFailed|return \\[\\]" apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift
rg -n "RuntimeBackup.*try\\?|recursiveRegularFileSize.*try\\?|fileSize.*try\\?" apps/vitalserver-macos-runtime/Sources/MacHostRuntimeAdapter
rg -n "containerLogsBytes = try\\?|containerLogsUpdatedAt: fileModifiedAt" apps/vitalserver-macos-runtime/Sources/HostCLI/Runtime/RuntimeHealthChecker.swift
```

상태 관련 read path에서 아래 패턴이 보이면 재검토합니다.

```text
read log -> map text to status
probe HTTP -> synthesize vmState
missing document field -> infer fallback state
computed property -> combine fields into operational readiness
UI fallback -> display unreported state as reported state
string literal -> shared status sentinel without contract owner
missing current status -> create placeholder health snapshot
unknown enum -> map to concrete operational state
nil database field -> store "unknown" as if it were reported
stale/missing guest state -> probe guest by vm-ip file
nil health field -> treat as stable
missing path/id -> expose empty string
missing timestamp -> compare as empty string
status document field -> fallback to raw guest runtime-state
missing selection -> store empty string sentinel
directory read failure -> return [] as if there are no entries
current install -> migrate legacy layout implicitly
diagnostic supplemental source -> named fallback
status/progress/event write failure -> silently ignored
runtime config read failure -> implicit default flag value
event written -> derived observation write failure hidden
folder list read failure -> empty folder list
data directory read failure -> zero or unknown stats
settings value -> read through status/plist fallback
status document read/decode failure -> missing status
guest runtime-state read/decode failure -> missing resource usage
settings read/decode failure -> default settings
guest result read/decode failure -> still waiting
redis backup result read/decode failure -> still waiting
pid file read/parse failure -> process stopped
runtime-version read/parse failure -> missing version
host proxy port read/parse failure -> default proxy port only
guest runtime-state metadata read failure -> stale only
runtime event JSONL read/decode failure -> empty event list only
recorder ingress status decode failure -> curl failure
update bundle manifest read/decode failure -> missing summary
latest backup read failure -> no backups available
log collection read/copy failure -> silent skip
guest log collection read failure -> no guest logs
recorder-ingress recorder connections -> VitalDB recorder summary fallback
missing VitalDB recorder observation -> zero recorder metrics
host proxy listener scan failure -> no proxy port failure reason
backup size read failure -> unknown backup size
container log metadata read failure -> missing container log metadata
```

## Actions

상태 추정 경로를 제거하고 명시 document만 신뢰합니다.

수정된 원칙:

1. `vmState`, `vmErrors`는 runtime status document가 제공한 값만 표시합니다.
2. status document에 값이 없으면 read layer가 새 값을 만들지 않습니다.
3. update progress는 `RuntimeProgressDocument`만 사용합니다.
4. `command.log`, `bootstrap.log`, launchd log는 상태 전이 입력이 아니라 export/diagnostics 자료로만 사용합니다.
5. Guest 내부 상태가 필요하면 guest가 result/status document로 직접 제공합니다.
6. Runtime readiness와 VM health 분류는 각각 `RuntimeReadinessPolicy`, `RuntimeVMHealthPolicy`에서만 수행합니다.
7. 실제 contract 값으로 남아야 하는 sentinel 문자열만 `RuntimeHTTPStatusText`처럼 shared constant로 모읍니다. 단순 placeholder 문자열은 제거합니다.
8. UI는 상태를 새로 만들지 않습니다. UI policy는 제공된 상태를 표시용 text/severity로만 변환합니다.
9. Progress/event 기록은 기존 status document의 명시 필드를 보존합니다. health snapshot placeholder를 만들어 채우지 않습니다.
10. 내부 typed enum을 API read model로 옮길 때는 exhaustive mapping을 사용하고, unknown을 임의의 구체 값으로 바꾸지 않습니다.
11. Legacy Guest HTTP 상태는 guest가 제공한 runtime-state만 사용합니다. Current Guest Control readiness는 typed Guest address provider가 loaded address를 제공할 때만 Guest Control API로 읽고, `runtime-observation.json.vmIP`로 address를 보정하지 않습니다.
12. 보고되지 않은 container health는 `stable`이 아니라 `unreported`로 분류합니다.
13. API/read model에서 미보고 경로와 식별자는 optional로 유지합니다. UI만 표시 단계에서 `Not reported`로 포맷합니다.
14. timestamp 정렬은 explicit comparator를 사용합니다. `nil` timestamp를 빈 문자열로 변환하지 않습니다.
15. Runtime status API는 status document가 제공해야 하는 필드를 raw guest runtime-state로 보정하지 않습니다. raw guest runtime-state는 resource usage처럼 그 문서가 직접 소유한 값에만 사용합니다.
16. UI 선택 상태는 optional로 유지합니다. 선택 없음은 `nil`이며, 표시 단계에서만 사용자 문구로 변환합니다.
17. 목록 조회에서 파일시스템 오류는 throw로 올립니다. 빈 배열은 성공적으로 읽은 결과가 실제로 비어 있을 때만 사용합니다.
18. 배포 전 제품의 구버전 layout 보정은 install path에서 제거합니다. 필요한 마이그레이션은 명시 migration step으로만 추가합니다.
19. 상태 보정이 아닌 보조 진단 입력은 `fallback`이라고 부르지 않습니다. `supplemental source`처럼 역할이 드러나는 이름을 사용합니다.
20. status/progress/event 기록 실패는 작업 실패로 승격하지 않더라도 `BestEffortRecording` 경로로 명시하고 로그에 남깁니다.
21. runtime config flag는 `RuntimeConfigFlagReader`에서만 읽습니다. config read 실패나 필드 누락으로 기본값을 쓰면 로그에 남깁니다.
22. event 저장과 derived observation 저장의 책임을 분리합니다. derived observation 저장 실패는 event 저장을 되돌리지 않지만 로그에 남깁니다.
23. Vital Files 폴더 목록 조회 실패는 throw로 올립니다. 메뉴는 빈 목록과 읽기 실패를 구분해 표시합니다.
24. Data directory 통계 조회 실패는 `dataDirectoryStatsError`로 노출합니다. 성공 통계와 실패 메시지를 같은 값으로 표현하지 않습니다.
25. Host proxy port는 settings read path가 읽습니다. Status read path는 status document 값이 없을 때 caller가 제공한 settings 값을 사용합니다.
26. Status document는 missing과 read/decode failure를 구분합니다. 읽기 실패는 `statusDocumentError`로 노출하고 상태 없음으로 보정하지 않습니다.
27. Guest runtime-state는 missing과 read/decode failure를 구분합니다. 읽기 실패는 `guestRuntimeStateError`로 노출하고 resource usage 미보고와 섞지 않습니다.
28. Settings reader는 missing과 read/decode failure를 구분합니다. 파일이 있는데 읽기 실패하면 `readIssues`로 노출하고, 기본값 사용 사실을 숨기지 않습니다.
29. Guest result reader는 missing과 read/decode failure를 구분합니다. Update activation/shutdown/datastore repair waiter는 result read failure를 즉시 실패로 처리합니다.
30. Redis backup result reader는 missing과 read/decode failure를 구분합니다. Redis backup wait loop는 result read failure를 guest worker 대기 상태로 보지 않습니다.
31. VM pid file reader는 missing과 read/parse failure를 구분합니다. Invalid pid file은 stopped 상태로 추정하지 않고 runtime operation failure로 노출합니다.
32. Runtime version reader는 missing과 read/parse failure를 구분합니다. Invalid version document는 missing version으로 표시하지 않습니다.
33. Host proxy port reader는 configured port와 fallback port를 구분합니다. Fallback을 사용하면 `hostProxyConfigInvalid` failure reason을 health snapshot에 남깁니다.
34. Guest runtime-state freshness reader는 stale과 metadata read failure를 구분합니다. Metadata read failure는 stale과 함께 `guestRuntimeStateInvalid`를 남깁니다.
35. Runtime event JSONL reader는 loaded events와 read/decode issues를 함께 제공합니다. Invalid lines는 valid events와 분리해서 기록합니다.
36. Recorder ingress status probe는 request failure와 invalid response를 구분합니다. Curl 실패는 `failed`, 응답 contract decode 실패는 `invalid-response`로 노출합니다.
37. Update bundle summary는 typed manifest contract를 사용합니다. Missing manifest와 invalid manifest를 같은 메시지로 합치지 않습니다.
38. Latest backup reader는 목록 read failure와 empty backup list를 구분합니다. Rollback preflight는 read failure를 `no backups available`로 바꾸지 않습니다.
39. Log collection은 missing source와 read/copy failure를 구분합니다. Export logs는 collection failure를 숨기지 않고 호출자에게 전달합니다.
40. Guest log collection은 missing guest run directory와 directory read failure를 구분합니다. Health/watchdog의 best-effort collection 실패도 runtime log에 남깁니다.
41. Recorder 상태 요약은 VitalDB observation만 사용합니다. Audit-proxy recorder connection은 상태 fallback이 아니라 `activeConnections` 연결 수로만 노출합니다.
42. VitalDB observation이 없을 때 UI는 recorder/bed/anomaly metric을 `0`으로 표시하지 않습니다. `Not reported`로 표시해 미관측과 실제 0개를 구분합니다.
43. Host proxy listener scan 실패는 `hostProxyListenerScanFailed`로 노출합니다. 빈 stdout/stderr의 `lsof` nonzero만 listener 없음으로 취급합니다.
44. Backup 목록의 크기 계산 실패는 목록 조회 실패로 전파합니다. `Unknown` 크기는 contract가 명시적으로 size를 제공하지 않을 때만 사용합니다.
45. Container log 파일이 존재하는데 size/mtime metadata를 읽지 못하면 `containerLogsMetadataError`로 노출합니다. 파일 미존재와 metadata read failure를 같은 `nil`로 합치지 않습니다.

## Prevention

새 상태를 추가할 때는 먼저 owner를 정합니다.

- Guest 내부 상태: guest가 document/result/event로 제공합니다.
- Host service 상태: host service manager 또는 명시 status writer가 제공합니다.
- UI 표시 상태: 이미 제공된 status를 포맷만 합니다.
- Log: 사람이 원인을 확인하는 자료이며 machine-readable state contract가 아닙니다.

금지 패턴:

- 로그 문자열을 파싱해 상태를 결정
- 상태 document가 비어 있을 때 HTTP probe로 VM lifecycle state를 생성
- 오래된 command log에서 update progress를 복원
- fallback으로 정상 contract 부재를 숨김
- 모델 computed property에 readiness/health 판단을 숨김
- UI가 `nil` 또는 `unknown`을 다른 필드로 보정해 구체 상태처럼 표시
- shared status sentinel 문자열을 여러 파일에 직접 작성
- progress/event 생성을 위해 placeholder health snapshot을 생성
- enum 변환 실패를 구체 상태로 fallback
- 저장소 read path에서 누락된 상태 필드를 `"unknown"`으로 저장/노출
- stale 또는 missing guest state를 `vm-ip` 파일과 HTTP probe로 보정
- 누락된 health 값을 stable/healthy로 분류
- 미보고 경로/식별자를 빈 문자열로 채워 contract 부재를 숨김
- timestamp 정렬/선택에서 `nil`을 `""`로 비교
- status document의 누락 필드를 raw guest runtime-state로 보정
- 선택되지 않은 path를 빈 문자열로 저장
- 디렉터리 읽기 실패를 `try? ... ?? []`로 숨김
- 현재 install workflow에서 legacy layout을 암묵적으로 이동/정리
- 진단 export source를 fallback으로 명명해 상태 fallback과 같은 개념처럼 보이게 함
- status/progress/event 기록 실패를 `try?`로 조용히 무시
- runtime config read 실패를 운영 설정 기본값으로 조용히 대체
- derived observation 저장 실패를 조용히 무시
- 폴더 목록 읽기 실패를 빈 목록으로 표시
- data directory 통계 읽기 실패를 0 또는 unknown으로 표시
- settings 값을 status reader가 plist/default fallback으로 추정
- status document read/decode 실패를 missing status와 같은 값으로 처리
- guest runtime-state read/decode 실패를 missing resource usage와 같은 값으로 처리
- settings 파일 read/decode 실패를 기본 설정값으로 조용히 대체
- guest result read/decode 실패를 missing result와 같은 값으로 처리
- Redis backup result read/decode 실패를 guest worker 대기 상태와 같은 값으로 처리
- pid file read/parse 실패를 missing pid file과 같은 값으로 처리
- runtime-version read/parse 실패를 missing version과 같은 값으로 처리
- host proxy port read/parse 실패를 default port 사용으로만 처리하고 failure reason을 남기지 않음
- guest runtime-state metadata read 실패를 stale과 같은 값으로만 처리
- runtime event JSONL read/decode 실패를 빈 이벤트 목록과 같은 값으로만 처리

## Operational Notes

상태가 비어 있거나 `unknown`이면 그 자체가 유효한 신호입니다. UI가 보기 좋게 채우기 위해 추정하면 장애 분석이 더 어려워집니다.

필요한 상태가 없다면 consumer가 추정하지 말고 provider가 contract를 확장해야 합니다. 이 원칙은 Swift Helper와 Remote Console 모두에 적용합니다.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-026`: PWA가 Runtime Control API unreachable을 표시
- `TS-029`: Update 중 Host가 Guest shutdown 상태를 추정함

## Follow-up

- 2026-05-29: `RuntimeStatusReader`의 `vmState`/`vmErrors` 추정, bootstrap log 기반 실패 분류, command log 기반 progress fallback을 제거했습니다.
- 2026-05-29: `RuntimeStatus.isReady`의 암묵적 readiness 계산을 `RuntimeReadinessPolicy`로 분리하고, VM 상태/오류 분류를 `RuntimeVMHealthPolicy`로 명시했습니다. `missing-vm-ip`, `bootstrap-pending` 상태 문자열도 `RuntimeHTTPStatusText` contract로 모았습니다.
- 2026-05-29: Swift status UI에서 `vmState == nil`을 `runtimeInstalled == false` 기준으로 `not-installed`처럼 표시하던 fallback을 제거했습니다. 설치 상태는 Runtime installation row가 표시하고, VM state row는 제공된 VM state만 표시합니다.
- 2026-05-29: `RuntimeHealthSnapshot.isHealthy` computed property를 제거하고 `RuntimeHealthSnapshotPolicy`로 분리했습니다. `RuntimeHealthSnapshot`의 기본 `vmState`도 제거해 모든 snapshot 생성자가 VM state를 명시하게 했습니다.
- 2026-05-29: progress/status writer에서 `not-evaluated` health snapshot을 생성하던 경로를 제거했습니다. Progress는 기존 status document가 없으면 쓰지 않고, 있으면 해당 document의 명시 상태 필드를 보존합니다.
- 2026-05-29: VitalDB relationship event/severity를 Remote Console read model로 옮길 때 `staleLink`/`warning`으로 fallback하던 로직을 제거하고 exhaustive mapping으로 변경했습니다.
- 2026-05-29: `RuntimeHealthChecker`가 missing/stale `runtime-observation.json` 상태에서 `vm-ip` 파일로 guest readiness를 직접 probing하던 경로를 제거했습니다. Guest HTTP 상태는 runtime-state가 제공한 값만 사용합니다.
- 2026-05-29: container health 미보고 값을 `stable`로 분류하지 않고 `unreported`로 명시했습니다. `RuntimeHealthInput`의 guest runtime-state 기본값도 제거해 호출자가 present/fresh 여부를 직접 넘기게 했습니다.
- 2026-05-30: `RuntimeInstallInfo`의 경로/식별자 빈 문자열 fallback을 optional로 변경했습니다. Swift UI는 표시 단계에서만 `Not reported`로 포맷합니다.
- 2026-05-30: Vital recorder/bed 최신값 선택과 정렬에서 `lastSeenAt ?? ""` 비교를 제거하고 explicit timestamp comparator로 변경했습니다.
- 2026-05-30: `RuntimeStatusReader`가 status document의 `vmIP`, `guestHTTP`, UI HTTP, VitalDB observation을 raw `runtime-observation.json`으로 보정하던 경로를 제거했습니다. Runtime status API는 status document가 보고한 상태만 노출하고, raw guest runtime-state는 resource usage 소스로만 사용합니다.
- 2026-05-30: rollback/delete backup 선택 상태의 빈 문자열 sentinel을 제거하고 optional selection으로 변경했습니다. 선택 없음은 command 실행 전 명시적으로 차단합니다.
- 2026-05-30: backup/Redis backup 목록 조회에서 디렉터리 읽기 실패를 빈 배열로 숨기던 `try? ... ?? []` 패턴을 제거했습니다. 읽기 실패는 API/UI에 오류로 전달하고, 빈 목록은 실제 빈 디렉터리에만 사용합니다.
- 2026-05-30: runtime install directory 준비 단계에서 legacy runtime log migration을 제거했습니다. Install 준비는 현재 layout 디렉터리를 생성하는 역할만 수행합니다.
- 2026-05-30: log export의 `Fallback` 용어를 `SupplementalSource`로 변경했습니다. 이는 상태 보정이 아니라 export archive에 추가 진단 파일을 포함하는 기능입니다.
- 2026-05-30: install/apply/rollback/health/repair 진행 중 status/progress/event 기록 실패를 `try?`로 무시하던 경로를 제거했습니다. 기록은 best-effort로 유지하되 실패 자체는 runtime log에 남깁니다.
- 2026-05-30: 자동복구/수면방지 flag 읽기를 `RuntimeConfigFlagReader`로 모았습니다. runtime config read 실패나 flag 누락으로 기본값을 쓰는 경우 runtime log에 남깁니다.
- 2026-05-30: `RuntimeObservationRecorder`에서 VitalDB observation projection 실패를 조용히 무시하던 `try?`를 제거했습니다. event 기록은 유지하되 projection 실패는 runtime log에 남깁니다.
- 2026-05-30: Vital Files 폴더 목록 조회 실패를 빈 배열로 숨기지 않도록 `vitalFileFolders(root:)`를 throwing 계약으로 변경했습니다. Swift 메뉴는 `No folders`와 `Could not read folders`를 구분합니다.
- 2026-05-30: Data directory 통계 조회 실패를 `dataDirectoryStatsError`로 분리했습니다. Swift와 Remote Console status UI는 통계 성공값과 읽기 실패를 구분해 표시합니다.
- 2026-05-30: Host proxy port 읽기 책임을 StatusReader에서 SettingsReader로 옮겼습니다. StatusReader는 launchd plist를 직접 읽지 않고 status document 또는 전달받은 settings 값을 사용합니다.
- 2026-05-30: runtime status document 읽기 결과를 `missing`, `loaded`, `failed`로 분리했습니다. Decode/read 실패는 `statusDocumentError`로 노출해 status 미생성과 파일 손상을 구분합니다.
- 2026-05-30: guest runtime-state 읽기 결과를 `missing`, `loaded`, `failed`로 분리했습니다. Decode/read 실패는 `guestRuntimeStateError`로 노출해 resource usage 미보고와 파일 손상을 구분합니다.
- 2026-05-30: Settings reader가 `vm-config.json`, guest runtime config, proxy launch daemon, VM disk size 읽기 실패를 `readIssues`로 노출하도록 변경했습니다. 파일 부재와 파일 손상/권한 실패를 분리합니다.
- 2026-05-30: Guest result gateway가 result document 읽기 결과를 `missing`, `loaded`, `failed`로 분리했습니다. Update activation/shutdown/datastore repair wait loop는 decode/read 실패를 더 이상 대기 상태로 보지 않습니다.
- 2026-05-30: Redis backup result reader가 result document 읽기 결과를 `missing`, `loaded`, `failed`로 분리했습니다. Decode/read 실패는 Redis backup operation 실패로 즉시 노출합니다.
- 2026-05-30: VM pid file reader가 pid file 읽기 결과를 `missing`, `loaded`, `failed`로 분리했습니다. Invalid/unreadable pid file은 process stopped로 추정하지 않습니다.
- 2026-05-30: Runtime version reader가 version document 읽기 결과를 `missing`, `loaded`, `failed`로 분리했습니다. Invalid/unreadable version file은 `invalid-version`으로 표시합니다.
- 2026-05-30: Host proxy port reader가 configured port와 fallback port를 분리했습니다. Launchd plist port를 읽지 못하면 default port를 쓰더라도 `hostProxyConfigInvalid`를 health failure reason으로 남깁니다.
- 2026-05-30: Guest runtime-state freshness reader가 stale과 metadata read failure를 분리했습니다. Modification date를 읽지 못하면 `guestRuntimeStateInvalid`를 함께 남깁니다.
- 2026-05-30: Runtime event JSONL reader가 loaded events와 read/decode issues를 분리했습니다. Legacy `all()`은 events만 반환하지만 `allResult()`로 문제 원인을 확인할 수 있습니다.
- 2026-05-30: Recorder ingress status 응답 decode 실패를 curl 실패와 섞지 않고 `invalid-response`로 노출합니다.
- 2026-05-30: Update bundle summary가 `[String: Any]` 임의 파싱 대신 `UpdateBundleManifest` contract를 사용하고, missing/invalid manifest를 구분합니다.
- 2026-05-30: Latest backup 조회가 backup directory read failure를 empty list로 숨기지 않도록 변경했습니다. Status convenience path는 실패를 로그에 남기고, rollback preflight는 오류를 그대로 받습니다.
- 2026-05-30: Runtime log collection이 존재하는 log source의 read/copy/size 실패를 조용히 skip하지 않고 throw하도록 변경했습니다. UI log preview는 실패 메시지를 표시하고, export logs는 실패를 호출자에게 전달합니다.
- 2026-05-30: Guest log collection이 guest run directory read failure를 조용히 skip하지 않고 throw하도록 변경했습니다. Health/watchdog 경로는 실패를 로그로 남긴 뒤 본래 작업을 계속합니다.
- 2026-05-30: Host proxy의 legacy `vm-ip` fallback을 제거했습니다. 당시 proxy upstream은 Guest가 제공하는 `runtime-observation.json`의 `vmIP`만 사용했습니다. `guestHTTP` 필드가 누락된 runtime-state도 `bootstrap-pending`으로 추정하지 않고 `missing-guest-http`와 `guest-runtime-state-invalid`로 노출합니다.
- 2026-07-08: Host proxy는 더 이상 `runtime-observation.json.vmIP`를 address source로 파싱하지 않습니다. 단기 호환 provider는 explicit `vm-ip` bootstrap file을 읽고, `runtime-observation.json.guestHTTP`는 bootstrap readiness evidence로만 사용합니다.
- 2026-05-30: devtools health/status도 legacy `vm-ip` 파일을 읽지 않도록 변경했습니다. 개발 도구도 `runtime-observation.json`의 `vmIP`와 `guestHTTP` 계약을 사용하고 missing/invalid state를 명시 오류로 표시합니다.
- 2026-05-30: Apply bundle 시작 전 log directory 준비와 runtime log rotation 실패를 `try?`로 숨기지 않고 runtime log에 남기도록 변경했습니다.
- 2026-05-30: Apply bundle 중 guest shutdown preparation cleanup 실패를 `try?`로 숨기지 않고 runtime log에 남기도록 변경했습니다.
- 2026-05-30: Update bundle archive materialization 임시 디렉터리 cleanup 실패를 `try?`로 숨기지 않고 runtime log에 남기도록 변경했습니다.
- 2026-05-30: stale VM pid file 제거 실패를 `try?`로 숨기지 않고 process stop/wait 로그에 남기도록 변경했습니다.
- 2026-05-30: Update artifact tar 검증 중 생성한 임시 출력 파일 cleanup 실패를 `try?`로 숨기지 않고 runtime log에 남기도록 변경했습니다.
- 2026-05-30: Swift log preview가 log file read/size/seek 실패를 `No log data`로 숨기지 않고 `Failed to read log file ...`로 표시하도록 변경했습니다.
- 2026-05-30: Host proxy port cleanup에서 `lsof` 실행 실패를 빈 listener 목록으로 숨기지 않고 cleanup 실패로 노출하도록 변경했습니다. listener가 없는 macOS `lsof`의 empty non-zero 결과만 빈 목록으로 처리합니다.
- 2026-05-30: Container log 파일이 존재할 때 size/mtime metadata read 실패를 `containerLogsMetadataError`로 노출합니다. 파일 미존재와 metadata read failure를 같은 미보고 상태로 합치지 않습니다.
- 2026-05-30: 완료 감사 기준을 정했습니다. 남은 `try?`/`unknown` 검색 결과는 file handle close, `Task.sleep`, forward-compatible unknown enum, optional UI formatting처럼 상태를 재구성하지 않는 경로만 허용합니다. Runtime state, update progress, recovery decision, event/read model 경로에서 새 fallback이 보이면 이 문서를 다시 열고 contract owner를 먼저 정합니다.
