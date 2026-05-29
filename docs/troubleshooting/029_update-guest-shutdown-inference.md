# 029 Update 중 Host가 Guest shutdown 상태를 추정함

> ID: TS-029
> Category: Update
> Owner: macOS runtime
> Status: resolved

## Symptoms

Update bundle 적용 중 `stop-runtime-services` 단계가 오래 멈추거나 실패합니다.

대표 로그:

```text
requesting graceful VM process stop before launchd unload
sent SIGTERM to VM process pid=16308
step=stop-runtime-services status=failed
bundle apply failed; rolling back error=VM process did not stop within 330s pid=16308
```

이전 구현에서는 VM process가 종료되지 않을 때 host가 guest log marker 또는 guest-side result를 다시 읽어 “guest disk가 안전한 상태일 것”이라고 추정한 뒤 force kill로 넘어가는 fallback을 갖고 있었습니다.

## Impact

Update 절차가 불필요하게 복잡해지고, 실패 원인이 흐려집니다.

- Host가 guest 내부 shutdown 완료 여부를 log marker로 추정합니다.
- 오래된 result, stale result, 새 request의 result를 구분하기 위한 방어로직이 계속 늘어납니다.
- graceful stop 실패와 guest shutdown 준비 실패가 같은 단계에서 뒤섞입니다.
- VM disk 손상, Redis backup 누락, rollback 지연 같은 증상이 서로 연결된 것처럼 보입니다.

## Cause

제품 설계 문제입니다.

Update는 host와 guest가 동시에 관여하는 작업인데, host가 guest 내부 상태를 간접 관측으로 판단했습니다. 특히 log marker 기반 판단은 신뢰할 수 있는 contract가 아닙니다.

문제의 패턴:

```text
host sends VM SIGTERM
host waits for VM process exit
if timeout:
  host reads guest/launchd logs
  host infers disk-safe shutdown
  host force kills VM
```

이 구조는 장애를 “복구”하는 것처럼 보이지만 실제로는 host가 guest의 책임을 대신 추정하는 fallback입니다. 조건이 늘어날수록 update flow의 핵심 판단이 분산됩니다.

## Checks

아래 문자열이 코드나 로그에 보이면 이 케이스를 의심합니다.

```sh
rg -n "disk-safe|disk safe|RuntimeVMShutdownLogProbe|vmDiskSafeShutdown|force stopping VM" apps/vitalserver-macos-runtime
rg -n "stale guest update|stale datastore|onStale|try\\? removePreviousResult" apps/vitalserver-macos-runtime
```

실패 signature:

```text
VM process did not stop within
guest disk-safe shutdown marker
stale guest update activation result
stale datastore repair result
```

## Actions

Host-side 추정과 fallback을 제거합니다.

수정된 update shutdown 원칙:

1. Host가 guest에 명시적 request를 작성합니다.
2. Guest가 Redis backup, container/service stop, `sync`를 수행합니다.
3. Guest가 현재 requestId에 대한 result를 작성합니다.
4. Host는 현재 requestId의 성공 result만 인정합니다.
5. 이후 VM은 graceful stop만 수행합니다.
6. VM stop timeout이면 실패로 처리합니다. Host가 log marker나 stale result를 근거로 force kill하지 않습니다.

현재 구현에서 유지해야 하는 contract:

```text
prepare-update-shutdown.request
prepare-update-shutdown-result.json
prepare-update-shutdown.log
```

Guest shutdown result는 현재 requestId와 일치해야 합니다. 이전 result가 남아 있거나 result 삭제가 실패하면 진행하지 않습니다.

## Prevention

Update 관련 방어로직은 아래 원칙을 지킵니다.

- Host는 guest 내부 상태를 추정하지 않습니다.
- Log는 진단 자료이며 상태 전이 contract가 아닙니다.
- Result document는 현재 requestId와 일치할 때만 유효합니다.
- `try? removePreviousResult()`처럼 실패를 숨기는 코드는 update/repair/activation 경로에 두지 않습니다.
- Fallback으로 정상 경로를 대체하지 않습니다. 실패는 명확히 실패로 남기고, 별도 repair action으로 복구합니다.

코드 구조 원칙:

- preflight 판단은 `RuntimeUpdatePreflightPolicy`
- managed operation 판단은 `RuntimeManagedOperationPolicy`
- health 분류는 `RuntimeHealthClassificationPolicy`
- guest shutdown 대기는 `GuestShutdownEvaluator` / `RuntimeGuestShutdownRunner`

## Operational Notes

이 케이스는 “graceful shutdown이 어렵다”기보다 “host가 guest를 추정하려고 해서 어려워진” 문제입니다. Guest가 준비 완료를 명시적으로 말하지 않으면 update는 진행하지 않는 것이 맞습니다.

VM process가 graceful stop timeout으로 실패하면 update를 성공시키기 위해 force kill하지 않습니다. 이후 조치는 별도 repair 기능 또는 수동 진단으로 분리해야 합니다.

## Related Cases

- `TS-012`: bundle update가 health wait 또는 rollback에서 오래 멈춤
- `TS-013`: update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨
- `TS-025`: update 후 VM disk attachment가 invalid로 실패

## Follow-up

- 2026-05-29: update 중 host-side guest shutdown 추정, disk-safe log marker fallback, stale result wait를 제거했습니다. 명시적 guest shutdown request/result contract만 사용하도록 단순화했습니다.
