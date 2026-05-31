# 036 macOS runtime 카오스 테스트 체계가 필요함

> ID: TS-036  
> Category: Update / Runtime health / Observability / Packaging  
> Owner: macOS runtime / testkit  
> Status: resolved

## Symptoms

현장 장애가 happy path 테스트와 coverage gate를 통과한 뒤에 발견될 수 있습니다.

- update 중 log refresh 권한 실패가 실제 update 상태를 흐립니다.
- Settings가 `runtime-config.json` 같은 secret-bearing file을 직접 읽으려다 권한 실패를 표시합니다.
- Observability event가 실제로 없어진 것인지, read path가 실패한 것인지 UI에서 구분하기 어렵습니다.
- clean uninstall 이후에도 이전 update 상태, stale request/result, root-owned directory, cached PWA asset이 영향을 줄 수 있습니다.
- Guest capability worker, log directory, SQLite/JSONL event store, backup/rollback directory 중 하나가 깨졌을 때 Host/PWA가 빈 값이나 generic failure로 숨길 수 있습니다.

정상 상태라면 장애 주입 후에도 실패가 예측 가능한 typed failure, read issue, runtime event, command result, export manifest, UI state 중 적절한 경계에 남아야 합니다.

## Impact

카오스 테스트가 없으면 운영자가 실제 장애에서 아래를 구분하기 어렵습니다.

- update flow failure vs log read failure
- event 미생성 vs event read failure
- clean uninstall 실패 vs stale installed artifact
- Guest worker unsupported vs Host timeout
- recoverable partial failure vs destructive state corruption

특히 update/install/rollback은 파일 교체, service stop/start, VM disk, Redis backup, PWA asset activation이 얽혀 있어 작은 권한/IO 실패도 runtime을 partially updated 상태로 남길 수 있습니다.

## Cause

기존 테스트는 주로 deterministic unit/integration과 read-only smoke에 집중되어 있습니다. 이는 안정적인 regression gate로 적합하지만, 실제 운영 장애 조건은 아래처럼 여러 경계가 동시에 흔들립니다.

- Host user process와 root/service-owned 파일의 permission mismatch
- Guest request/result worker capability 부재
- update bundle stage, artifact replace, rollback cleanup 중간 실패
- Observability SQLite/JSONL read/write partial failure
- PWA/service worker/cache가 이전 asset을 유지하는 update activation 문제
- clean uninstall 후 app bundle, launchd plist, runtime state, temp/log/cache 잔존

AGENTS.md 원칙상 Host/UI는 상태를 추정하지 않아야 합니다. 따라서 chaos test의 목적은 “어떻게든 복구한다”가 아니라, 상태 owner가 실패를 명시하고 consumer가 그 실패를 숨기지 않는지 검증하는 것입니다.

## Checks

현재 기본 regression gate를 먼저 통과시킵니다.

```sh
make coverage
make runtime-chaos
CHAOS_LOOP_COUNT=5 make runtime-chaos-loop
cd apps/vitalserver-runtime-pwa && npm run test -- --run src/infrastructure/console-api/consoleClient.test.ts
make e2e-smoke
make e2e-local
```

설치본의 host-visible permission 상태는 chaos 실행 전 baseline으로 기록합니다.

```sh
make runtime-permission-audit
RUNTIME_PERMISSION_AUDIT_ARGS=--require-install make runtime-permission-audit
```

update/observability/log 관련 상태를 수집합니다.

```sh
stat -f '%Sp %Su:%Sg %N' \
  "/Library/Application Support/TiroshVitalServer/logs" \
  "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl" \
  "/Library/Application Support/TiroshVitalServer/status/runtime-observability.sqlite"

jq '{status,operation,message,progress,failureReasons}' \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
```

현재 코드에 chaos/fault injection seam이 있는지 확인합니다.

```sh
rg -n "RuntimeFileStore|ProcessRunner|permission|fault|chaos|CocoaError|readIssues|readError" \
  apps/vitalserver-macos-runtime/Tests apps/vitalserver-macos-runtime/Sources
```

## Actions

카오스 테스트는 destructive random test가 아니라 단계별로 도입합니다.

1. Scenario catalog를 고정합니다.
   - permission chaos: log/settings/event/backup directory read/write denial
   - update chaos: stage/copy/move/remove/chmod/plist/write failure
   - guest contract chaos: missing capability, missing result, invalid result, timeout, explicit unsupported
   - observability chaos: SQLite unreadable, JSONL unreadable, corrupted event row, empty-but-readable store
   - uninstall chaos: launchd unload failure, app bundle remove failure, runtime directory partial remove, stale update request/result
   - PWA chaos: stale asset cache, API contract mismatch, endpoint unreachable, partial response decode failure

