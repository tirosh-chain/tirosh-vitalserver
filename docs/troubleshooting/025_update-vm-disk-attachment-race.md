# 025 update 후 VM disk attachment가 invalid로 실패

> ID: TS-025  
> Category: Update  
> Owner: macOS runtime  
> Status: active

## Symptoms

Update apply가 `activate-guest-update` 단계에서 오래 기다린 뒤 실패합니다. 이후 rollback이 시작되거나 watchdog이 `critical`을 기록하고, `runtime-status.json`에는 아래 reason이 같이 보입니다.

```text
vm-disk-attachment-invalid
vm-launch-failed-virtualization
vm-service-not loaded
guest-runtime-state-stale
```

`logs/runtime/launchd.err.log`에는 Virtualization framework가 VM disk attach를 거부한 기록이 남습니다.

```text
failed to start VM: Error Domain=VZErrorDomain Code=2 "The storage device attachment is invalid."
```

같은 시점에 `logs/runtime/launchd.out.log`에는 guest shutdown이 아직 진행 중인 흔적이 남을 수 있습니다.

```text
Job tirosh-vitalserver-compose.service/stop running
```

## Impact

Update artifact 검증, 파일 교체, migration은 성공했지만 guest activation 또는 rollback health wait가 실패합니다. `vm-disk.img`는 mutable runtime disk라 managed rollback 대상이 아니므로, 같은 update bundle을 반복 적용해도 상태가 풀리지 않을 수 있습니다.

## Cause

확인된 원인은 host update flow의 VM stop/start race입니다. `stop-runtime-services` 단계가 launchd `bootout` 요청 완료를 service stop 완료로 취급했고, VM process가 guest shutdown과 disk flush를 끝내기 전에 `start-runtime-services`가 같은 `vm-disk.img`를 다시 attach할 수 있었습니다.

이 경우 disk image 파일이 반드시 손상된 것은 아닙니다. 이전 VM process가 아직 disk를 소유한 상태이면 새 `VZDiskImageStorageDeviceAttachment(readOnly: false)`가 같은 raw disk를 열지 못해 `storage device attachment is invalid`를 반환할 수 있습니다.

TS-013은 ext4 journal/read-only 손상 케이스이고, TS-025는 shutdown 미완료 또는 stale VM process로 인한 attach race 케이스입니다. 두 증상은 같은 Virtualization error를 공유할 수 있으므로 launchd stdout의 shutdown 진행 상태와 host process 상태를 함께 확인합니다.

## Checks

```sh
tail -n 240 /private/tmp/tirosh-vitalserver-manager-command.log
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 120 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.err.log"
tail -n 260 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.out.log"
ps aux | grep -E 'vitalserver-vm|VitalServer|nginx'
netstat -anv -p tcp | grep '.80'
```

특히 아래 순서가 보이면 attach race 가능성이 높습니다.

```text
step=stop-runtime-services status=completed
step=start-runtime-services status=started
Job tirosh-vitalserver-compose.service/stop running
failed to start VM: ... "The storage device attachment is invalid."
```

## Actions

1. Update command가 아직 살아 있으면 먼저 중복 apply를 멈춥니다. 관리자 권한으로 실행된 `vitalserver-vm runtime apply-bundle ...` 프로세스가 남아 있는지 확인합니다.
2. VM launchd service와 VM pid file 상태를 확인합니다.

```sh
launchctl print system/com.tirosh.vitalserver-vm
cat "/Library/Application Support/TiroshVitalServer/vm/run/vitalserver-vm.pid"
```

3. 이전 VM process가 남아 있으면 guest shutdown이 끝날 때까지 기다립니다. 장시간 멈춰 있으면 VM disk와 Redis backup 보존 여부를 먼저 확인한 뒤 복구 절차를 선택합니다.
4. 80번 포트가 stale nginx에 잡혀 있으면 host proxy 문제를 별도로 정리합니다. 이 문제는 VM disk attach 실패의 직접 원인은 아니지만 rollback/health check 실패를 연쇄적으로 만들 수 있습니다.
5. ext4 오류나 read-only remount가 같이 보이면 TS-013 절차를 우선합니다.

