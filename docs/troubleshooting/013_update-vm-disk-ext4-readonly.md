# 013 update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨

> ID: TS-013  
> Category: Update  
> Owner: macOS runtime  
> Status: active

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

이 경우 `vm-disk.img`는 mutable 운영 디스크이므로 managed rollback 대상이 아닙니다. rollback은 app bundle, runtime tools, nginx bundle, guest deploy, rootfs base 같은 교체 가능한 artifact를 복원하지만, 이미 손상된 mutable VM disk를 되돌리지는 않습니다.

확인:

```sh
tail -n 300 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.out.log"
tail -n 100 "/Library/Application Support/TiroshVitalServer/logs/runtime/launchd.err.log"
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/guest/activate-update.log"
```

조치:

최신 runtime은 VM launchd `ExitTimeOut`을 300초로 늘리고, guest Compose stop timeout과 `sync`를 명시합니다. update bundle에는 `004-refresh-vm-shutdown-timeouts` migration이 포함되어 기존 설치본의 VM launchd plist도 갱신합니다.

이미 disk 오류가 발생한 설치본에서는 같은 update bundle을 반복 적용하지 않습니다. 먼저 Redis backup이 남아 있는지 확인하고, 가능한 경우 Redis backup을 보존한 뒤 VM disk 복구 또는 재설치를 진행합니다.

```sh
ls -lh "/Library/Application Support/TiroshVitalServer/backups"
ls -lh "/Library/Application Support/TiroshVitalServer/vm/data/backups" 2>/dev/null || true
```

운영 판단:

- `activate-update.log`에 `guest update activation completed`가 있어도 이후 health check가 실패할 수 있습니다. 이 경우 update payload가 아니라 VM disk 상태를 먼저 봅니다.
- `EXT4-fs error`, `Remounting filesystem read-only`, `fsck is recommended`가 보이면 일반 rollback보다 VM disk repair/recreate가 우선입니다.
- `vm-disk.img`는 Redis volume과 Docker runtime state를 포함할 수 있으므로 clean uninstall 전에 Redis backup 경로를 확인합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