2. Deterministic fault injection을 먼저 구현합니다.
   - `RuntimeFileStore` fake로 file read/write/copy/move/remove/chmod failure를 주입합니다.
   - process runner fake로 command timeout, non-zero exit, stderr permission failure를 주입합니다.
   - Guest capability/result reader fake로 unsupported/missing/invalid/running-timeout을 주입합니다.
   - HTTP/PWA 테스트는 mocked gateway와 contract decoder로 API/network/contract failure를 분리합니다.
   - 반복 실행은 `CHAOS_LOOP_COUNT`, `CHAOS_LOOP_INTERVAL`로 제어하고, 기본 suite는 deterministic scenario만 실행합니다.

3. Local-only POSIX chaos를 얇게 추가합니다.
   - temp directory에 `0o000`, `0o555`, `0o600`을 적용해 실제 FileManager path를 검증합니다.
   - root/sandbox/CI 차이로 flaky해지는 경우 deterministic fake를 primary로 유지합니다.

4. Installed-runtime chaos는 명시 opt-in으로 둡니다.
   - 기본 `make e2e-local`에는 destructive chaos를 넣지 않습니다.
   - 설치본 대상 chaos는 `--require-install`, `--confirm-destructive`, backup path 확인을 요구합니다.
   - 실행 전후 `runtime-permission-audit`, runtime status, command log, event history를 저장합니다.

5. Assertion 기준을 명시합니다.
   - 실패가 성공/빈 값/default로 숨겨지지 않아야 합니다.
   - 실패 원인이 owner boundary에 보존되어야 합니다.
   - recovery가 가능하면 recovery command/result/event가 남아야 합니다.
   - recovery가 불가능하면 unsafe retry 대신 typed failure로 멈춰야 합니다.

## Implemented Scenario Set

우선순위는 실제로 문제가 확인된 흐름부터 잡았습니다. 현재 기본 deterministic suite는 destructive installed-runtime 조작 없이 아래 계약을 검증합니다.

| Scenario | Injected fault | Expected result | Coverage |
|---|---|---|---|
| log export permission chaos | log collection failure, supplemental file copy denied | 가능한 로그는 export하고, 실패 item은 export manifest에 남김 | `RuntimeChaosScenarioTests` |
| settings read permission chaos | secret-bearing config read denied | Helper가 secret file을 직접 required read model로 요구하지 않음 | `RuntimeChaosScenarioTests` |
| observability read chaos | SQLite/JSONL event store read denied | `0 events`/unavailable default가 아니라 read failure/readError를 노출 | `RuntimeChaosScenarioTests` |
| observability corruption chaos | corrupt SQLite file | event 없음과 store corruption을 readError/failed state로 분리 | `RuntimeChaosScenarioTests` |
| update log refresh chaos | update 중 log collection refresh 실패 | update operation state와 log read failure를 분리 | `RuntimeChaosScenarioTests` |
| update artifact chaos | managed storage copy denied | copy 실패 원래 error와 operation log를 보존 | `RuntimeUpdateChaosScenarioTests` |
| update apply chaos | apply 중 update artifact replacement 실패 | partial success로 보이지 않고 failed progress, recovering status, rollback 시도를 남김 | `RuntimeUpdateChaosScenarioTests` |
| rollback chaos | rollback restore step failure | failed rollback step과 recovering status를 보존 | `RuntimeUpdateChaosScenarioTests` |
| guest capability chaos | capability missing/read failure | request를 쓰기 전에 typed failure로 중단 | `RuntimeUpdateChaosScenarioTests` |
| guest result chaos | stale result, missing result timeout | Host가 Guest 내부 상태를 추정하지 않고 invalid/timeout을 분리 | `RuntimeUpdateChaosScenarioTests` |
| clean uninstall residue chaos | uninstaller missing after partial uninstall/residue | clean uninstall command를 추정 실행하지 않고 missing uninstaller boundary에서 중단 | `RuntimeChaosScenarioTests` |
| installed permission chaos | installed backup directory read denied | empty backup list로 숨기지 않고 read failure를 throw | `RuntimeChaosScenarioTests` |
| backup/restore chaos | backup artifact copy denied, restore rootfs missing | backup manifest를 쓰기 전에 중단하고 missing restore artifact에서 rollback preflight 중단 | `RuntimeUpdateChaosScenarioTests` |
| runtime command chaos | command non-zero exit with stderr | throw 전에 stderr, failed event, process result를 남김 | `RuntimeUpdateChaosScenarioTests` |
| PWA API contract chaos | API 500, contract mismatch, network failure | UI/client가 domain state를 만들지 않고 API/contract/network error boundary를 유지 | `consoleClient.test.ts` |

## Scenario Coverage

TS-036은 개별 장애를 새 TS로 쪼개기보다 macOS runtime chaos scenario catalog로 유지합니다. High/medium priority backlog는 deterministic Tier 1/2 coverage로 전환했습니다.

