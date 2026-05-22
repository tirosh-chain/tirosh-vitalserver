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

## Update 안정성 기준

Update 계약의 목표는 “어떤 설치본에서 어떤 update bundle을 적용하더라도, 실패 원인을 명확히 남기고 재시도/rollback 가능한 상태를 유지하는 것”입니다. Update는 runtime 자체를 바꾸는 기능이므로 일반 기능보다 더 보수적으로 설계합니다.

### 핵심 원칙

| 원칙 | 기준 |
|---|---|
| update protocol은 후방 호환 | `manifest.json`, `activate-update.request`, `runtime-version.json`, status/result JSON은 새 reader가 예전 형식을 읽을 수 있어야 한다 |
| updater는 보수적으로 변경 | update를 수행하는 host runtime tool과 guest activation script는 일반 runtime보다 더 강한 호환성 기준을 적용한다 |
| request 필드는 늘릴 때 기본값 제공 | 새 필드를 추가해도 기존 설치본이 만든 request를 처리할 수 있어야 한다 |
| 모르는 필드는 무시 | reader는 알 수 없는 JSON field 때문에 실패하면 안 된다 |
| 실패는 상태 파일과 로그에 남김 | 실패 단계, reason code, 사람이 읽을 수 있는 message를 남긴다 |
| 재실행 가능 | 같은 bundle을 다시 적용해도 중간 산출물 때문에 더 망가지면 안 된다 |
| rollback 가능 | 운영 데이터는 보존하고 교체 가능한 artifact만 managed backup으로 되돌린다 |

### Update Protocol 계약

아래 파일은 update 호환성의 public contract로 취급합니다.

| 파일 | 생산자 | 소비자 | 호환성 기준 |
|---|---|---|---|
| `manifest.json` | build tool | host updater | `schemaVersion`, `version`, artifact 목록은 필수. 새 필드는 optional로 추가 |
| `checksums.txt` | build tool | host verifier | artifact path와 sha256/size 검증 기준 |
| `activate-update.request` | host updater | guest activation script | `requestId`가 없어도 legacy request로 처리 가능해야 함 |
| `activate-update-result.json` | guest activation script | host updater/Helper UI | `status`, `message`, `updatedAt`은 항상 기록 |
| `runtime-status.json` | host updater/watchdog | Helper UI | operation/step/status는 enum 계약으로 유지 |
| `runtime-version.json` | installer/updater | Helper UI/updater | 현재 runtime/app/guest version 표시와 rollback 판단 기준 |

호환성을 위해 host updater가 아래처럼 최소 필드만 가진 request를 만들더라도 guest activation script는 처리할 수 있어야 합니다.

```json
{
  "operation": "activate-update",
  "requestedAt": "2026-05-22T00:00:00Z",
  "version": "1.2.3"
}
```

게스트 activation script는 이 request를 실패시키지 말고 legacy request로 처리해야 합니다.

```text
requestId missing
  -> generate legacy request id
  -> continue activation
  -> write result with generated requestId
```

반대로 host updater는 `requestId`를 기대하고 기다리므로, result의 `requestId`가 다를 수 있는 legacy case도 명시적으로 처리합니다.

| 상황 | 처리 |
|---|---|
| host request에 `requestId` 있음 | result의 `requestId`가 일치해야 completed로 인정 |
| host request에 `requestId` 없음 | guest가 생성한 legacy `requestId`를 허용하고, `version`/`operation`/`status` 중심으로 판단 |
| result에 `schemaVersion` 없음 | legacy result로 읽고 status/message를 우선 사용 |
| result status가 `failed` | 즉시 실패 처리하고 message를 Helper UI와 command log에 노출 |

### Manifest Compatibility

update bundle manifest에는 updater 호환성 판단을 위한 필드를 둡니다.

```json
{
  "schemaVersion": 2,
  "product": "com.tirosh.vitalserver",
  "version": "1.2.3",
  "runtimeVersion": "1.2.3",
  "minUpdaterVersion": "1.1.0",
  "requiresGuestActivation": true,
  "requiresTwoPhaseUpdate": false
}
```

필드 의미:

| 필드 | 의미 |
|---|---|
| `minUpdaterVersion` | 이 bundle을 직접 적용할 수 있는 최소 host updater/runtime-tools 버전 |
| `requiresGuestActivation` | `guest-deploy` 교체 후 VM 내부 activation이 필요한지 |
| `requiresTwoPhaseUpdate` | updater 자체를 먼저 갱신해야 하는 bridge update가 필요한지 |

Reader는 이 필드들의 누락을 허용해야 합니다. 새 필드는 optional로 추가하고, 기본값을 통해 오래된 bundle도 읽을 수 있어야 합니다.

### Two-Phase Update 기준

update system 자체가 바뀌는 경우에는 runtime payload와 updater payload를 한 번에 섞어 처리하지 않습니다.

