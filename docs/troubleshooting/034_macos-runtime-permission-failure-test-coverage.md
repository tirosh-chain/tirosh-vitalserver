# 034 macOS runtime 권한 실패 검증이 부족함

> ID: TS-034  
> Category: Update / Runtime Control PWA / Observability  
> Owner: macOS runtime / packaging  
> Status: active

## Symptoms

현장 설치본이나 update 이후에 파일/폴더 권한 때문에 아래 기능이 실패할 수 있는데, 테스트가 happy path 위주이면 release 전에 감지하기 어렵습니다.

- Settings가 root-owned 설정 파일을 읽지 못해 `readIssues`를 표시합니다.
- Export logs가 root-owned log/config 파일을 수집하지 못합니다.
- Observability가 SQLite/JSONL event store를 읽지 못하거나 실패 원인을 빈 event list로 숨깁니다.
- update/install/rollback 중 `copy`, `move`, `remove`, `chmod`, plist write, backup restore가 권한 문제로 실패합니다.
- 실패 원인이 UI/API/log에 남지 않으면 운영자는 event 미생성, update 손상, Helper 버그를 구분하기 어렵습니다.

정상 상태라면 권한 실패가 발생해도 실패 원인은 `readIssues`, `readError`, command stderr, export manifest, Runtime Control API response, ViewModel message 중 적절한 경계에 보존되어야 합니다.

## Impact

권한 실패 자체는 환경 의존적이지만, update/rollback 경로에서 발생하면 runtime이 partially updated 상태로 남거나 rollback 판단을 어렵게 만들 수 있습니다.

Settings, Observability, Export logs 쪽 권한 실패는 runtime 자체를 즉시 중단시키지 않더라도 운영 진단 능력을 낮춥니다. 특히 event가 실제로 존재하는데 UI가 `0 events`만 보여주면 watchdog/event recorder와 read path 문제를 구분할 수 없습니다.

## Cause

macOS runtime은 여러 권한 경계를 동시에 사용합니다.

- root/service-owned runtime files: `/Library/Application Support/TiroshVitalServer/...`
- user-owned Helper process
- privileged launcher command path
- guest-generated logs/status/projection files
- update bundle staging, artifact replacement, backup/rollback directories

이 경계에서 권한 실패가 발생할 수 있지만, 기존 테스트가 기능별 정상 흐름만 검증하면 아래 문제가 남습니다.

- read failure가 `nil`, `[]`, default value로 사라집니다.
- write failure가 generic failure로 축약되어 어떤 파일이 막혔는지 알 수 없습니다.
- update 중 cleanup/rollback 실패가 progress/status에 남지 않습니다.
- 실제 POSIX permission 테스트만 사용하면 CI/sandbox/user 권한 차이로 flaky해질 수 있습니다.

## Checks

현재 coverage gate와 전체 coverage를 확인합니다.

```sh
make coverage
```

`make coverage`는 runtime library/API boundary에 대해 85% line coverage gate를 적용합니다. 전체 product source coverage도 별도로 확인해 UI/App shell/CLI orchestrator 쪽 blind spot을 파악합니다.

Runtime Control HTTP 경계의 반복 가능한 E2E smoke를 확인합니다.

```sh
make e2e-smoke
```

이 smoke는 local HTTP server를 실제로 기동하고 core read endpoint와 missing-token failure를 확인합니다. 설치, update 적용, rollback 같은 destructive 작업은 별도 명시 없이 실행하지 않습니다.

로컬 반복 검증은 아래 묶음 명령을 사용합니다.

```sh
make e2e-local
E2E_LOOP_COUNT=5 E2E_LOOP_INTERVAL=10 make e2e-local-loop
```

`make e2e-local`은 Runtime Control HTTP smoke와 PWA check/test/build를 함께 실행합니다.

권한 실패 테스트가 있는지 빠르게 확인합니다.

```sh
rg -n "fileReadNoPermission|fileWriteNoPermission|permission denied|not permitted|readIssues|readError|chmod" \
  apps/vitalserver-macos-runtime/Tests
```

권한 경계가 있는 production path를 확인합니다.

```sh
rg -n "readData|readUTF8Text|writeData|copyItem|moveItem|removeItem|chmod|posixPermissions|sqlite|exportLogs" \
  apps/vitalserver-macos-runtime/Sources
```

## Actions

권한 실패 검증은 coverage 숫자를 직접 목표로 삼지 않고, 운영 리스크가 큰 경로부터 추가합니다.

1. 권한 실패 surface inventory를 작성합니다.
   - read: settings, logs, backups, observability DB/JSONL
   - write/create: staging directory, settings write, status/progress write, export staging
   - copy/move/remove: update artifact replacement, rollback restore, cleanup
   - chmod: launcher tools, plist, admin password file
   - SQLite: read-only query, schema/index write attempt, fallback

2. deterministic fake 기반 테스트를 우선 추가합니다.
   - `RuntimeFileStore` fake로 `CocoaError(.fileReadNoPermission)`과 `CocoaError(.fileWriteNoPermission)`을 주입합니다.
   - process runner fake로 `permission denied`, `Operation not permitted`, chmod failure를 주입합니다.
   - assertion은 “실패한다”가 아니라 “실패 원인이 올바른 경계에 보존된다”에 둡니다.

