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
| Redis가 `exec format error`로 재시작됨 | [Redis가 `exec format error`를 출력함](#redis가-exec-format-error를-출력함) |
| Redis UI가 template fetch 오류를 표시 | [Redis UI가 `failed to fetch html template`을 표시](#redis-ui가-failed-to-fetch-html-template을-표시) |
| Service health가 302를 Reachable로 표시 | [HTTP 302가 Reachable로 표시됨](#http-302가-reachable로-표시됨) |
| bundle update가 오래 멈춘 것처럼 보임 | [bundle update가 health wait 또는 rollback에서 오래 멈춤](#bundle-update가-health-wait-또는-rollback에서-오래-멈춤) |
| update 후 Redis가 `exec format error` | [update 후 Redis가 `exec format error`로 실패](#update-후-redis가-exec-format-error로-실패) |
| Redis가 AOF 오류로 재시작 반복 | [Redis AOF 손상으로 runtime health가 회복되지 않음](#redis-aof-손상으로-runtime-health가-회복되지-않음) |
| VM IP가 계속 `Waiting` | [설치된 runtime binary에 virtualization entitlement가 없음](#설치된-runtime-binary에-virtualization-entitlement가-없음) |
| pkg 설치 후 Helper app이 안 보임 | [pkg 설치 후 `/Applications`에 Helper app이 없음](#pkg-설치-후-applications에-helper-app이-없음) |
| Helper app이 없어 GUI 삭제가 안 됨 | [Helper app 없이 설치물을 제거해야 함](#helper-app-없이-설치물을-제거해야-함) |
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

Ubuntu cloud image의 기본 root disk는 Docker, Compose, nginx, guest systemd unit, VitalServer image 준비까지 수행하기에 작습니다.

조치:

`make vm-download`는 VM disk를 기본 `4G`(4 GiB)로 확장합니다. 더 크게 만들려면:

```sh
VM_ROOTFS_SIZE=32G make vm-download
```

`VM_ROOTFS_SIZE`의 `G` suffix는 build tool 입력 형식이며 GiB 기준으로 해석합니다. 예를 들어 `32G`는 32 GiB root disk target size입니다.

이미 디스크 부족으로 망가진 PoC runtime은 재생성합니다.

```sh
make vm-clean
make vm-prepare
```

### golden rootfs 준비 중 `apt-get update`가 Release file 시간 오류로 실패

증상:

```text
Release file ... is not valid yet
```

원인:

golden rootfs 준비용 VM의 첫 부팅 직후 guest 시간이 실제 시간보다 과거일 수 있습니다. cloud-init final 단계가 package install을 먼저 시작하면 apt repository metadata 시간이 미래처럼 보입니다.

조치:

`Support/Guest/prepare-airgap-rootfs.sh`는 build-machine에서만 apt를 실행합니다. target Mac의 `bootstrap.sh`는 air-gapped 계약 때문에 apt를 실행하지 않습니다. 이 오류가 나면 golden rootfs 준비 VM의 시간 동기화 상태를 먼저 확인합니다.

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

VM 내부 Compose edge nginx는 `app:80`의 VitalServer container로 proxy합니다. app container가 아직 healthy가 아니거나 HTTP worker가 뜨지 않으면 502가 납니다.

확인:

```sh
ssh ubuntu@<vm-ip> 'sudo docker ps'
ssh ubuntu@<vm-ip> 'sudo docker logs --tail 120 vitalserver-app-1'
ssh ubuntu@<vm-ip> 'sudo docker compose --project-name vitalserver -f /mnt/tirosh/deploy/compose.yaml ps'
ssh ubuntu@<vm-ip> 'curl -I http://127.0.0.1/'
```

이번 PoC에서는 `VITALSERVER_MIN_CPUS=6` 때문에 upstream VitalServer가 worker를 0개만 만들었습니다.

```js
numCPUs = os.cpus().length - 6
```

### Redis가 `exec format error`를 출력함

증상:

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

원인:

guest VM은 arm64 Ubuntu인데 Docker image bundle이나 compose 설정이 amd64 image를 강제로 사용하면 container entrypoint를 실행하지 못합니다. 이 경우 Redis뿐 아니라 다른 container도 같은 방식으로 실패할 수 있습니다.

조치:

- Docker image bundle은 `linux/arm64`로 생성합니다.
- Compose에서 특정 service에 `platform: linux/amd64`를 강제하지 않습니다.
- Redis Commander처럼 운영 UI container도 `latest` 대신 pinned multi-arch image를 사용합니다.

현재 기준:

```text
docker image platform: linux/arm64
Redis Commander: ghcr.io/joeferner/redis-commander:0.9.0
```

이미 잘못된 bundle을 적용했다면 수정된 bundle을 다시 적용하거나 runtime을 재설치한 뒤 health를 확인합니다.

### Redis UI가 `failed to fetch html template`을 표시

증상:

```text
failed to fetch html template templates/editBranch.ejs
```

원인:

Redis Commander는 browser에서 `templates/*.ejs` 같은 상대 경로를 가져옵니다. `/redis-ui/` 아래에 붙일 때 nginx가 prefix를 그대로 upstream에 넘기면 Redis Commander의 정적 template 경로와 어긋날 수 있습니다.

조치:

guest edge nginx는 `/redis-ui/` prefix를 제거해서 Redis Commander upstream에는 root path로 보이게 합니다.

```nginx
location = /redis-ui {
  return 301 /redis-ui/;
}

location /redis-ui/ {
  proxy_pass http://redis-ui:8081/;
}
```

Compose에는 `URL_PREFIX=/redis-ui`를 넣지 않습니다. prefix는 edge nginx가 처리하고 Redis Commander는 root app처럼 실행합니다.

### HTTP 302가 Reachable로 표시됨

증상:

Helper app의 Service health에서 VitalServer 또는 Network access가 `HTTP 302`인데도 `Reachable`로 표시됩니다.

원인:

`/` 요청은 로그인 화면 등으로 redirect될 수 있습니다. Redirect 자체는 proxy가 살아 있다는 신호일 수 있지만, 운영 health를 의미하지는 않습니다.

조치:

health check는 `/` 대신 VitalServer readiness endpoint인 `/check`를 사용하고, 성공 상태는 2xx만 인정합니다. 브라우저로 여는 URL은 여전히 `/`를 사용합니다.

worker가 없으면 master process만 살아 있고 HTTP listener가 없어 nginx가 502를 냅니다.

조치:

`VITALSERVER_MIN_CPUS` 기본값을 `8`로 두어 최소 worker 2개가 뜨게 했습니다.

### bundle update가 health wait 또는 rollback에서 오래 멈춤

증상:

Helper app에서 `Apply Bundle`을 실행한 뒤 화면상으로 업데이트가 5분 이상 진행되지 않는 것처럼 보입니다. Logs 탭에도 최신 진행 상태가 바로 보이지 않거나, command log가 마지막 줄에서 끊긴 것처럼 보일 수 있습니다.

원인:

bundle apply는 아래 순서로 동작합니다.

```text
verify bundle
stage bundle
create managed backup
stop runtime services
replace bundle artifacts
start runtime services
wait for runtime health
rollback if health does not recover
wait for rollback health
```

runtime health wait는 의도적으로 길게 잡혀 있습니다. VM 부팅, Docker compose 재시작, VitalServer app worker 준비가 모두 끝나야 하기 때문입니다. 다만 health wait 중 내부 서비스가 계속 실패하면, 사용자는 멈춘 것으로 느낄 수 있습니다.

확인:

```sh
tail -f /private/tmp/tirosh-vitalserver-manager-command.log
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/container-logs.log"
```

최신 Helper app은 command log를 Logs 탭에서 실시간 갱신하고, runtime health wait 중에도 `waiting for runtime health reasons=...` 형태의 진행 로그를 남깁니다. 이전 버전에서 시작한 update/rollback 작업에는 이 개선이 적용되지 않습니다.

Update 탭에서는 적용 중인 현재 step과 Command log tail을 함께 표시합니다. 화면이 `Applying update bundle...` 한 줄에서 오래 멈춰 보이면 먼저 `Command log` source를 확인합니다.

조치:

먼저 command log와 container log에서 실제 실패 원인을 확인합니다. update가 이미 rollback 단계에 들어간 경우에는 중간에 강제 종료하면 runtime이 반쯤 교체된 상태로 남을 수 있으므로, 가능한 한 rollback timeout이 끝날 때까지 기다립니다. 반복적으로 health가 회복되지 않으면 새 bundle 또는 재설치로 복구합니다.

Helper app의 Advanced > Recovery operations에는 `Repair Data Store`가 있습니다. 이 작업은 VM 내부에 복구 요청 파일을 만들고, guest systemd path unit이 Redis AOF 검사/복구와 container 재시작을 수행하게 합니다. update 실패 후 Redis 또는 VitalServer health가 회복되지 않을 때 먼저 시도합니다.

Update 과정의 전체 계약, 보존/변경 범위, 0.1.3 실패 분석은 [Update](update.md)를 봅니다.

### update 후 bootstrap이 `missing runtime package`로 실패

증상:

```text
error: missing runtime package in air-gapped rootfs
Required commands/services: curl, docker, docker compose, avahi-daemon, growpart.
```

원인:

일반 update bundle은 `rootfs-base.raw.gz`를 교체하지만, 이미 설치되어 실행 중인 mutable disk인 `vm-disk.img`는 보존합니다. 따라서 기존 `vm-disk.img` 안에 Docker/Compose/Avahi/growpart 같은 runtime package가 빠져 있으면, guest deploy나 cloud-init seed만 갱신해도 bootstrap이 성공할 수 없습니다.

조치:

같은 bundle을 반복 적용하지 말고, 새 package 재설치 또는 별도 VM/rootfs replacement 흐름으로 복구합니다. 운영 데이터 보존 범위는 [Update](update.md)의 `0.1.4 update에서 다시 실패하는 경우`를 확인합니다.

### update 후 Redis가 `exec format error`로 실패

증상:

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

동시에 runtime status에는 아래처럼 표시될 수 있습니다.

```text
host-proxy-http-502
redis-ui-http-502
swagger-ui-http-502
guest-http-000failed
```

원인:

guest VM architecture와 Docker image architecture가 맞지 않을 때 발생합니다. 단, update bundle 내부 image가 `arm64`로 맞아 있어도 실패할 수 있습니다. update가 `guest-deploy.tar.gz`를 host shared directory에 교체하는 것만으로는 VM 내부 Docker daemon에 새 image가 load되지 않습니다. 최초 설치 때만 cloud-init bootstrap이 image bundle을 load합니다.

확인:

```sh
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/container-logs.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/bootstrap.log"
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
```

bundle 내부 image architecture 확인:

```sh
tar -xOf dist/update-bundles/update-bundle-<version>/guest-deploy.tar.gz \
  deploy/docker-images/vitalserver-images.tar.gz > /tmp/vitalserver-images.tar.gz

tar -xOf /tmp/vitalserver-images.tar.gz manifest.json
```

조치:

`guest-deploy`나 Docker image bundle을 바꾸는 update는 반드시 guest activation까지 진행되어야 합니다. 현재 update bundle은 기본 migration으로 cloud-init seed를 갱신하고, 새 runtime은 `activate-update.request`를 통해 VM 안에서 Docker image bundle을 다시 load하고 기존 container를 recreate합니다. 단순히 host shared directory만 교체되면 이전 wrong-arch image cache를 계속 사용할 수 있습니다.

0.1.3에서 확인한 상세 원인은 [Update 문서의 0.1.3 실패 분석](update.md#013-실패-분석)에 남겨둡니다.

### VM은 부팅됐지만 VM IP가 계속 Waiting

증상:

Helper Status에서 VM service와 watchdog은 running인데 VM IP, VitalServer, Redis가 계속 Waiting으로 표시됩니다.

확인:

```sh
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/logs/launchd.out.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/logs/launchd.err.log"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/bootstrap.log"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json"
```

원인:

VM 자체는 부팅됐지만 guest bootstrap이 실패하면 `runtime-state.json`이 생성되지 않습니다. 이 경우 UI는 VM IP를 알 수 없어 Waiting으로 남습니다. 한 사례에서는 bootstrap preflight가 arm64 VM에서 `qemu-x86_64-static`을 필수로 요구해 실패했습니다. 현재 container image는 `linux/arm64`로 제공하므로 qemu-user-static은 runtime 필수 조건이 아닙니다.

조치:

수정된 `bootstrap.sh`가 들어간 update bundle을 다시 만들고 적용합니다. 해당 변경은 `guest-deploy.tar.gz`에 포함되며, 기본 migration과 guest activation 경로를 통해 현장 runtime에 반영됩니다.

### Redis AOF 손상으로 runtime health가 회복되지 않음

증상:

bundle update 이후 VitalServer, Network access, Redis UI, Swagger UI가 502 또는 500을 반환하고, Redis container log에 아래 오류가 반복됩니다.

```text
Bad file format reading the append only file
make a backup of your AOF file, then use ./redis-check-aof --fix <filename>
```

원인:

Redis append-only file이 손상되면 Redis가 기동하지 못하고 재시작을 반복합니다. VitalServer app은 Redis에 의존하므로 Redis가 준비되지 않으면 app readiness도 실패하고, host proxy는 최종적으로 502를 반환합니다.

조치:

최신 guest compose는 Redis container 시작 전에 `redis-check-aof`를 실행합니다. AOF가 깨져 있으면 기존 파일을 `.bak.<timestamp>`로 백업한 뒤 `redis-check-aof --fix`를 수행하고 Redis를 시작합니다.

이미 이전 bundle로 update가 진행 중이라면, 실행 중인 old runtime binary에는 이 복구 로직이 없습니다. 현재 apply/rollback 작업이 끝난 뒤 Redis AOF 복구가 포함된 새 bundle을 다시 적용합니다.

최신 runtime에서는 아래 복구 명령도 사용할 수 있습니다.

```sh
sudo vitalserver-vm runtime repair-datastore
```

이 명령은 host에서 `/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore.request`를 만들고, VM 내부의 `tirosh-vitalserver-repair-datastore.path`가 이를 감지해 Redis AOF를 검사/복구합니다. 복구 결과는 아래 파일에 기록됩니다.

```text
/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore-result.json
/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore.log
```

그래도 회복되지 않으면 managed backup rollback을 다시 시도하거나, vital files를 보존한 상태로 runtime을 재설치합니다.

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

`guest-http-missing-vm-ip`는 VM 첫 부팅 중 아직 `/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json`에 VM IP가 기록되지 않았을 때 나올 수 있습니다. legacy fallback으로 `vm-ip` 파일도 볼 수 있습니다. 이후 VM IP가 생겼는데도 `host-proxy-http-502`가 계속 남으면 host nginx proxy 쪽을 봅니다.

이번 사례에서는 guest VM IP는 생성됐지만, 설치된 host nginx가 port 80을 bind하지 못했습니다.

```text
nginx: [emerg] bind() to 0.0.0.0:80 failed (48: Address already in use)
```

확인:

```sh
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip"
cat "/Library/Application Support/TiroshVitalServer/vm/logs/proxy.err.log"
sudo lsof -nP -iTCP:80 -sTCP:LISTEN
```

조치:

port 80을 점유한 기존 nginx 또는 다른 web server를 중지한 뒤 proxy LaunchDaemon을 다시 시작합니다.

Helper app이 열리는 상태라면 `Repair Proxy` 버튼을 사용할 수 있습니다. 이 버튼은 관리자 승인을 받은 뒤 configured proxy port를 점유한 `nginx` listener를 종료하고 `com.tirosh.vitalserver-proxy`를 다시 시작합니다. `nginx`가 아닌 프로세스가 port를 점유한 경우에는 자동 종료하지 않고 로그에 표시합니다.

```sh
sudo launchctl kickstart -k system/com.tirosh.vitalserver-proxy
```

개발용 host proxy가 남아 있는 경우에는 repository에서 아래 명령으로 정리합니다.

```sh
make proxy-stop-orphans
```

최신 runtime은 host proxy health가 실패할 때 `proxy-port-80-in-use-by-...` 형태의 failure reason도 같이 기록합니다.

### 설치된 runtime binary에 virtualization entitlement가 없음

증상:

```text
Runtime state: critical
VM IP: Waiting
Guest HTTP: missing-vm-ip
Host proxy: failed
```

launchd log에는 아래 오류가 남습니다.

```text
The process doesn't have the "com.apple.security.virtualization" entitlement.
Invalid virtual machine configuration.
```

원인:

패키징 중 `vm-golden-rootfs` 준비 과정이 Swift binary를 다시 빌드하면, 앞에서 signing했던 `vitalserver-vm`이 unsigned binary로 덮일 수 있습니다. 이 상태로 `.pkg`에 들어가면 설치된 `/usr/local/bin/vitalserver-vm`이 VM을 띄우지 못하고, guest가 부팅되지 않으므로 runtime state에 VM IP가 기록되지 않습니다.

확인:

```sh
codesign -d --entitlements :- /usr/local/bin/vitalserver-vm 2>&1 | grep com.apple.security.virtualization
sudo launchctl print system/com.tirosh.vitalserver-vm
cat "/Library/Application Support/TiroshVitalServer/vm/logs/launcher.err.log"
```

조치:

`make vm-pkg`는 package root에 binary를 복사하기 직전에 다시 signing하고 entitlement를 검증합니다. 기존에 설치된 잘못된 package는 다시 빌드한 package로 재설치해야 합니다.

### pkg 설치 후 `/Applications`에 Helper app이 없음

증상:

```sh
ls "/Applications/VitalServer Helper.app"
```

결과가 `No such file or directory`입니다.

확인:

```sh
pkgutil --files com.tirosh.vitalserver.vm | grep "VitalServer Helper.app"
pkgutil --payload-files dist/TiroshVitalServerVM-<version>.pkg | grep "VitalServer Helper.app"
```

원인:

payload에는 app bundle이 있어도 macOS Installer가 bundle을 relocatable component로 취급하면 `/Applications`가 아닌 이전 위치를 참고할 수 있습니다. 제품 package에서는 Helper app이 반드시 `/Applications`에 설치되어야 하므로 relocation을 꺼야 합니다.

조치:

`make vm-pkg`는 `Support/Packaging/components.plist`를 `pkgbuild --component-plist`에 넘깁니다. 여기서 `BundleIsRelocatable=false`를 명시합니다.

```text
Applications/VitalServer Helper.app
  BundleIsRelocatable = false
```

`postinstall`도 `/Applications/VitalServer Helper.app`이 없으면 실패하도록 검증합니다. 이 증상이 보이면 최신 package를 다시 빌드하고 재설치합니다.

### Helper app 없이 설치물을 제거해야 함

증상:

`/Applications/VitalServer Helper.app`이 없어서 Helper app의 Uninstall 버튼을 사용할 수 없습니다. 하지만 package receipt, LaunchDaemon, runtime files는 남아 있을 수 있습니다.

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
ls -ld "/Applications/VitalServer Helper.app"
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

Apple Silicon Linux guest에서는 container image도 `linux/arm64`로 맞춥니다. 첫 build/pull 직후에는 Docker image load, Redis healthcheck, VitalServer worker boot 때문에 시작이 느릴 수 있습니다.

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
Sources/RuntimeOrchestrator/
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
