# VitalServer Helper Update

VitalServer Helper의 update bundle이 무엇을 바꾸고, 무엇을 보존하며, 실패했을 때 어디를 봐야 하는지 정리합니다.

## 이 문서에서 바로 알아야 할 것

| 질문 | 답 |
|---|---|
| update 입력 단위는? | `dist/update-bundles/update-bundle-<version>/` directory |
| 현장 적용 UI는? | Helper app의 Update 탭 |
| CLI backend는? | `/usr/local/bin/vitalserver-vm runtime apply-bundle` |
| 검증 기준은? | `manifest.json`, `checksums.txt`, artifact sha256/size |
| mutable VM disk는 교체하나? | 기본적으로 교체하지 않는다 |
| Redis/Vital files 데이터는 보존하나? | 보존 대상이다 |
| Docker image bundle만 바꾸면 container가 자동 갱신되나? | update 단계에서 guest-side activation을 실행해야 한다 |
| `bootstrap.sh` 수정은 update bundle로 반영되나? | 된다. `guest-deploy.tar.gz`에 포함되고 기본 migration/activation 경로로 반영된다 |
| 실패 시 자동 rollback하나? | apply 중 health check 실패 시 managed backup으로 rollback을 시도한다 |

## Update Bundle 구조

일반 update bundle은 설치 파일 전체가 아니라 교체 가능한 artifact 묶음입니다.

```text
dist/update-bundles/update-bundle-<version>/
  manifest.json
  checksums.txt
  signature
  rootfs-base.raw.gz
  app-bundle.tar.gz
  runtime-tools.tar.gz
  nginx-bundle.tar.gz
  guest-deploy.tar.gz
  migrations/
```

각 artifact의 의미는 아래와 같습니다.

| artifact | 대상 | 적용 결과 |
|---|---|---|
| `app-bundle.tar.gz` | `/Applications/VitalServer Helper.app` | Helper UI 교체. 적용 중 실행 중인 app과 충돌할 수 있어 재실행이 필요 |
| `runtime-tools.tar.gz` | `/usr/local/bin` | `vitalserver-vm`, `vitalserver-proxy-run`, uninstall CLI 교체 |
| `nginx-bundle.tar.gz` | `/Library/Application Support/TiroshVitalServer/nginx` | macOS host proxy binary/config asset 교체 |
| `guest-deploy.tar.gz` | `/Library/Application Support/TiroshVitalServer/vm/data/deploy` | VM 안에서 참조하는 Compose, guest bin/systemd, nginx config, Docker image bundle 교체 |
| `rootfs-base.raw.gz` | `/Library/Application Support/TiroshVitalServer/vm/runtime/rootfs-base.raw.gz` | 이후 provisioning 기준 base artifact 교체. 기존 `vm-disk.img`에는 자동 전개하지 않음 |
| `migrations/*` | host runtime command | 설치된 runtime 상태를 바꾸는 executable migration. 기본 bundle에는 cloud-init seed refresh migration이 포함됨 |

중요한 구분은 `rootfs-base.raw.gz`와 `vm-disk.img`입니다.

```text
rootfs-base.raw.gz = immutable base artifact
vm-disk.img        = installed mutable VM instance
```

update에서 `rootfs-base.raw.gz`를 교체해도 이미 생성된 `vm-disk.img` 내부 OS/package는 자동으로 바뀌지 않습니다. 이미 설치된 VM 내부를 바꾸려면 migration이나 guest-side activation 단계가 필요합니다.

따라서 기존 `vm-disk.img` 자체가 Docker, Docker Compose, Avahi, growpart 같은 runtime package를 가지고 있지 않다면 일반 update bundle만으로는 복구할 수 없습니다. 이 경우에는 새 package로 재설치하거나, 별도의 VM/rootfs replacement 흐름을 사용해야 합니다. 이 흐름은 운영 데이터 보존 정책이 더 민감하므로 일반 Update 탭이 아니라 Danger Zone 대상입니다.

## 보존되는 것과 바뀌는 것

기본 update는 운영 데이터 보존을 우선합니다.