```text
Phase 1: updater compatibility layer 갱신
  - runtime-tools
  - guest activation script
  - status/result parser
  - update UI 표시 개선

Phase 2: runtime payload 갱신
  - guest-deploy
  - Docker image bundle
  - nginx bundle
  - rootfs-base
  - migrations
```

적용 기준:

| 변경 내용 | 단일 bundle 가능 여부 | 비고 |
|---|---|---|
| Helper UI만 변경 | 가능 | app bundle 교체 후 app 재실행 필요 |
| runtime-tools CLI만 변경 | 가능하지만 주의 | 현재 실행 중인 updater는 중간에 바뀌지 않음 |
| guest activation request/result 계약 변경 | bridge bundle 권장 | 구버전 host/guest 조합을 고려 |
| Docker image bundle 변경 | 가능 | guest activation 필수 |
| rootfs-base 변경 | 가능 | 기존 `vm-disk.img`에는 자동 전개되지 않음 |
| mutable VM disk 교체 | 일반 update 금지 | Danger Zone의 별도 rootfs replacement 대상 |

### Bridge Bundle 기준

아래 상황에서는 일반 update bundle 대신 bridge bundle을 먼저 제공합니다.

| 상황 | bridge bundle에 포함할 것 |
|---|---|
| host updater가 새 manifest를 읽지 못함 | `runtime-tools.tar.gz`, Helper app |
| guest activation script 계약이 바뀜 | `guest-deploy.tar.gz`, cloud-init seed refresh migration |
| result/status parser 계약이 바뀜 | `runtime-tools.tar.gz`, Helper app |
| update progress 표시 방식이 바뀜 | Helper app, runtime-tools |

Bridge bundle은 가능한 작게 유지합니다.

```text
bridge bundle:
  - app-bundle.tar.gz
  - runtime-tools.tar.gz
  - guest-deploy.tar.gz
  - migrations/

일반적으로 제외:
  - rootfs-base.raw.gz
  - 대용량 Docker image bundle
```

### Idempotency 기준

update 단계는 중간 실패 후 재실행이 가능해야 합니다. 이를 위해 단계별 marker 또는 result를 남깁니다.

| 단계 | marker/log 기준 |
|---|---|
| verification completed | command log |
| bundle staged | staged bundle path |
| backup created | `backups/<timestamp>-before-<version>` |
| artifacts replaced | runtime progress step |
| guest activation requested | `activate-update.request` |
| guest activation completed | `activate-update-result.json` status `completed` |
| health passed | `runtime-status.json` state `healthy` |
| update committed | `runtime-version.json` version 갱신 |

재실행 시에는 아래를 지켜야 합니다.

- 이미 staged된 같은 bundle은 검증 후 재사용할 수 있다.
- 이미 존재하는 backup은 덮어쓰지 않고 새 backup을 만들거나 명시적으로 재사용한다.
- stale `activate-update-result.json`은 request id 또는 timestamp로 구분한다.
- stale `activate-update.request`는 새 요청 전 제거하거나 새 request id로 덮어쓴다.
- rollback 중에도 운영 데이터 경로는 삭제하지 않는다.

### Backward-Compatible Guest Activation

게스트 activation script는 update 안정성에서 가장 보수적으로 다룹니다.

필수 동작:

| 케이스 | 동작 |
|---|---|
| `python3` 없음 | 실패하되 명확한 message와 result 기록. 단, 제품 rootfs에는 `python3`를 필수 포함 |
| `requestId` 없음 | legacy id를 생성하고 계속 진행 |
| `version` 없음 | `unknown`으로 기록하고 계속 진행 |
| request JSON 파싱 실패 | failed result와 log 기록 |
| Docker image bundle 없음 | image load는 skip 가능하되 compose recreate는 정책에 따라 진행 |
| compose 실패 | failed result와 container log 확인 안내 |

구현 기준:

```text
activation request reader:
  - requestId optional
  - version optional
  - schemaVersion optional
  - operation optional but recommended

activation result writer:
  - schemaVersion always written
  - requestId always written, generated if needed
  - status always written
  - message always written
  - updatedAt always written
```

### Release Gate

update bundle을 배포 후보로 보려면 아래를 통과해야 합니다.

| 항목 | 기준 |
|---|---|
| fresh install | clean machine 또는 clean runtime home에서 설치 성공 |
| same-version apply | 같은 version bundle을 적용해도 깨지지 않음 |
| previous-version apply | 직전 버전 설치본에서 최신 bundle 적용 성공 |
| legacy request apply | `requestId` 없는 activation request도 guest가 처리 |
| guest activation | Docker image load와 compose recreate가 수행됨 |
| health wait | VitalServer, Redis, network access가 ready |
| rollback | 의도적 실패 bundle에서 managed backup rollback 성공 |
| logs | Update 탭/Logs 탭에서 현재 단계와 실패 이유를 확인 가능 |

Release gate를 통과하지 못한 bundle은 현장 전달 대상이 아닙니다. 특히 update system 자체가 바뀌는 release는 이전 설치본에서 직접 적용하는 테스트를 반드시 포함합니다.

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

