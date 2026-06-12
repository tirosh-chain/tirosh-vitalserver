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

plist 파일만 갱신되어도 이미 loaded 상태인 launchd job에는 즉시 반영되지 않습니다. 아래처럼 plist는 최신 `ExitTimeOut`인데 `launchctl print`의 loaded job은 더 짧은 timeout을 유지할 수 있습니다.

```sh
plutil -p "/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist" | grep ExitTimeOut
launchctl print system/com.tirosh.vitalserver-vm | grep "exit timeout"
```

이 상태에서 update/rollback이 VM을 정지하면 launchd가 예전 timeout 기준으로 VM process를 종료할 수 있고, 그 결과 ext4 journal abort 또는 read-only remount로 이어질 수 있습니다.

이 경우 `vm-disk.img`는 mutable 운영 디스크이므로 managed rollback 대상이 아닙니다. rollback은 app bundle, runtime tools, nginx bundle, guest deploy, rootfs base 같은 교체 가능한 artifact를 복원하지만, 이미 손상된 mutable VM disk를 되돌리지는 않습니다.

2026-06-04 재현에서는 packaging workflow도 원인이 될 수 있음을 확인했습니다. `.tmp/vitalserver-vm-golden/run/vm-lifecycle.json`이 `stopping`인 상태였는데도 `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz`가 생성되어, guest shutdown이 끝났다는 명시적 증명 없이 golden VM disk가 base artifact로 압축되었습니다. `rootfs-ready` marker는 guest 준비가 끝났다는 신호일 뿐 VM disk가 clean shutdown되었다는 신호가 아닙니다.

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

정상적으로 갱신된 상태에서는 plist가 `ExitTimeOut => 900`이고, loaded job도 `exit timeout = 900`을 사용해야 합니다.

조치:

최신 runtime은 VM launchd `ExitTimeOut`을 900초로 늘리고, guest Compose stop timeout과 `sync`를 명시합니다. update bundle에는 `004-refresh-vm-shutdown-timeouts` migration이 포함되어 기존 설치본의 VM launchd plist를 갱신하고, loaded 상태인 VM launchd job을 unload하여 다음 start에서 갱신된 timeout이 적용되게 합니다.

2026-05-29 이후 runtime은 update의 첫 `stop-runtime-services`에서도 launchd timeout만 믿지 않습니다. VM service를 `bootout`하기 전에 `vitalserver-vm.pid`가 가리키는 VM process에 먼저 `SIGTERM`을 보내고, VM process의 signal handler가 Virtualization `requestStop()`을 수행해 guest shutdown과 disk flush를 끝낼 때까지 기다립니다. 2026-06-01 이후 이 대기 시간은 900초입니다. 따라서 migration이 아직 실행되기 전 loaded launchd job이 예전 `exit timeout = 60`을 들고 있어도 update 첫 stop이 곧바로 강제 종료로 이어지지 않아야 합니다.

guest가 filesystem flush/unmount를 완료하지 못하거나 initrd shutdown에서 특정 프로세스를 기다리며 poweroff를 끝내지 못하는 경우도 있습니다. 이때 host는 guest log marker를 근거로 disk-safe 상태를 추정하지 않습니다. VM process가 timeout 안에 종료되지 않으면 update를 실패로 남기고, disk와 Redis backup 보존 여부를 확인한 뒤 수동 복구 절차를 선택합니다.

Guest runtime state는 `diskHealth` contract로 root filesystem read-only 여부와 kernel disk error line을 보고합니다. Host health는 fresh `runtime-state.json`에 포함된 이 명시적 contract만 사용해 `guest-filesystem-error`, `guest-filesystem-read-only`, `guest-disk-io`를 판단합니다. Update preflight는 이 오류들이 있으면 update를 진행하지 않고 VM disk repair를 요구해야 합니다.

이미 disk 오류가 발생한 설치본에서는 같은 update bundle을 반복 적용하지 않습니다. 먼저 Redis backup이 남아 있는지 확인하고, 가능한 경우 Redis backup을 보존한 뒤 VM disk 복구 또는 재설치를 진행합니다.