| 구분 | 경로/대상 | update 기본 정책 |
|---|---|---|
| VM mutable disk | `vm/runtime/vm-disk.img` | 보존 |
| VM config | `vm/runtime/vm-config.json` | 보존. Settings/CLI configure로 변경 |
| cloud-init seed | `vm/runtime/seed.iso` | `guest-deploy` 변경 시 갱신. VM 부팅 때 bootstrap 재실행을 유도 |
| Vital files | configured vital files directory | 보존 |
| VR release files | `vm/data/vr-release` | 보존 |
| Redis data | guest Docker volume `redis-data` | 보존 |
| runtime status | `status/runtime-status.json` | update/rollback 상태로 갱신 |
| install/update logs | `logs/`, `/private/tmp/tirosh-vitalserver-manager-command.log` | 보존 또는 rotation |
| managed backups | `backups/<timestamp>-before-<version>` | 생성/보존 |
| Helper app | `/Applications/VitalServer Helper.app` | 교체 |
| runtime CLI | `/usr/local/bin/*` | 교체 |
| host nginx bundle | product `nginx/` | 교체 |
| guest deploy bundle | `vm/data/deploy/` | 교체 |

`guest-deploy.tar.gz` 안에 Docker image bundle이 포함되어도, 그것은 “host shared directory에 새 image tar가 놓였다”는 뜻입니다. VM 안의 Docker daemon에 image가 실제로 load되고, 기존 container가 새 image로 recreate되는 것은 별도의 guest-side activation입니다.

따라서 `apps/vitalserver-vm-launcher/Support/Guest/bootstrap.sh` 같은 guest deploy 파일을 수정했다면, 새 update bundle을 만들면 그 수정은 `guest-deploy.tar.gz`에 들어갑니다. 이미 설치된 현장에서 실제로 반영되려면 Helper Update 탭 또는 `apply-bundle`로 해당 bundle을 적용해야 합니다.

## Apply 과정

Helper app의 Update 탭과 CLI는 같은 Swift runtime lifecycle을 사용합니다.

```text
1. verify bundle
2. stage bundle
3. free-space preflight
4. create managed backup
5. stop runtime services
6. replace host-side artifacts
7. run migrations
8. refresh cloud-init seed when guest deploy changed
9. write runtime-version.json
10. restart services
11. activate guest update when guest deploy changed
12. wait runtime health
13. success or rollback
```

각 단계의 의미는 아래입니다.

| 단계 | 설명 |
|---|---|
| verify | `manifest.json`, `checksums.txt`, artifact sha256/size 검증 |
| stage | bundle을 product root의 `bundles/` 아래로 복사 |
| preflight | stage/apply/backup에 필요한 여유 공간 확인 |
| backup | rollback 가능한 artifact를 `backups/` 아래에 저장 |
| stop services | VM/proxy/watchdog launchd service 중지 |
| replace | app/runtime-tools/nginx/guest-deploy/rootfs-base 교체 |
| migrations | executable migration을 순서대로 실행 |
| cloud-init refresh | `guest-deploy`가 바뀐 경우 새 instance-id로 seed를 갱신해 bootstrap 재실행을 유도 |
| restart | 이전에 runtime이 running 상태였으면 VM/proxy/watchdog 재시작 |
| guest activation | VM 내부에서 Docker image load, compose recreate, runtime-state 갱신 |
| health wait | guest HTTP, host proxy, Redis UI, Swagger UI 등 runtime health 대기 |
| rollback | health wait 실패 또는 migration 실패 시 backup 복원 시도 |

Helper app은 update 중 Command log를 1초 단위로 갱신합니다. Update 탭에서는 현재 단계와 command log tail을 함께 보여주며, 상세 로그는 Logs 탭의 `Command log`, `Update activation`, `Containers` source에서 확인합니다.

## Guest-Side Activation

현재 update 계약에서 가장 조심해야 하는 부분입니다.

`guest-deploy.tar.gz`는 host shared directory의 deploy bundle을 교체합니다. 하지만 VM 내부에서 아래 작업이 자동으로 보장되는 것은 아닙니다.

```text
docker load -i /mnt/tirosh/deploy/docker-images/vitalserver-images.tar.gz
docker compose down
docker compose up -d
old wrong-arch image cleanup
guest systemd unit 재설치
guest-side health 재검증
```

첫 설치에서는 cloud-init이 `bootstrap.sh`를 실행하고, 이 과정에서 Docker image bundle을 load합니다. 반면 update에서는 `guest-deploy`를 host shared directory에 교체하는 것만으로는 VM 내부 Docker daemon이 자동 갱신되지 않습니다.

이를 보완하기 위해 update flow는 `guest-deploy` 변경 시 두 단계를 수행합니다.

| 단계 | 목적 |
|---|---|
| cloud-init seed refresh | 새 instance-id를 가진 `seed.iso`를 만들어 VM 부팅 시 `bootstrap.sh`가 다시 실행될 수 있게 함 |
| guest activation request | `/mnt/tirosh/run/activate-update.request`를 만들고, VM 안의 `tirosh-vitalserver-activate-update`가 image load/compose recreate를 수행하게 함 |

