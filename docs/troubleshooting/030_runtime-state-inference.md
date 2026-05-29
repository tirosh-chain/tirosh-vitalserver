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
- `runtime-state.json`이 없거나 stale인데 `vm-ip` 파일로 guest endpoint를 직접 probing해 상태를 채웁니다.
- container health가 보고되지 않았는데 `stable`로 분류됩니다.

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
11. Guest HTTP 상태는 guest가 제공한 runtime-state만 사용합니다. `vm-ip` 파일을 이용해 Host가 guest readiness를 대신 probing하지 않습니다.
12. 보고되지 않은 container health는 `stable`이 아니라 `unreported`로 분류합니다.

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
- 2026-05-29: `RuntimeHealthChecker`가 missing/stale `runtime-state.json` 상태에서 `vm-ip` 파일로 guest readiness를 직접 probing하던 경로를 제거했습니다. Guest HTTP 상태는 runtime-state가 제공한 값만 사용합니다.
- 2026-05-29: container health 미보고 값을 `stable`로 분류하지 않고 `unreported`로 명시했습니다. `RuntimeHealthInput`의 guest runtime-state 기본값도 제거해 호출자가 present/fresh 여부를 직접 넘기게 했습니다.