```sh
ls -lh "/Library/Application Support/TiroshVitalServer/backups"
ls -lh "/Library/Application Support/TiroshVitalServer/vm/data/backups" 2>/dev/null || true
```

Helper 0.1.9 이후에는 수동 VM disk repair를 사용할 수 있습니다. 이 작업은 Redis backup을 먼저 시도한 뒤 현재 `vm-disk.img`를 `backups/vm-disk-repair-<timestamp>/` 아래로 보관하고, 설치된 `rootfs-base.raw.gz`에서 새 VM disk를 만든 뒤 runtime services를 다시 시작합니다. VM이 이미 부팅 불가능해서 Redis backup이 실패해도 기존 VM disk archive는 남깁니다.

```sh
sudo /usr/local/bin/vitalserver-vm runtime repair-vm-disk
```

Repair flow는 일반 update stop과 다릅니다. 손상된 VM은 graceful stop이 실패할 수 있으므로 repair는 먼저 정상 stop을 시도하고, 실패하면 VM disk 교체를 위해 VM process를 종료한 뒤 launchd service를 unload합니다. 이 강제 종료 경로는 손상된 disk를 계속 운영하기 위한 경로가 아니라, 기존 disk를 archive하고 새 disk로 교체하기 위한 복구 전용 경로입니다.

주의: VM 내부 Redis volume과 Docker runtime state는 새 disk로 교체됩니다. Redis 데이터가 필요하면 Redis backup을 확인하고 복원 절차를 진행합니다. 호스트의 configured Vital files directory는 VM disk 밖에 있으므로 보존됩니다.

Packaging에서는 `rootfs-base.raw.gz`를 만들기 전에 golden VM lifecycle state가 `stopped`인지 확인해야 합니다. lifecycle document가 없거나 `stopping`, `running`, `failed`이면 base artifact 생성을 중단합니다. Host에 `e2fsck`가 없는 macOS build host에서는 ext4 fsck를 직접 수행하기 어렵기 때문에, 최소한 VM lifecycle stopped proof 없이 rootfs를 압축하지 않는 것이 필수 예방선입니다.

`stopped` lifecycle이라도 `terminalReason`이 남아 있으면 clean shutdown proof로 보지 않습니다. `guest-kernel-panic`, `guest-filesystem-read-only`, `disk-attachment-invalid` 같은 terminal failure가 기록된 VM disk는 base artifact source가 아니며, packaging 단계에서 거부해야 합니다. `rootfs-base.raw.gz` 생성 직후에는 gzip stream을 끝까지 읽어 CRC/EOF와 uncompressed size를 검증합니다. 이 검증은 ext4 논리 오류를 대체하지 않지만, partial/corrupt gzip이 installer package에 들어가는 경로를 막는 최소 산출물 검증입니다.

같은 `VM_HOME`을 사용하는 VM process가 2개 이상 떠 있으면 같은 `vm-disk.img`에 동시 접근할 수 있고, golden rootfs도 운영 VM disk처럼 ext4 journal 손상으로 이어질 수 있습니다. local packaging의 detached VM start는 pid file 하나만 신뢰하지 않고 process table에서 같은 `VITALSERVER_VM_HOME`을 가진 `vitalserver-vm start` process를 확인해야 합니다. 중복 process가 있으면 새 VM을 시작하지 않고 build를 실패시켜야 합니다.

2026-06-08 local packaging 재현에서는 `.tmp/vitalserver-vm-golden/logs/launcher.log`에 아래 계열의 로그가 남았습니다.

```text
EXT4-fs error (device vda1): htree_dirblock_to_tree: bad entry in directory
Aborting journal on device vda1-8.
EXT4-fs (vda1): Remounting filesystem read-only
Input/output error
cloud-init.target: Failed with result 'dependency'
cloud-final.service: Failed with result 'exit-code'
```

이 로그는 cloud-init 자체 문제로 보지 않습니다. 같은 build host에서 process table을 확인했을 때 같은 `.tmp/vitalserver-vm-golden` `VITALSERVER_VM_HOME`을 가진 `vitalserver-vm start` process가 2개 떠 있었고, 둘 다 같은 `vm-disk.img`에 접근할 수 있는 상태였습니다. 이 경우 guest filesystem은 정상적인 single-writer disk contract를 잃고, golden rootfs 준비 중이어도 운영 VM disk와 같은 방식으로 journal abort/read-only remount가 발생할 수 있습니다.