| Priority | Scenario | Coverage status | Tier |
|---|---|---|---|
| High | update apply chaos | covered by deterministic apply runner chaos | Tier 1 |
| High | rollback chaos | covered by deterministic rollback runner chaos | Tier 1 |
| High | guest result chaos | covered by deterministic GuestActivationWaiter chaos | Tier 1 |
| High | clean uninstall residue chaos | covered at command boundary; destructive residue audit remains opt-in | Tier 1 / Tier 3 opt-in |
| High | installed permission chaos | covered at host file reader boundary; installed read-only audit remains opt-in | Tier 1 / Tier 3 opt-in |
| Medium | observability corruption chaos | covered by corrupt SQLite read chaos | Tier 2 |
| Medium | backup/restore chaos | covered by backup copy denial and rollback preflight missing artifact chaos | Tier 1 |
| Medium | PWA API contract chaos | covered by ConsoleClient API/contract/network boundary chaos | Tier 1 |

## Installed Verification

2026-05-31에 destructive action 없이 설치본 read-only 검증을 수행했습니다.

| Check | Result | Notes |
|---|---|---|
| `make runtime-permission-audit` | passed | installed runtime 필수 경로 모두 `OK`; `/Users/Shared/TiroshVitalServer`만 optional `WARN missing` |
| `RUNTIME_PERMISSION_AUDIT_ARGS=--require-install make runtime-permission-audit` | passed | Helper app, launcher, uninstaller, status/log/db/runtime/deploy/run 경로 모두 required audit 통과 |
| `make e2e-smoke` | passed | Runtime Control HTTP core read endpoint smoke 통과 |
| `make e2e-local` | passed | HTTP smoke, PWA typecheck, PWA test 86개, PWA production build 통과 |

Tier 4 destructive chaos는 실행하지 않았습니다. `sudo chmod`, `launchctl`, app bundle removal, runtime directory partial remove, update apply interruption은 backup/cleanup/명시 확인이 있는 별도 운영 절차에서만 수행합니다.

## Prevention

- Chaos scenario는 실제 운영 장애와 연결된 named scenario로 관리합니다.
- Random fault injection은 deterministic scenario가 충분히 쌓인 뒤에만 추가합니다.
- Destructive chaos는 기본 test/coverage/e2e-local에 포함하지 않습니다.
- State owner가 명시하지 않은 상태를 Host/UI가 추정하는지 검증합니다.
- Permission/read/decode/contract failure는 empty/default value로 숨기지 않습니다.
- 새 update/repair/uninstall flow는 최소 하나 이상의 failure-path chaos scenario를 함께 가져야 합니다.
- Chaos 실행 결과는 command log, runtime event, export manifest, UI state를 함께 확인합니다.

## Operational Notes

카오스 테스트는 운영 설치본을 손상시킬 수 있으므로 실행 tier를 분리합니다.

- Tier 1: unit/fake chaos. 항상 CI 가능.
- Tier 2: local temp filesystem chaos. CI 가능하지만 POSIX 권한 차이 주의.
- Tier 3: local installed-runtime read-only chaos. 명시 opt-in 필요.
- Tier 4: installed-runtime destructive chaos. backup/cleanup/확인 프롬프트 필수.

`sudo chmod`, `launchctl`, app bundle removal, runtime directory removal, update apply interruption은 Tier 4입니다. TS 문서에 scenario와 expected recovery contract가 없는 destructive chaos는 실행하지 않습니다.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-027`: Update 적용 후 PWA가 이전 JS를 계속 사용
- `TS-033`: Runtime Control Helper가 설정/로그/event를 읽지 못함
- `TS-034`: macOS runtime 권한 실패 검증이 부족함
- `TS-035`: Update가 Guest capability 계약 없이 request/result worker를 가정함

## Follow-up

- 2026-05-31: PWA coverage gate를 추가해 statements 88.51%, lines 88.42%, functions 89.04%, branches 70.09% 상태에서 threshold를 적용했습니다. Chaos test는 coverage 숫자보다 failure visibility와 recovery contract를 우선합니다.
- 2026-05-31: 카오스 테스트를 TS-036으로 등록했습니다. 첫 구현 후보는 permission chaos, observability read chaos, update log refresh chaos, guest capability chaos입니다.
- 2026-05-31: `make runtime-chaos`를 추가해 `Chaos` 필터가 붙은 deterministic Swift chaos scenario만 빠르게 실행할 수 있게 했습니다. 초기 suite는 update log refresh chaos, observability read chaos, settings permission chaos, guest capability chaos, update artifact copy permission chaos를 포함합니다.
- 2026-05-31: `make runtime-chaos-loop`를 추가해 deterministic chaos suite를 반복 실행할 수 있게 했습니다. suite는 log export manifest issue, observability snapshot/relationship read failure, command stderr/runtime event 보존까지 확장했습니다.
- 2026-05-31: high/medium priority backlog를 deterministic coverage로 전환했습니다. Swift `Chaos` suite는 18개 scenario를 통과하고, PWA ConsoleClient는 API/contract/network boundary chaos를 통과합니다. TS-036 상태를 `resolved`로 변경했습니다.
- 2026-05-31: 설치본 read-only permission audit와 `make e2e-smoke`, `make e2e-local`을 통과했습니다. Tier 4 destructive chaos는 의도적으로 실행하지 않았습니다.
