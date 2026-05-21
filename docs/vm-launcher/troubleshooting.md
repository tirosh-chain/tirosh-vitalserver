# VitalServer VM Troubleshooting

PoC와 패키징 과정에서 확인한 문제, 원인, 조치 방법을 모았습니다. 502, cloud-init, bridged entitlement, disk full 같은 운영 이슈를 우선 확인합니다.

## 빠른 증상표

| 증상 | 먼저 볼 항목 |
|---|---|
| boot asset이 없다고 실패 | [`make vm-start`가 boot asset 없음으로 실패](#make-vm-start가-boot-asset-없음으로-실패) |
| VM IP가 `192.168.64.x` | [VM IP가 `192.168.64.x`로 보임](#vm-ip가-19216864x로-보임) |
| bridged mode가 `Killed: 9` | [bridged mode가 `Killed: 9`로 종료됨](#bridged-mode가-killed-9로-종료됨) |
| Docker 설치 중 disk full | [`docker.io` 설치 중 `No space left on device`](#dockerio-설치-중-no-space-left-on-device) |
| apt Release file 시간 오류 | [`apt-get update`가 Release file 시간 오류로 실패](#apt-get-update가-release-file-시간-오류로-실패) |
| cloud-init이 다시 안 돎 | [cloud-init이 bootstrap을 다시 실행하지 않음](#cloud-init이-bootstrap을-다시-실행하지-않음) |
| nginx `502 Bad Gateway` | [nginx가 `502 Bad Gateway`를 반환](#nginx가-502-bad-gateway를-반환) |
| watchdog이 `host-proxy-http-502`를 표시 | [watchdog이 host proxy 502를 복구하지 못함](#watchdog이-host-proxy-502를-복구하지-못함) |
| pkg 설치 후 Manager app이 안 보임 | [pkg 설치 후 `/Applications`에 Manager app이 없음](#pkg-설치-후-applications에-manager-app이-없음) |
| Manager app이 없어 GUI 삭제가 안 됨 | [Manager app 없이 설치물을 제거해야 함](#manager-app-없이-설치물을-제거해야-함) |
| app container health가 오래 starting | [app container가 오래 `health: starting` 상태](#app-container가-오래-health-starting-상태) |
| Ubuntu arm64 `flash-kernel` 실패 | [Ubuntu arm64 cloud image에서 `flash-kernel`이 실패](#ubuntu-arm64-cloud-image에서-flash-kernel이-실패) |
| stale pid file | [`make vm-status`가 stale pid file을 표시](#make-vm-status가-stale-pid-file을-표시) |

## 상세 조치

### `make vm-start`가 boot asset 없음으로 실패

증상:

```text
error: missing file: .../runtime/Image
```

원인:

`vitalserver-vm start`는 VM만 실행합니다. Linux kernel, initrd, root disk, cloud-init seed가 없으면 시작할 수 없습니다.

조치:

```sh
make vm-prepare
make vm-start
```

또는 한 번에:

```sh
make vm-up
```

### VM IP가 `192.168.64.x`로 보임

증상:

cloud-init log에 아래처럼 표시됩니다.

```text
Address 192.168.64.3
Gateway 192.168.64.1
```

원인:

shared/NAT mode에서는 macOS Virtualization NAT DHCP가 VM IP를 부여합니다. 이 IP는 병원 LAN DHCP에서 받은 IP가 아닙니다.

조치:

v1 구조에서는 정상입니다. 사용자는 이 VM IP로 직접 접속하지 않고, target Mac host nginx로 접속합니다.

```text
VRecorder
  -> http://<target Mac LAN IP>/
      -> host nginx
      -> VM shared/NAT IP
```

host nginx를 경유하면 VRecorder 원 IP 보존이 가능합니다.

VM이 병원 LAN IP를 직접 받는 구조를 검증하려면 bridged mode를 사용합니다.

```sh
make vm-interfaces
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

### bridged mode가 `Killed: 9`로 종료됨

증상:

```text
VITALSERVER_VM_HOME=... vitalserver-vm network bridged "en0"
make: *** [vm-network-bridged] Killed: 9
```

원인:

`com.apple.vm.networking` entitlement가 들어간 바이너리를 ad-hoc signing으로 실행하면 macOS가 프로세스를 시작 직후 종료할 수 있습니다. 이 entitlement는 shared/NAT boot smoke test용 `com.apple.security.virtualization`보다 더 제한적입니다.

확인:

```sh
security find-identity -v -p codesigning
codesign -d --entitlements - apps/vitalserver-vm-launcher/.build/release/vitalserver-vm
```

현재 개발 PC에 유효한 codesign identity가 없으면 bridged mode까지 진행할 수 없습니다.

조치:

```sh
VM_BRIDGED_CODESIGN_IDENTITY="Developer ID Application: ..." \
VM_BRIDGED_INTERFACE=en0 \
make vm-up-bridged
```

`make vm-bridged-preflight`는 이 조건을 먼저 확인합니다. codesign identity가 없는 환경에서는 `Killed: 9` 대신 설명 가능한 오류로 중단합니다.

### `docker.io` 설치 중 `No space left on device`

증상:

```text
cannot copy extracted data ... failed to write (No space left on device)
```

원인:

Ubuntu cloud image의 기본 root disk는 Docker, nginx, qemu-user-static, VitalServer image build까지 수행하기에 작습니다.

조치:

`make vm-download`는 VM disk를 기본 `8G`로 확장합니다. 더 크게 만들려면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

이미 디스크 부족으로 망가진 PoC runtime은 재생성합니다.

```sh
make vm-clean
make vm-prepare
```

### `apt-get update`가 Release file 시간 오류로 실패

증상:

```text
Release file ... is not valid yet
```

원인:

VM 첫 부팅 직후 guest 시간이 실제 시간보다 과거일 수 있습니다. cloud-init final 단계가 package install을 먼저 시작하면 apt repository metadata 시간이 미래처럼 보입니다.

조치:

`Support/Guest/bootstrap.sh`는 `apt-get update` 전에 `systemd-timesyncd`를 재시작하고 NTP 동기화를 기다립니다.

수동 확인:

```sh
timedatectl
timedatectl show -p NTPSynchronized --value
```

### cloud-init이 bootstrap을 다시 실행하지 않음

증상:

`seed.iso`를 다시 만들어도 `/mnt/tirosh/deploy/bootstrap.sh`가 실행되지 않습니다.

원인:

cloud-init은 `instance-id`를 기준으로 이미 처리한 instance인지 판단합니다. 같은 instance-id를 재사용하면 초기화 스크립트를 다시 실행하지 않을 수 있습니다.

조치:

`make vm-cloud-init`은 기본적으로 새 instance-id를 생성합니다. 수동으로 지정하려면:

```sh
uv run --project packages/vm-build vitalserver-vm-build \
  --config apps/vitalserver-vm-launcher/Support/Build/vm-build.toml \
  cloud-init \
  --runtime-dir ~/.tirosh/vitalserver-vm/runtime \
  --instance-id tirosh-site-a-001
```

### nginx가 `502 Bad Gateway`를 반환

증상:

```sh
curl -I http://<vm-ip>/
```

결과가 `502 Bad Gateway`입니다.

원인:

VM 내부 nginx는 `127.0.0.1:18080`의 VitalServer container로 proxy합니다. app container가 아직 healthy가 아니거나 HTTP worker가 뜨지 않으면 502가 납니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker ps'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
ssh ubuntu@<vm-ip> 'curl -I http://127.0.0.1:18080/'
```

이번 PoC에서는 `VITALSERVER_MIN_CPUS=6` 때문에 upstream VitalServer가 worker를 0개만 만들었습니다.

```js
numCPUs = os.cpus().length - 6
```

worker가 없으면 master process만 살아 있고 HTTP listener가 없어 nginx가 502를 냅니다.

조치:

`VITALSERVER_MIN_CPUS` 기본값을 `8`로 두어 최소 worker 2개가 뜨게 했습니다.

### watchdog이 host proxy 502를 복구하지 못함

증상:

```text
watchdog recovery started: host-proxy-http-failed, guest-http-missing-vm-ip
Failure reasons: host-proxy-http-502, guest-http-missing-vm-ip
```

또는 recovery 이후 아래처럼 남습니다.

```text
watchdog recovery failed: host-proxy-http-502
```

원인:

`guest-http-missing-vm-ip`는 VM 첫 부팅 중 아직 `/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip`가 없을 때 나올 수 있습니다. 이후 VM IP가 생겼는데도 `host-proxy-http-502`가 계속 남으면 host nginx proxy 쪽을 봅니다.

이번 사례에서는 guest VM IP는 생성됐지만, 설치된 host nginx가 port 80을 bind하지 못했습니다.

```text
nginx: [emerg] bind() to 0.0.0.0:80 failed (48: Address already in use)
```

확인:

```sh
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip"
cat "/Library/Application Support/TiroshVitalServer/vm/logs/proxy.err.log"
sudo lsof -nP -iTCP:80 -sTCP:LISTEN
```

조치:

port 80을 점유한 기존 nginx 또는 다른 web server를 중지한 뒤 proxy LaunchDaemon을 다시 시작합니다.

Manager app이 열리는 상태라면 `Repair Proxy` 버튼을 사용할 수 있습니다. 이 버튼은 관리자 승인을 받은 뒤 configured proxy port를 점유한 `nginx` listener를 종료하고 `com.tirosh.vitalserver-proxy`를 다시 시작합니다. `nginx`가 아닌 프로세스가 port를 점유한 경우에는 자동 종료하지 않고 로그에 표시합니다.

```sh
sudo launchctl kickstart -k system/com.tirosh.vitalserver-proxy
```

개발용 host proxy가 남아 있는 경우에는 repository에서 아래 명령으로 정리합니다.

```sh
make proxy-stop-orphans
```

최신 runtime은 host proxy health가 실패할 때 `proxy-port-80-in-use-by-...` 형태의 failure reason도 같이 기록합니다.

### pkg 설치 후 `/Applications`에 Manager app이 없음

증상:

```sh
ls "/Applications/Tirosh VitalServer Manager.app"
```

결과가 `No such file or directory`입니다.

확인:

```sh
pkgutil --files com.tirosh.vitalserver.vm | grep "Tirosh VitalServer Manager.app"
pkgutil --payload-files dist/TiroshVitalServerVM-0.1.0.pkg | grep "Tirosh VitalServer Manager.app"
```

원인:

payload에는 app bundle이 있어도 macOS Installer가 bundle을 relocatable component로 취급하면 `/Applications`가 아닌 이전 위치를 참고할 수 있습니다. 제품 package에서는 Manager app이 반드시 `/Applications`에 설치되어야 하므로 relocation을 꺼야 합니다.

조치:

`make vm-pkg`는 `Support/Packaging/components.plist`를 `pkgbuild --component-plist`에 넘깁니다. 여기서 `BundleIsRelocatable=false`를 명시합니다.

```text
Applications/Tirosh VitalServer Manager.app
  BundleIsRelocatable = false
```

`postinstall`도 `/Applications/Tirosh VitalServer Manager.app`이 없으면 실패하도록 검증합니다. 이 증상이 보이면 최신 package를 다시 빌드하고 재설치합니다.

### Manager app 없이 설치물을 제거해야 함

증상:

`/Applications/Tirosh VitalServer Manager.app`이 없어서 Manager app의 Uninstall 버튼을 사용할 수 없습니다. 하지만 package receipt, LaunchDaemon, runtime files는 남아 있을 수 있습니다.

확인:

```sh
pkgutil --pkgs | grep com.tirosh.vitalserver.vm
ls -l /usr/local/bin/tirosh-vitalserver-uninstall
ls -ld "/Library/Application Support/TiroshVitalServer"
```

조치:

설치된 CLI uninstaller가 남아 있으면 그걸 사용합니다. 기본 제거는 `.vital` 파일 경로와 backups를 보존합니다.

```sh
sudo tirosh-vitalserver-uninstall
```

테스트 설치물을 완전히 지워야 하면 clean 제거를 사용합니다. 이 옵션은 backups와 설정된 vital files directory까지 삭제할 수 있으므로 실제 데이터가 있는 환경에서는 먼저 경로를 확인합니다.

```sh
sudo tirosh-vitalserver-uninstall --clean
```

개발 repo에서 반복 설치/삭제 중이면 같은 제거 스크립트를 감싼 target을 사용할 수 있습니다.

```sh
make vm-pkg-uninstall-dev
```

제거 후에는 아래 항목들이 사라졌는지 확인합니다.

```sh
pkgutil --pkgs | grep com.tirosh.vitalserver.vm
ls -l /usr/local/bin/tirosh-vitalserver-uninstall /usr/local/bin/vitalserver-vm
ls -ld "/Library/Application Support/TiroshVitalServer"
ls -ld "/Applications/Tirosh VitalServer Manager.app"
```

정상 로그:

```text
worker:1 is forked
worker:2 is forked
worker:1 is listening
worker:2 is listening
```

정상 응답:

```text
HTTP/1.1 302 Found
Location: /check
```

### app container가 오래 `health: starting` 상태

증상:

```text
vitalserver-app-1   Up ... (health: starting)
```

원인:

Apple Silicon Linux guest에서 VitalServer는 `linux/amd64` Node 12 image를 qemu-user-static으로 실행합니다. 첫 build/pull 직후에는 시작이 느릴 수 있습니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker inspect -f "{{json .State.Health}}" vitalserver-app-1'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
```

worker가 `listening` 상태까지 갔는지 확인합니다.

### Ubuntu arm64 cloud image에서 `flash-kernel`이 실패

증상:

```text
Unsupported platform ''.
dpkg: error processing package flash-kernel (--configure)
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

원인:

Ubuntu arm64 cloud image에는 `flash-kernel`이 포함될 수 있습니다. 하지만 이 VM은 Apple Virtualization launcher가 macOS에서 kernel/initrd를 직접 지정해 부팅하므로 guest 안의 `flash-kernel`이 필요하지 않습니다. 해당 hook이 실행되면 현재 VM platform을 인식하지 못하고 apt/dpkg 흐름을 막을 수 있습니다.

조치:

guest `bootstrap.sh`에서 `flash-kernel` hook을 비활성화하고 `flash-kernel` 패키지를 제거한 뒤 `dpkg --configure -a`로 package state를 복구합니다.

### `make vm-status`가 stale pid file을 표시

증상:

```text
stale pid file: .../run/vitalserver-vm.pid
```

원인:

VM process가 이미 종료되었지만 pid file이 남아 있습니다. sandbox 안에서 실행하면 `~/.tirosh` 아래 pid file 삭제가 막혀 stale이 계속 보일 수 있습니다.

조치:

일반 shell에서 다시 실행하면 stale pid file이 정리됩니다.

```sh
make vm-status
make vm-status
```

첫 번째 호출에서 stale을 감지하고, 두 번째 호출에서 `stopped`가 보여야 합니다.

## Code Structure

```text
Sources/VitalServerVMLauncher/
  main.swift

  CLI/
    Command.swift
    Launcher.swift
    LauncherError.swift

  Runtime/
    Constants.swift
    LauncherPaths.swift
    ProcessState.swift

  VirtualMachine/
    VMRuntimeConfig.swift
    VMConfigurationFactory.swift
    VirtualMachineDelegate.swift
```

## References

- Apple Developer: Running Linux in a Virtual Machine
- Apple Developer: `VZVirtualMachineConfiguration`
- Apple Developer: `VZBridgedNetworkDeviceAttachment`