pid file은 이 상황의 충분한 lock이 아닙니다. 첫 VM process가 pid file을 쓰기 전 두 번째 start가 들어오거나, 두 번째 process가 pid file을 덮어쓰면 pid file만 보는 preflight는 중복 process를 놓칠 수 있습니다. detached VM start는 host process table에서 같은 `VITALSERVER_VM_HOME`을 명시적으로 확인해야 하며, process table을 읽지 못하는 경우도 안전한 empty state로 취급하지 않고 실패해야 합니다.

이 재현에서는 golden cache를 삭제한 뒤 rootfs를 다시 만들었습니다. clean rebuild 이후 `launcher.log`에는 정상 mount/shutdown 로그만 남았고, `EXT4-fs error`, `Input/output error`, read-only remount 패턴은 재발하지 않았습니다. package용 rootfs는 Docker image load와 guest provisioning 여유를 위해 기본 크기를 `8G`로 올렸고, `4G` 요청은 build planning 단계에서 거부합니다.

`internal/vm/wait/rootfs-ready`가 위와 같은 terminal guest failure를 보지 못하면 `rootfs-ready` marker가 절대 생성되지 않는 상태에서도 timeout까지 대기합니다. wait 단계는 marker만 기다리지 않고 VM lifecycle `failed` state와 launcher log의 ext4/kernel panic/soft lockup 패턴을 확인해 즉시 실패해야 합니다. 또한 detached VM start는 `launcher.log`를 append하지 않고 run마다 새로 시작해야 합니다. 과거 failure log가 다음 build의 판단 근거가 되면 stale observability가 현재 상태처럼 보이기 때문입니다.

VM disk repair가 `Archiving current VM disk`에 머문 것처럼 보이면 실제로는 archive 이전 stop 단계에서 VM service 또는 VM process stop이 실패했을 수 있습니다. repair workflow는 service stop 실패를 `critical` runtime status로 기록한 뒤 중단해야 하며, 이 상태에서 현재 disk를 이동하거나 replacement disk를 start하지 않습니다.

운영 판단:

- `activate-update.log`에 `guest update activation completed`가 있어도 이후 health check가 실패할 수 있습니다. 이 경우 update payload가 아니라 VM disk 상태를 먼저 봅니다.
- `EXT4-fs error`, `Remounting filesystem read-only`, `fsck is recommended`가 보이면 일반 rollback보다 VM disk repair/recreate가 우선입니다.
- `vm-disk.img`는 Redis volume과 Docker runtime state를 포함할 수 있으므로 clean uninstall 전에 Redis backup 경로를 확인합니다.

## Follow-up