호환성을 위해 update bundle에도 `001-refresh-cloud-init-seed` migration을 기본 포함합니다. 이유는 중요합니다. 이미 설치된 구버전 Helper가 bundle을 적용하면, 새 Swift apply 로직은 아직 실행될 수 없습니다. 하지만 구버전 apply도 migration은 실행하므로, 이 migration이 `seed.iso`를 갱신해 VM 부팅 시 새 `guest-deploy/bootstrap.sh`가 실행될 수 있게 합니다.

게스트 activation은 아래 결과 파일을 남깁니다.

```text
/mnt/tirosh/run/activate-update.log
/mnt/tirosh/run/activate-update-result.json
```

호스트 update command는 이 result가 `completed`가 될 때까지 기다린 뒤 runtime health check로 넘어갑니다.

현재 방향은 아래입니다.

```text
host apply-bundle
  -> replace guest-deploy on shared directory
  -> refresh cloud-init seed when guest deploy changed
  -> restart VM/proxy/watchdog
  -> run guest activation request
      -> /mnt/tirosh/run/activate-update.request
      -> VM 내부에서 image load
      -> docker compose recreate
      -> runtime-state 갱신
  -> host health wait
```

이 단계가 없으면 host에는 새 `guest-deploy`가 보이지만, VM Docker daemon은 이전 image/cache를 그대로 사용할 수 있습니다.

## 0.1.3 실패 분석

이번 0.1.3 update는 bundle 검증과 artifact 교체까지는 통과했습니다.

```text
bundle verified
bundle staged
backup created
replace-rootfs-base completed
replace-update-artifacts completed
run-migrations: no migrations
start-runtime-services completed
wait-runtime-health started
```

실패 지점은 runtime health wait입니다.

```text
step=wait-runtime-health status=failed error=runtime health check failed
```

runtime status에는 아래 failure reason이 남았습니다.

```text
host-proxy-http-502
proxy-port-80-in-use-by-nginx-66291_nginx-66292
redis-ui-http-502
swagger-ui-http-502
guest-http-000failed
```

VM container log에는 Redis가 아래처럼 반복 실패했습니다.

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

해석은 아래입니다.

| 관찰 | 의미 |
|---|---|
| `exec format error` | guest CPU architecture와 container image architecture가 맞지 않음 |
| 0.1.3 bundle 내부 Docker image config | `redis`, `vitalserver`, `nginx`, `redis-commander`, `swagger-ui` 모두 `arm64`로 확인됨 |
| installed `guest-deploy` | 새 compose와 새 image bundle은 host shared directory에 배치됨 |
| `bootstrap.log` | 최초 설치 때 image load만 기록. update 후 새 image load가 수행됐다는 로그가 없음 |
| `run-migrations: no migrations` | guest-side activation 단계가 없었음 |

따라서 0.1.3의 핵심 원인은 “새 bundle에 arm64 image가 없었다”가 아니라, **새 Docker image bundle을 VM 내부 Docker daemon에 load/recreate하는 update 단계가 빠진 것**입니다. 이전 잘못된 image cache가 남아 있으면 compose는 계속 그 image를 사용할 수 있고, Redis는 `exec format error`로 재시작 루프에 빠집니다.

부가적으로 rollback도 실패했습니다.

```text
rollback-restore-update-artifacts failed
NSPOSIXErrorDomain Code=24 "Too many open files"
```

즉 health wait 실패 후 managed backup으로 돌아가려 했지만, app bundle 복원 중 file descriptor 한계에 걸렸습니다. 이 경우 runtime은 `critical` 상태로 남을 수 있습니다.

정리하면 0.1.3 실패는 세 가지가 겹친 상태입니다.

1. guest Docker image activation 부재로 Redis가 wrong-arch image를 계속 실행
2. port 80에 이전 nginx listener가 남아 host proxy health가 502 또는 port-in-use로 실패
3. rollback 복원 중 `Too many open files`로 rollback 자체도 실패

## 0.1.4에서 반영해야 하는 보강

0.1.4에서는 update flow에 아래 보강을 포함합니다.