3. 필요한 곳만 POSIX integration 테스트를 얇게 둡니다.
   - temp file/dir에 `0o000`, `0o555`, `0o600`을 걸어 실제 FileManager 경로를 검증합니다.
   - root 또는 sandbox 환경에서 의미가 달라지는 경우 mock 기반 테스트를 primary로 둡니다.

4. Update/rollback 경로를 우선 검증합니다.
   - bundle stage에서 existing destination remove 실패
   - artifact copy/move/replace 실패
   - install permission/chmod/plist write 실패
   - rollback restore/cleanup 실패
   - 실패 시 status/progress/log가 남는지

5. Settings/Observability/Export logs 경로를 검증합니다.
   - secret-bearing file은 Helper가 직접 읽지 않아야 합니다.
   - Helper-readable read model은 권한 실패 시 `readIssues`를 노출해야 합니다.
   - SQLite query 실패는 JSONL fallback 또는 `readError`로 노출되어야 합니다.
   - Export logs는 일부 supplemental item 실패를 manifest issue로 남기고 가능한 로그는 계속 export해야 합니다.

## Prevention

권한 경계별 테스트 원칙을 유지합니다.

- 권한 실패는 빈 배열/default value로 숨기지 않습니다.
- secret-bearing file과 Helper-readable file을 분리합니다.
- read path에서 migration, projection rebuild, schema write 같은 side effect를 암묵 수행하지 않습니다.
- update/install/rollback의 destructive step은 실패 시 file path, operation, stderr를 남깁니다.
- coverage gate는 runtime library/API boundary에 적용하고, UI/App shell/CLI orchestrator는 의미 있는 smoke/integration 테스트로 보강합니다.
- 반복 실행 E2E는 먼저 read-only/local-only smoke로 고정하고, update/install/rollback은 별도 fixture와 cleanup 계약이 생긴 뒤 추가합니다.

### Coverage Targets

모든 파일을 100%로 맞추기보다, 운영 판단과 장애 전파에 직접 영향을 주는 영역을 높게 유지합니다.

| Area | Target | Rationale |
|---|---:|---|
| `Core/Application/*` | 95%+ | update/rollback policy와 operation plan은 순수 로직에 가까워 조합 테스트 효율이 높습니다. |
| `Core/Health/*` | 97%+ | runtime health 판단은 운영 상태와 recovery 판단의 기준입니다. |
| `Core/Guest/*Evaluator` | 95%+ | guest activation/bootstrap/shutdown 결과 해석은 failure reason 품질과 직결됩니다. |
| `RuntimeControlAPI/Boundary/*` | 90%+, core handler 95% | PWA/API 경계에서 실패가 빈 결과나 성공으로 숨겨지지 않아야 합니다. |
| `RuntimeControlAPI/Transport/RuntimeControlHTTPWireCodec.swift` | 95%+ | HTTP parsing/encoding은 순수 로직이고 edge case 회귀 비용이 큽니다. |
| `MacHostRuntimeAdapter/RuntimeObservabilityReader.swift` | 90%+ | event 미조회 이슈와 직접 연결되므로 read failure와 empty result를 구분해야 합니다. |
| `MacHostRuntimeAdapter/RuntimeFileReaders.swift` | 90%+ | Settings/log/update bundle summary 진단 경로의 권한/파일 없음/invalid data 처리가 중요합니다. |
| `MacHostRuntimeAdapter/RuntimeSettingsReader.swift` | 95%+ | Settings read issue surface는 Helper 권한 문제의 1차 진단 경계입니다. |
| `MacHostRuntimeAdapter/RuntimeLogExporter.swift` | 95%+ | Export logs는 partial failure를 manifest issue로 남겨야 합니다. |
| OS/process adapter and SwiftUI shell | 60-90% by risk | line coverage보다 command mapping, error propagation, smoke rendering을 우선합니다. |

### Remaining Priorities

최근 coverage 보강 이후 남은 우선순위입니다.

목표 달성 항목:

- `RuntimeFileReaders.swift`: 56.12%에서 96.92%까지 상승
- `RuntimeControlHTTPWireCodec.swift`: 74.15%에서 97.96%까지 상승
- `RuntimeUpdatePreflightPolicy.swift`: 68.00%에서 100.00%까지 상승
- `RuntimeUpdateCompatibilityChecker.swift`: 80.77%에서 100.00%까지 상승
- `RuntimeLogExporter.swift`: 91.92%에서 97.31%까지 상승
- `RuntimeSettingsReader.swift`: 90.76%에서 96.74%까지 상승

현재 TS-034에서 지정한 고가치 coverage target은 모두 목표를 달성했습니다. 다음 coverage 보강은 새 장애 사례가 확인될 때 운영 리스크 기준으로 재선정합니다.

## Operational Notes

권한 문제를 실제 현장에서 볼 때는 파일 mode만 보지 말고 owner/process boundary를 같이 봅니다.