- 2026-05-28: 재현 환경에서 plist 파일은 `ExitTimeOut=300`이었지만 `launchctl print system/com.tirosh.vitalserver-vm`의 loaded job은 `exit timeout = 60`을 유지하고 있었습니다. 원인은 migration이 plist만 갱신하고 loaded launchd job을 reload/unload하지 않은 것입니다.
- 2026-05-28: `004-refresh-vm-shutdown-timeouts` migration이 VM launchd job을 `bootout`하도록 수정했습니다. 다음 runtime start에서 launchd가 plist를 다시 읽어 갱신된 `ExitTimeOut`을 적용합니다. Fix: `2aaef21 fix: reload VM launchd timeout migration`.
- 2026-05-29: 다른 현장 로그에서 `004-refresh-vm-shutdown-timeouts` migration 자체가 update의 첫 `stop-runtime-services` 이후 실행되므로, 이미 loaded 상태인 VM job의 예전 60초 timeout이 첫 stop에 적용될 수 있음을 확인했습니다. Host CLI가 VM launchd `bootout` 전에 VM process에 직접 graceful stop을 요청하고 process 종료를 기다리도록 수정했습니다.
- 2026-06-01: guest shutdown이 `systemd-resolved`/initrd finalization에서 330초보다 오래 걸리는 케이스를 확인했습니다. Host CLI와 VM launchd timeout을 900초로 늘렸고, disk-safe marker 기반 force stop fallback은 사용하지 않는 원칙을 문서화했습니다.
- 2026-06-04: golden VM lifecycle이 `stopping`인데 `rootfs-base.raw.gz`가 생성된 build workflow 문제를 확인했습니다. `rootfs-base` 생성은 golden VM lifecycle `stopped` proof를 요구하도록 변경하고, fresh guest runtime state의 `diskHealth` contract로 update preflight가 VM disk repair 대상 오류를 차단하도록 했습니다.
- 2026-06-08: fresh install에서 `EXT4-fs error`, cloud-init `Input/output error`, guest kernel panic이 함께 나타나는 로그를 확인했습니다. packaging은 stopped lifecycle에 terminal failure reason이 없는지 확인하고, rootfs gzip 산출물을 생성 직후 검증합니다. VM disk repair는 runtime service stop 실패를 critical status로 남겨 `Archiving current VM disk`가 마지막 상태처럼 남지 않게 합니다.
- 2026-06-08: local `vm-golden/logs/launcher.log`에서 golden rootfs 준비 중 `EXT4-fs error`, `Aborting journal`, read-only remount가 발생했고, 동시에 같은 `.tmp/vitalserver-vm-golden` `VITALSERVER_VM_HOME`을 쓰는 VM process가 2개 떠 있음을 확인했습니다. detached VM start는 same VM_HOME process scan으로 중복 start를 거부하고, package용 rootfs 기본 크기는 `8G`로 올립니다.
- 2026-06-09: `wait/rootfs-ready`가 guest kernel panic/soft lockup 이후에도 marker만 기다리며 timeout까지 멈춘 사례를 확인했습니다. wait 단계는 VM lifecycle failure와 launcher log terminal pattern을 즉시 실패로 처리하고, detached start는 launcher log를 append하지 않고 새 run log로 시작합니다.
- 2026-06-11: golden rootfs rebuild 중 `apt-get`/`dpkg`가 `Illegal instruction`, `Segmentation fault`, `systemd` shared library error를 내고 이후 `Kernel panic - not syncing: Attempted to kill init!`으로 종료되는 사례를 확인했습니다. `wait/rootfs-ready`는 `Kernel panic - not syncing`과 `Attempted to kill init`을 terminal launcher log pattern으로 처리해야 하며, rootfs marker 대기 timeout은 HTTP readiness timeout과 분리합니다.
- 2026-06-12: golden rootfs compile 중 guest script가 시작되기 전 `EXT4-fs error ... checksum invalid`,
  `Aborting journal`, `Remounting filesystem read-only`가 발생하고 panic stack이 `hwrng` /
  `virtio_read [virtio_rng]`로 끝나는 사례를 확인했습니다. 이 경우 `Remounting filesystem read-only`는
  결과 신호이고, `EXT4-fs error`와 `virtio_rng` panic stack을 먼저 봅니다. VM configuration은
  product compile 안정성을 위해 `VZVirtioEntropyDeviceConfiguration`을 붙이지 않습니다.
- 2026-06-12: entropy device 제거 이후에도 Docker daemon start에서
  `Internal error: Oops`, `Kernel panic - not syncing`, scheduler stack corruption이 반복되는 사례를
  확인했습니다. `docker.io` 설치 중 service auto-start는 `policy-rc.d`로 막고, rootfs smoke의
  `docker-service` stage에서 명시적으로 Docker를 시작해 실패 지점을 분리합니다. 같은 지점에서
  반복 panic하면 rootfs script 순서가 아니라 Ubuntu cloud image serial/kernel 조합 문제로 보고
  `guest.ubuntu.base_url`과 `guest.ubuntu.apt_snapshot`을 함께 올립니다.
- 이미 `EXT4-fs error`, `Aborting journal`, `Remounting filesystem read-only`가 발생한 VM disk는 이 수정만으로 복구되지 않습니다. Redis backup을 먼저 확인하고 VM disk repair/recreate 또는 재설치를 진행합니다.