Guest-side activation은 update 계약에서 가장 조심해야 하는 부분입니다.

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

표준 흐름은 아래입니다.

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

## 실패 패턴: Guest Activation 누락

Bundle 검증과 host-side artifact 교체가 통과했더라도, guest-side activation이 빠지면 VM 내부 Docker daemon은 이전 image/cache를 계속 사용할 수 있습니다.

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

이 경우 실패 지점은 보통 runtime health wait입니다.

```text
step=wait-runtime-health status=failed error=runtime health check failed
```

runtime status에는 아래와 같은 failure reason이 남을 수 있습니다.

```text
host-proxy-http-502
proxy-port-80-in-use-by-nginx-66291_nginx-66292
redis-ui-http-502
swagger-ui-http-502
guest-http-000failed
```

VM container log에는 Redis나 다른 container가 아래처럼 반복 실패할 수 있습니다.

```text
redis-1 | exec /usr/local/bin/docker-entrypoint.sh: exec format error
```

해석은 아래입니다.

| 관찰 | 의미 |
|---|---|
| `exec format error` | guest CPU architecture와 container image architecture가 맞지 않음 |
| bundle 내부 Docker image config는 정상 | bundle은 올바르지만 VM 내부 Docker daemon에 load되지 않았을 수 있음 |
| installed `guest-deploy`는 교체됨 | 새 compose와 새 image bundle은 host shared directory에 배치됨 |
| `bootstrap.log`에 최초 설치 기록만 있음 | update 후 새 image load가 수행되지 않았을 수 있음 |
| guest activation log가 없음 | Docker image load/compose recreate 단계가 실행되지 않았을 수 있음 |

이 패턴의 핵심은 “새 bundle에 올바른 image가 없었다”가 아니라, **새 Docker image bundle을 VM 내부 Docker daemon에 load/recreate하는 update 단계가 빠진 것**입니다. 이전 잘못된 image cache가 남아 있으면 compose는 계속 그 image를 사용할 수 있고, Redis 같은 서비스는 `exec format error`로 재시작 루프에 빠집니다.

부가적으로 rollback이 실패할 수도 있습니다.

```text
rollback-restore-update-artifacts failed
NSPOSIXErrorDomain Code=24 "Too many open files"
```

즉 health wait 실패 후 managed backup으로 돌아가려 했지만, app bundle 복원 중 file descriptor 한계에 걸릴 수 있습니다. 이 경우 runtime은 `critical` 상태로 남을 수 있습니다.

이 실패 패턴은 보통 세 가지가 겹칩니다.

1. guest Docker image activation 부재로 Redis가 wrong-arch image를 계속 실행
2. port 80에 이전 nginx listener가 남아 host proxy health가 502 또는 port-in-use로 실패
3. rollback 복원 중 `Too many open files`로 rollback 자체도 실패

## 필수 보강 항목

Update flow는 아래 보강을 포함해야 합니다.

| 항목 | 이유 |
|---|---|
| guest deploy activation | Docker image bundle load, compose recreate, guest bin/systemd 갱신을 update 과정에 포함 |
| cloud-init seed refresh | activation unit이 없는 이전 설치본도 부팅 시 bootstrap을 다시 수행할 수 있게 함 |
| qemu preflight 제거 | arm64 image로 운영하므로 `qemu-x86_64-static`은 runtime 필수 조건이 아님 |
| image architecture preflight | bundle의 image config가 guest architecture와 맞는지 verify 단계에서 표시 |
| stale/wrong image cleanup | 동일 tag의 wrong-arch image가 남아도 새 image를 확실히 사용하게 함 |
| rollback copy 안정화 | app bundle 복원 시 `Too many open files`를 피하도록 tar/ditto 기반 atomic restore 사용 |
| proxy port preflight | apply 전 port 80을 점유한 stale nginx를 감지하고 중단 또는 repair 안내 |
| health reason 정규화 | `guest-http-000failed`, `host-proxy-http-`처럼 빈 code가 나오지 않게 표현 정리 |

## 실패 패턴: Mutable VM Disk의 OS Package 누락

Update bundle에 guest activation 보강이 포함되어 있어도, 기존 설치본의 `vm-disk.img`가 air-gapped runtime package를 갖고 있지 않은 경우에는 VM 내부 bootstrap 단계에서 실패할 수 있습니다.

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

단순히 같은 bundle을 다시 적용하면 같은 bootstrap 실패가 반복됩니다. mutable VM disk의 OS package 상태가 원인인 경우에는 일반 update bundle이 아니라 재설치, rootfs replacement, 또는 별도 offline OS package migration이 필요합니다.

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

같은 실패가 반복되는 경우에는 `Apply Bundle`을 계속 누르기보다, guest activation 로그와 container log를 먼저 확인한 뒤 원인에 맞는 recovery 절차를 선택합니다.