```sh
stat -f '%Sp %Su:%Sg %N' "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"
stat -f '%Sp %Su:%Sg %N' "/Library/Application Support/TiroshVitalServer/status/runtime-observability.sqlite"
stat -f '%Sp %Su:%Sg %N' "/Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-config.json"
```

Helper 사용자 권한에서 읽기/쓰기 probe를 분리합니다. SQLite row가 있는데 UI가 비어 있으면 event 미생성이 아니라 read path 권한 실패일 수 있습니다.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-024`: pkg 설치가 `Running package scripts...`에서 실패
- `TS-025`: update 후 VM disk attachment가 invalid로 실패
- `TS-029`: Update 중 Host가 Guest shutdown 상태를 추정함
- `TS-033`: Runtime Control Helper가 설정/로그/event를 읽지 못함

## Follow-up

- 2026-05-30: `make coverage`에 runtime library/API boundary 기준 85% line coverage gate를 추가했습니다. 당시 scoped coverage는 85.43%, 전체 product source coverage는 74.92%입니다.
- 2026-05-30: MacHostRuntimeAdapter worker/client/command worker, MacTestKitController HTTP boundary, RuntimeViewModel TestKit flow, RuntimeAdvancedPanel smoke rendering 테스트를 추가했습니다.
- 2026-05-30: 다음 보강 범위를 permission failure 중심으로 재정의했습니다. 우선순위는 update/install/rollback 권한 실패, Settings/Observability read error propagation, Export logs partial failure manifest입니다.
- 2026-05-31: update/apply 경로의 권한 실패 전파 테스트를 추가했습니다. Bundle stage의 기존 staged bundle 제거 실패와 managed storage copy 실패, artifact replacement의 temporary directory 생성 실패와 기존 app bundle 제거 실패, rootfs/update artifact replacement 실패를 검증합니다.
- 2026-05-31: Runtime Control API handler에서 backup list read permission failure와 Export logs write permission failure가 빈 결과나 성공 응답으로 숨겨지지 않고 그대로 throw되는지 검증합니다.
- 2026-05-31: 고가치 coverage target을 TS-034에 명시했습니다. 우선 `RuntimeControlClientAPIReadHandler`는 39.57%에서 100.00%로, `RuntimeObservabilityReader`는 54.71%에서 94.71%로 올렸습니다. 전체 scoped line coverage는 87.27%입니다.
- 2026-05-31: `RuntimeFileReaders`가 `RuntimeFileStore` 추상화로 partial log read를 수행하도록 조정하고, command log fallback, container log refresh 조건, diagnostic source fallback, backup wrapper 실패 전파를 검증했습니다. `RuntimeFileReaders.swift`는 56.12%에서 96.92%로, 전체 scoped line coverage는 88.02%로 상승했습니다.
- 2026-05-31: `RuntimeControlHTTPWireCodec`의 malformed request, invalid `Content-Length`, unsupported method, body-without-length, stream header, bad request response, status phrase encoding edge case를 검증했습니다. `RuntimeControlHTTPWireCodec.swift`는 74.15%에서 97.96%로, 전체 scoped line coverage는 88.41%로 상승했습니다.
- 2026-05-31: `RuntimeUpdatePreflightPolicy`가 compatible bundle을 통과시키고 compatibility failure를 그대로 전파하는지 검증했습니다. `RuntimeUpdatePreflightPolicy.swift`는 68.00%에서 100.00%로, 전체 scoped line coverage는 88.50%로 상승했습니다.
- 2026-05-31: `RuntimeUpdateCompatibilityChecker`의 equivalent version, text/numeric version segment comparison, mixed text/number comparison, operational error description을 검증했습니다. `RuntimeUpdateCompatibilityChecker.swift`는 80.77%에서 100.00%로, 전체 scoped line coverage는 88.73%로 상승했습니다.
- 2026-05-31: `RuntimeLogExporter`가 기존 export archive를 교체하고, ditto archive 실패 시 stdout/stderr 또는 fallback summary를 보존하는지 검증했습니다. `RuntimeLogExporter.swift`는 91.92%에서 97.31%로, 전체 scoped line coverage는 88.93%로 상승했습니다.
- 2026-05-31: `RuntimeSettingsReader`가 disk size, public runtime settings, legacy runtime config, proxy launch daemon read failure를 `readIssues`에 보존하는지 검증했습니다. `RuntimeSettingsReader.swift`는 90.76%에서 96.74%로, 전체 scoped line coverage는 89.05%로 상승했습니다.
- 2026-05-31: `make e2e-smoke`를 추가해 Runtime Control local HTTP server, core read endpoint, auth failure를 실제 HTTP 요청으로 검증합니다. destructive install/update/rollback은 이 smoke 범위에서 제외했습니다.
- 2026-05-31: 로컬 반복 검증용 `make e2e-local`과 `make e2e-local-loop`를 추가했습니다. CI 연결 전에는 이 명령으로 Runtime Control HTTP smoke와 PWA check/test/build를 묶어 확인합니다.
