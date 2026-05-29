# 030 Runtime 상태를 Host/UI가 추정함

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

## Impact

상태 판단이 분산되면 장애가 발생했을 때 원인이 흐려집니다.

- 상태의 책임 주체가 불명확해집니다.
- HTTP probe, launchd log, command log, guest result가 서로 다른 결론을 만들 수 있습니다.
- 예외 케이스가 생길 때마다 fallback과 방어로직이 늘어납니다.
- update flow가 실제 contract보다 복잡해지고, 실패를 실패로 남기지 못합니다.

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

## Checks

아래 코드가 다시 생기면 이 케이스를 의심합니다.

```sh
rg -n "LegacyBootstrapLogEvaluator|LegacyCommandProgressParser|legacyCommandProgressLine" apps/vitalserver-macos-runtime
rg -n "inferredVMState|inferredVMErrors|vmDiagnosticErrors\\(" apps/vitalserver-macos-runtime
```

상태 관련 read path에서 아래 패턴이 보이면 재검토합니다.

```text
read log -> map text to status
probe HTTP -> synthesize vmState
missing document field -> infer fallback state
```

## Actions

상태 추정 경로를 제거하고 명시 document만 신뢰합니다.

수정된 원칙:

1. `vmState`, `vmErrors`는 runtime status document가 제공한 값만 표시합니다.
2. status document에 값이 없으면 read layer가 새 값을 만들지 않습니다.
3. update progress는 `RuntimeProgressDocument`만 사용합니다.
4. `command.log`, `bootstrap.log`, launchd log는 상태 전이 입력이 아니라 export/diagnostics 자료로만 사용합니다.
5. Guest 내부 상태가 필요하면 guest가 result/status document로 직접 제공합니다.

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

## Operational Notes

상태가 비어 있거나 `unknown`이면 그 자체가 유효한 신호입니다. UI가 보기 좋게 채우기 위해 추정하면 장애 분석이 더 어려워집니다.

필요한 상태가 없다면 consumer가 추정하지 말고 provider가 contract를 확장해야 합니다. 이 원칙은 Swift Helper와 Remote Console 모두에 적용합니다.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-026`: PWA가 Runtime Control API unreachable을 표시
- `TS-029`: Update 중 Host가 Guest shutdown 상태를 추정함

## Follow-up

- 2026-05-29: `RuntimeStatusReader`의 `vmState`/`vmErrors` 추정, bootstrap log 기반 실패 분류, command log 기반 progress fallback을 제거했습니다.
