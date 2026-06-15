# Update Shutdown Service Failed Without Result

> ID: TS-061  
> Category: Update  
> Owner: macOS runtime / guest command contract  
> Status: resolved

## Symptoms

- Product update가 `stop-runtime-services` 단계에서 멈춘 뒤 실패합니다.
- Helper message 또는 manager command log에 아래 흐름이 보입니다.

```text
guest update shutdown requested version=<version>
waiting for guest update shutdown result timeoutSeconds=300.0
waiting for guest update shutdown worker
guest update shutdown timed out
bundle apply failed; rolling back: guest update shutdown timed out
```

- guest request-file poller log에는 `prepare-update-shutdown.request`가 반복 감지되고
  `service-scheduled`가 반복됩니다.
- `prepare-update-shutdown-result.json`과 `prepare-update-shutdown.log`가 없거나 비어 있습니다.
- observability snapshot 또는 systemd state에서는
  `tirosh-vitalserver-prepare-update-shutdown.service`가 `failed`로 보일 수 있습니다.
- 이후 rollback이나 VM stop 중 Linux kernel panic/unmount stack trace가 나타날 수 있습니다.

## Impact

Update가 실패하고 rollback으로 들어갈 수 있습니다. rollback stop 단계에서 VM shutdown이 다시
실패하면 runtime status가 `recovering` 또는 rollback progress에 남을 수 있습니다.

이 증상에서 kernel panic은 주요 단서이지만 1차 원인으로 단정하지 않습니다. 먼저 guest
`prepare-update-shutdown` 작업이 명시 result를 남겼는지 확인해야 합니다.

## Cause

guest command poller가 `systemctl start --no-block` 성공만 보고 `service-scheduled`로 기록했습니다.
oneshot service가 즉시 `failed`가 되어도 request file이 남아 있으면 poller가 계속 재스케줄했고,
Host는 `prepare-update-shutdown-result.json`만 기다리다가 timeout까지 갔습니다.

즉, 실패한 guest unit state가 Host contract로 올라오지 않아 `failed`와 `pending`이 같은 모양으로
보였습니다. rollback 중 보인 VM kernel panic은 guest shutdown 준비 실패 이후 VM stop 과정에서
발생한 2차 장애로 봅니다.

## Checks

```sh
tail -n 200 "/private/tmp/tirosh-vitalserver-helper-message.log"
tail -n 200 "/private/tmp/tirosh-vitalserver-manager-command.log"
tail -n 200 "/Library/Application Support/VitalServerHelper/vm/data/run/guest-request-file-poller.log"
ls -l "/Library/Application Support/VitalServerHelper/vm/data/run/prepare-update-shutdown-result.json"
ls -l "/Library/Application Support/VitalServerHelper/vm/data/run/prepare-update-shutdown.log"
cat "/Library/Application Support/VitalServerHelper/status/runtime-operation-lease.json"
tail -n 200 "/Library/Application Support/VitalServerHelper/logs/runtime/launchd.out.log"
```

확인할 기준:

- `guest-request-file-poller.log`에 같은 request가 반복 schedule되는지
- `prepare-update-shutdown-result.json`이 `failed`인지, missing인지
- operation lease의 `expiresAt`이 있는지
- launchd log의 kernel panic이 timeout 이후 rollback/stop 시점인지

## Actions

최신 runtime에서는 poller가 prepare-update-shutdown unit failure 또는 dispatch failure를
`prepare-update-shutdown-result.json`에 `status=failed`로 기록합니다. Host는 이 명시 실패를
받으면 timeout까지 기다리지 않고 update 실패로 전환합니다.

이미 이전 버전에서 이 상태가 발생한 설치본은 먼저 update를 반복하지 않습니다. runtime operation
lease와 runtime status를 확인하고, VM process와 launchd state가 남아 있으면 clean uninstall 또는
VM disk repair 절차 중 데이터 보존 요구에 맞는 쪽을 선택합니다.

## Prevention

- guest poller는 `systemctl start --no-block` 성공을 operation 성공으로 취급하지 않습니다.
- unit이 `failed`이면 request를 반복 schedule하지 않고 explicit failed result를 기록합니다.
- update shutdown result JSON은 temp replace 후 file/directory fsync로 내구성을 높입니다.
- final sync가 끝나면 Guest는 poweroff request 전에 `ready`/`poweroff-ready` result를 먼저 기록해야 합니다.
- update VM shutdown 실패는 `RuntimeVMStateControlUseCase`가 회수 책임을 갖고 force-stop fallback을 실행합니다.
- apply-bundle operation lease는 `expiresAt`을 가져야 하며, stale operation이 watchdog recovery를 영구 차단하지 않습니다.

## Operational Notes

`prepare-update-shutdown.log`가 없는 것은 “아무 일도 안 했다”가 아니라 진입 전 실패, runtime share
mount 실패, systemd unit 실행 실패일 수 있습니다. 이 경우 poller/result contract를 먼저 봅니다.

Host는 guest 내부 상태를 log line이나 request file 존재로 추정하지 않습니다. Guest가 제공한 result
document나 dispatch failure document만 operation transition 근거로 사용합니다.

## Related Cases

- TS-013
- TS-029
- TS-030
- TS-049
- TS-053

## Follow-up

- 2026-06-10: update log timeout 이후 rollback stop 중 kernel panic이 보인 사례를 분석했습니다.
  1차 원인은 guest prepare-update-shutdown unit failure가 result contract로 노출되지 않은 것이며,
  kernel panic은 이후 VM stop 과정의 2차 장애로 분리했습니다.