## Prevention

2026-05-29 수정: `RuntimeServiceController.stopRuntimeServices()`가 stop 요청 직후 완료되지 않고, loaded launchd job이 사라질 때까지 기다립니다. 일반 VM service stop의 경우 launchd `bootout` 전에 `vitalserver-vm.pid`가 가리키는 process에 먼저 `SIGTERM`을 보내 Virtualization `requestStop()` 경로를 타게 하고, process가 종료되거나 pid file이 정리될 때까지 기다립니다. 2026-06-01 이후 VM stop 대기 시간은 최대 900초입니다.

2026-06-02 수정: update bundle 적용처럼 guest가 update shutdown contract를 처리하는 경로는 일반 VM stop과 다릅니다. Guest가 `shutdownPhase=poweroff-requested`를 명시적으로 쓴 뒤 host는 VM process 자연 종료를 기다리고, 그 다음 launchd job을 정리합니다. 이 경로에서는 host가 VM process에 직접 stop signal을 보내지 않습니다.

추가 현장 로그에서 guest가 `poweroff.target` 이후 initrd shutdown으로 들어갔지만 `systemd-resolved` 프로세스를 계속 기다려 VM process가 330초 안에 끝나지 않는 케이스를 확인했습니다. 최신 host CLI는 guest shutdown을 log marker로 추정하거나 VM process를 자동 강제 종료하지 않습니다. VM process가 900초 안에 종료되지 않으면 update를 실패로 남기고, disk와 Redis backup 보존 여부를 확인한 뒤 수동 복구 절차를 선택합니다.

이 순서가 중요합니다. update bundle의 `004-refresh-vm-shutdown-timeouts` migration은 첫 `stop-runtime-services` 이후 실행되므로, 기존 설치본에서 이미 loaded 상태인 launchd VM job은 여전히 예전 `exit timeout = 60`을 들고 있을 수 있습니다. VM process를 먼저 graceful stop하지 않으면 첫 stop부터 launchd timeout에 의해 강제 종료될 수 있습니다.

이 수정 이후 `stop-runtime-services` progress event의 `completed` 시점은 launchd 요청 완료가 아니라 service/process stop 확인 완료를 의미합니다. timeout이 발생하면 같은 단계가 실패 event로 기록되므로, 이후 `start-runtime-services`가 같은 disk를 섣불리 attach하지 않습니다.

## Operational Notes

- `vm-disk.img`가 존재하고 `file` 명령에서 GPT/raw disk로 보이는 것만으로는 안전한 attach 가능 상태를 보장하지 않습니다.
- `runtime-status.json`의 `vm-disk-attachment-invalid`는 disk corruption과 attach race 모두에서 발생할 수 있습니다.
- update/rollback 중 같은 bundle을 반복 적용하기 전에 `/private/tmp/tirosh-vitalserver-manager-command.log`와 host process 상태를 먼저 확인합니다.

## Related Cases

- TS-012: bundle update가 health wait 또는 rollback에서 오래 멈춤
- TS-013: update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨
- TS-023: stale pid file

## Follow-up

- 2026-05-29: 현장 로그에서 `stop-runtime-services completed` 직후 guest compose stop이 계속 진행 중이고, 새 VM start가 `VZErrorDomain Code=2`로 실패하는 흐름을 확인했습니다.
- 2026-05-29: host CLI에 service unload wait와 VM pid/process wait를 추가했습니다.
- 2026-06-01: guest shutdown이 filesystem detach/finalization 이후 initrd에서 `systemd-resolved`를 기다리며 VM process가 330초 안에 종료되지 않는 흐름을 확인했습니다. disk-safe shutdown marker 기반 forced stop fallback은 사용하지 않고, VM stop timeout을 900초로 늘렸습니다.