| 항목 | 이유 |
|---|---|
| guest deploy activation | Docker image bundle load, compose recreate, guest bin/systemd 갱신을 update 과정에 포함 |
| cloud-init seed refresh | activation unit이 없는 이전 설치본도 부팅 시 bootstrap을 다시 수행할 수 있게 함 |
| qemu preflight 제거 | arm64 image로 운영하므로 `qemu-x86_64-static`은 runtime 필수 조건이 아님 |
| image architecture preflight | bundle의 image config가 guest architecture와 맞는지 verify 단계에서 표시 |
| stale/wrong image cleanup | 동일 tag의 wrong-arch image가 남아도 새 image를 확실히 사용하게 함 |
| rollback copy 안정화 | app bundle 복원 시 `Too many open files`를 피하도록 tar/ditto 기반 atomic restore 검토 |
| proxy port preflight | apply 전 port 80을 점유한 stale nginx를 감지하고 중단 또는 repair 안내 |
| health reason 정규화 | `guest-http-000failed`, `host-proxy-http-`처럼 빈 code가 나오지 않게 표현 정리 |

## 0.1.4 update에서 다시 실패하는 경우

0.1.4 bundle은 0.1.3에서 빠졌던 guest activation 보강을 포함하지만, 기존 설치본의 `vm-disk.img`가 이미 air-gapped runtime package를 갖고 있지 않은 경우에는 VM 내부 bootstrap 단계에서 실패할 수 있습니다.

대표 로그:

```text
error: missing runtime package in air-gapped rootfs
The target bootstrap never runs apt-get. Rebuild the package rootfs with make vm-golden-rootfs.
Required commands/services: curl, docker, docker compose, avahi-daemon, growpart.
```

이 메시지는 update bundle의 `rootfs-base.raw.gz`가 잘못 교체됐다는 뜻이 아닙니다. 이미 설치되어 사용 중인 mutable disk인 `vm-disk.img` 안에 필요한 OS package가 없다는 뜻입니다.

중요한 제약:

| 항목 | 설명 |
|---|---|
| `rootfs-base.raw.gz` | update로 교체됨. 새 설치 또는 VM disk 재생성 기준 |
| `vm-disk.img` | 운영 중인 mutable disk. 일반 update에서는 보존됨 |
| guest deploy | update로 교체됨. VM 안에서 bootstrap/activation이 실행되어야 반영됨 |
| OS package | 기존 `vm-disk.img` 안에 없으면 일반 guest deploy update만으로 추가할 수 없음 |

이 상태에서 가능한 선택지는 아래입니다.

1. 새 package로 재설치한다. `.vital` 저장 경로와 backup 보존 여부를 먼저 확인합니다.
2. Danger Zone에 VM/rootfs replacement 기능을 추가해 `vm-disk.img`를 새 rootfs에서 재생성하고, Redis/Vital files 같은 운영 데이터를 별도로 보존/복원합니다.
3. 현장용 offline OS package bundle을 별도로 만들어 guest migration에서 설치합니다. 완전 air-gapped 제품에서는 이 방식도 artifact 검증과 rollback 정책이 필요합니다.

단순히 같은 bundle을 다시 적용하면 같은 bootstrap 실패가 반복됩니다.

## 확인해야 할 로그

Update 실패 시 우선 아래를 봅니다.

```sh
tail -f /private/tmp/tirosh-vitalserver-manager-command.log
cat "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/data/run/container-logs.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/vm/logs/proxy.err.log"
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json"
```

bundle 자체를 확인할 때:

```sh
cat dist/update-bundles/update-bundle-<version>/manifest.json
tar -tzf dist/update-bundles/update-bundle-<version>/guest-deploy.tar.gz | grep docker-images
```

Docker image bundle architecture를 확인할 때:

```sh
tar -xOf dist/update-bundles/update-bundle-<version>/guest-deploy.tar.gz \
  deploy/docker-images/vitalserver-images.tar.gz > /tmp/vitalserver-images.tar.gz

tar -xOf /tmp/vitalserver-images.tar.gz manifest.json
```

`manifest.json`의 각 image config blob에서 `"architecture":"arm64"`인지 확인합니다.

## Recovery 원칙

Update 실패 시 가장 중요한 것은 운영 데이터 보존입니다.

1. 먼저 `runtime-status.json`과 command/container log를 저장합니다.
2. `backups/<timestamp>-before-<version>`이 있는지 확인합니다.
3. Redis data와 vital files directory를 임의로 삭제하지 않습니다.
4. rollback이 실패했다면 같은 bundle을 반복 적용하기 전에 실패 원인을 제거합니다.
5. Docker image architecture 문제가 있으면 guest-side activation 또는 재설치가 필요할 수 있습니다.
6. 재설치를 선택하더라도 `.vital` 파일 경로와 backups 보존 여부를 먼저 확인합니다.

현재 0.1.3 실패 상태에서는 단순히 `Apply Bundle`을 다시 누르는 것보다, guest Docker image activation 보강이 들어간 다음 bundle을 적용하거나, clean하지 않은 재설치/복구 절차를 별도로 수행하는 편이 안전합니다.
