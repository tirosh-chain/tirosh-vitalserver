# 013 update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨

> ID: TS-013  
> Category: Update  
> Owner: macOS runtime  
> Status: resolved

증상:

update apply가 `activate-guest-update` 또는 `wait-runtime-health` 단계에서 실패하고 rollback으로 넘어갑니다. 이후 VM IP가 사라지거나 `runtime-state.json`이 갱신되지 않고, launchd log에 아래 메시지가 남습니다.

```text
EXT4-fs error (device vda1): ... iget: checksum invalid
Aborting journal on device vda1-8.
EXT4-fs (vda1): Remounting filesystem read-only
Filesystem error recorded from previous mount: IO failure
mounting fs with errors, running e2fsck is recommended
```

VM 재시작 시에는 아래처럼 Virtualization framework가 disk attachment를 거부할 수 있습니다.

```text
failed to start VM: Error Domain=VZErrorDomain Code=2
"The storage device attachment is invalid."
```

원인:

update는 guest 내부에서 Docker image load, Compose recreate, systemd unit 갱신처럼 root filesystem에 큰 쓰기 작업을 수행합니다. 기존 VM launchd plist의 `ExitTimeOut=90`은 guest shutdown과 Docker Compose stop이 끝나기에는 여유가 부족했습니다. 특히 guest `tirosh-vitalserver-compose.service`의 기본 stop timeout도 90초 수준이라 host launchd timeout과 맞물리면 filesystem flush가 끝나기 전에 VM process가 종료될 수 있습니다.

plist 파일만 갱신되어도 이미 loaded 상태인 launchd job에는 즉시 반영되지 않습니다. 아래처럼 plist는 `ExitTimeOut=300`인데 `launchctl print`의 loaded job은 더 짧은 timeout을 유지할 수 있습니다.

```sh
plutil -p "/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist" | grep ExitTimeOut
launchctl print system/com.tirosh.vitalserver-vm | grep "exit timeout"
```

이 상태에서 update/rollback이 VM을 정지하면 launchd가 예전 timeout 기준으로 VM process를 종료할 수 있고, 그 결과 ext4 journal abort 또는 read-only remount로 이어질 수 있습니다.

이 경우 `vm-disk.img`는 mutable 운영 디스크이므로 managed rollback 대상이 아닙니다. rollback은 app bundle, runtime tools, nginx bundle, guest deploy, rootfs base 같은 교체 가능한 artifact를 복원하지만, 이미 손상된 mutable VM disk를 되돌리지는 않습니다.

확인:

```sh
tail -n 300 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.out.log"
tail -n 100 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.err.log"
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/guest/activate-update.log"
```

plist와 loaded launchd job의 timeout이 같은지도 확인합니다.

```sh
plutil -p "/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist" | grep ExitTimeOut
launchctl print system/com.tirosh.vitalserver-vm | grep "exit timeout"
```

정상적으로 갱신된 상태에서는 plist가 `ExitTimeOut => 300`이고, loaded job도 `exit timeout = 300`을 사용해야 합니다.

조치:

최신 runtime은 VM launchd `ExitTimeOut`을 300초로 늘리고, guest Compose stop timeout과 `sync`를 명시합니다. update bundle에는 `004-refresh-vm-shutdown-timeouts` migration이 포함되어 기존 설치본의 VM launchd plist를 갱신하고, loaded 상태인 VM launchd job을 unload하여 다음 start에서 갱신된 timeout이 적용되게 합니다.

2026-05-29 이후 runtime은 update의 첫 `stop-runtime-services`에서도 launchd timeout만 믿지 않습니다. VM service를 `bootout`하기 전에 `vitalserver-vm.pid`가 가리키는 VM process에 먼저 `SIGTERM`을 보내고, VM process의 signal handler가 Virtualization `requestStop()`을 수행해 guest shutdown과 disk flush를 끝낼 때까지 최대 330초 기다립니다. 따라서 migration이 아직 실행되기 전 loaded launchd job이 예전 `exit timeout = 60`을 들고 있어도 update 첫 stop이 곧바로 강제 종료로 이어지지 않아야 합니다.

이미 disk 오류가 발생한 설치본에서는 같은 update bundle을 반복 적용하지 않습니다. 먼저 Redis backup이 남아 있는지 확인하고, 가능한 경우 Redis backup을 보존한 뒤 VM disk 복구 또는 재설치를 진행합니다.

```sh
ls -lh "/Library/Application Support/TiroshVitalServer/backups"
ls -lh "/Library/Application Support/TiroshVitalServer/vm/data/backups" 2>/dev/null || true
```

Helper 0.1.9 이후에는 수동 VM disk repair를 사용할 수 있습니다. 이 작업은 Redis backup을 먼저 시도한 뒤 현재 `vm-disk.img`를 `backups/vm-disk-repair-<timestamp>/` 아래로 보관하고, 설치된 `rootfs-base.raw.gz`에서 새 VM disk를 만든 뒤 runtime services를 다시 시작합니다. VM이 이미 부팅 불가능해서 Redis backup이 실패해도 기존 VM disk archive는 남깁니다.

```sh
sudo /usr/local/bin/vitalserver-vm runtime repair-vm-disk
```

주의: VM 내부 Redis volume과 Docker runtime state는 새 disk로 교체됩니다. Redis 데이터가 필요하면 Redis backup을 확인하고 복원 절차를 진행합니다. 호스트의 configured Vital files directory는 VM disk 밖에 있으므로 보존됩니다.

운영 판단:

- `activate-update.log`에 `guest update activation completed`가 있어도 이후 health check가 실패할 수 있습니다. 이 경우 update payload가 아니라 VM disk 상태를 먼저 봅니다.
- `EXT4-fs error`, `Remounting filesystem read-only`, `fsck is recommended`가 보이면 일반 rollback보다 VM disk repair/recreate가 우선입니다.
- `vm-disk.img`는 Redis volume과 Docker runtime state를 포함할 수 있으므로 clean uninstall 전에 Redis backup 경로를 확인합니다.

## Follow-up

- 2026-05-28: 재현 환경에서 plist 파일은 `ExitTimeOut=300`이었지만 `launchctl print system/com.tirosh.vitalserver-vm`의 loaded job은 `exit timeout = 60`을 유지하고 있었습니다. 원인은 migration이 plist만 갱신하고 loaded launchd job을 reload/unload하지 않은 것입니다.
- 2026-05-28: `004-refresh-vm-shutdown-timeouts` migration이 VM launchd job을 `bootout`하도록 수정했습니다. 다음 runtime start에서 launchd가 plist를 다시 읽어 `ExitTimeOut=300`을 적용합니다. Fix: `2aaef21 fix: reload VM launchd timeout migration`.
- 2026-05-29: 다른 현장 로그에서 `004-refresh-vm-shutdown-timeouts` migration 자체가 update의 첫 `stop-runtime-services` 이후 실행되므로, 이미 loaded 상태인 VM job의 예전 60초 timeout이 첫 stop에 적용될 수 있음을 확인했습니다. Host CLI가 VM launchd `bootout` 전에 VM process에 직접 graceful stop을 요청하고 process 종료를 기다리도록 수정했습니다.
- 이미 `EXT4-fs error`, `Aborting journal`, `Remounting filesystem read-only`가 발생한 VM disk는 이 수정만으로 복구되지 않습니다. Redis backup을 먼저 확인하고 VM disk repair/recreate 또는 재설치를 진행합니다.
