# VitalServer VM Packaging and Update

빌드 산출물, 설치 흐름, install/update 계약을 정리합니다. 현장 전달 표준 `make dist/dmg/dev`, 반복 개발용 `make dist/dmg/dev/cached`, `make dist/pkg/dev`/`make dist/pkg/release`, `make dist/dmg/release`, update bundle, 설치 설정 JSON을 볼 때 사용합니다.

## 이 문서에서 바로 알아야 할 것

| 질문 | 답 |
|---|---|
| 최종 설치 단위는? | `.pkg` |
| DMG의 역할은? | `.pkg`를 전달하는 껍데기 |
| 최종 산출물 위치는? | `dist/` |
| build 작업의 주 구현은? | Python `packages/vitalserver-devtools` |
| 설치 후 provisioning 주 구현은? | Swift `vitalserver-vm runtime install-provision` |
| Platform API 자동 기동은? | launchd `ai.tirosh.vitalserver.helper.platform-agent` (`RunAtLoad`, `KeepAlive`) |
| Shell script 역할은? | `postinstall`, launchd, uninstall wrapper |
| update bundle은 누가 검증/적용하나? | Swift `RuntimeLifecycle` |

## 배포 시나리오

| 시나리오 | 산출물 | 생성 명령 | 현장 적용 |
|---|---|---|---|
| 신규 설치 dev 현장 전달 표준 gate | `dist/VitalServerHelper-<version>.dmg` | `make dist/dmg/dev` | review, environment preflight, clean compile, artifact verify, runtime smoke |
| 반복 개발용 dev cache-preferred 패키징 | `dist/VitalServerHelper-<version>.dmg` | `make dist/dmg/dev/cached` | 현재 source 계약과 rootfs receipt가 일치하는 golden cache만 재사용. 현장 전달 proof는 만들지 않음 |
| 신규 설치 release 검증 | `dist/VitalServerHelper-<version>.dmg` | `make dist/dmg/release` | release.json 기반 release 검증 |
| 개발용 `.pkg` artifact 생성 | `dist/VitalServerHelper-<version>.pkg` | `make dist/pkg/dev` | 직접 설치 전 artifact packaging. 현장 전달 proof는 `dist/dmg/dev`가 소유 |
| release `.pkg` artifact 생성 | `dist/VitalServerHelper-<version>.pkg` | `make dist/pkg/release` | 직접 설치 전 artifact packaging. 현장 전달 proof는 `dist/dmg/release`가 소유 |
| air-gapped Product Update | `dist/update-bundles/update-bundle-<channel>-product-update-<releaseLabel>.tar.gz` | `make dist/update/release` | Helper app Update 탭 또는 `vitalserver-vm runtime apply-bundle` |
| VM Image Update | `dist/update-bundles/update-bundle-<channel>-vm-image-update-<releaseLabel>.tar.gz` | `make dist/image-update/release` | rootfs-base 교체가 필요한 경우에만 사용 |
| Product Update bundle 검증 | product update tarball | `make dist/update/verify/release` | 전달 전 manifest/checksum 검증 |
| VM Image Update bundle 검증 | VM image update tarball | `make dist/image-update/verify/release` | 전달 전 manifest/checksum 검증 |
| 개발 설치 테스트 | installed runtime | `make dist/install/dev` | 현재 repo가 있는 개발 Mac에 설치 후 `make dist/installed/health` |

사용자에게 “bundle”로 제공하는 대상은 두 가지입니다. 신규 설치는 `.dmg`/`.pkg`이고, 이미 설치된 현장 업데이트는 `update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz` tarball입니다. air-gapped 환경에서는 이 파일을 USB나 폐쇄망 파일 서버로 전달합니다. 적용 과정과 보존/변경 범위는 [Update](update.md)에 따로 정리합니다.

## 버전 source of truth

package, DMG, update bundle, Helper product/component version은 아래 파일을 기준으로 관리합니다.

```text
apps/vitalserver-macos-runtime/release.json
apps/vitalserver-macos-runtime/release-dev.json
```

`release.json`은 stable channel, `release-dev.json`은 내부 dev channel SoT입니다. `*-release` target은 `release.json`을 사용하고 현재 repository branch가 `main`일 때만 실행됩니다. `*-dev` target은 `release-dev.json`을 사용하며 branch 제약을 두지 않습니다.

Release manifest는 build input이고, Product Lab/API 구현의 세부 contract는 소유하지 않습니다. Runtime 전체 SoT map은 [Runtime observability model](observability.md#source-of-truth-map)에 정리합니다. Packaging 관점에서는 release manifest가 artifact identity와 service catalog를 소유하고, `vm-build.toml`이 build/deploy 경로와 Docker image bundle 구성을 소유합니다.

`make devtools/release-contract`는 Docker export, rootfs fingerprint/cache 판단보다 먼저 release manifest의 Guest service image를 `Support/Guest/compose.yaml`과 `config/vm-build.toml`의 Docker plan에 대조합니다. 이 단계는 Compose, VM config, Guest Python source를 고치지 않습니다. 불일치는 source path, service/field, expected/actual image를 포함한 compile failure로 끝납니다. 이 단계가 쓰는 것은 지정된 Swift `Generated*.swift` 파생 소스뿐입니다.

따라서 image tag를 바꾸는 release는 manifest만 바꿔 빌드 중에 다른 입력을 덮어쓰지 않습니다. manifest, Compose, VM Docker plan을 같은 변경에서 명시적으로 맞춰야 합니다. 나중에 profile별 image가 달라지면 shared source를 rewrite하는 대신 profile별 immutable compile input 또는 `.tmp` 아래 profile-scoped rendered deploy material과 receipt를 사용합니다.

| Field | Owner | 의미 |
|---|---|---|
| `channel` | release manifest | updater channel compatibility와 artifact routing. 설치된 updater channel과 bundle channel이 다르면 apply preflight에서 거부 |
| `helperVersion` | release manifest | Apple/pkg-safe numeric Helper product version |
| `releaseLabel` | release manifest | package/DMG/update bundle/staging/backup/installed version 표시에 쓰는 artifact identity |
| `targetPlatform` | release manifest | 이 release artifact/update bundle을 적용할 수 있는 단일 platform variant |
| `distribution.profile` | release manifest | stable/dev build profile. Local browser diagnostics console은 `dev`에서만 노출 |
| `distribution.audience` | release manifest | artifact의 intended audience 설명 |
| `services.*` | release manifest | bundled service image, version, display name |
| `bundle.optionalContainerServices` | release manifest | 이번 package/update bundle에 포함할 선택 container service 목록 |

`bundle.optionalContainerServices`는 dev-only 선택 container service를 포함할지 여부만 표현합니다. Runtime v2 product stack의 Product Lab과 Postgres는 선택 TestKit service가 아니라 `services.lab`, `services.postgres`, Guest compose, Guest compile contract가 함께 검증하는 product dependency입니다. Lab route, API shape, 화면 정책은 release manifest가 아니라 Runtime Control `/runtime/lab/*`, Guest Control `/runtime/lab/*`, `apps/vitalserver-lab` 구현이 소유합니다.

Product Lab과 VitalDB read model은 Postgres를 운영 store로 사용하되 SQL 문자열을 shell `psql`에 조립하지 않습니다. Domain class, SQLAlchemy ORM record, mapper, repository를 분리하고 database URL로 engine을 조립합니다. SQLite는 fallback이 아니라 동일 persistence contract를 검증하는 대체 dialect이며, 운영 store 변경은 명시 configuration/migration으로만 수행합니다.

Vital Files library upload는 packaging이 파일을 미리 포함하거나 Guest path를 추정하는
기능이 아닙니다. 설치된 Runtime Control API가 Host/PWA에서 선택한 N개 `.vital` 파일을
multipart batch로 받고, 전체 batch 검증과 staging commit 후 configured library에
반영합니다. `.vital`이 아닌 파일, duplicate filename, existing destination, unreadable
source, missing library는 성공이나 빈 결과로 바꾸지 않습니다. Replay는 upload와 별도이며
library read model이 제공한 상대 경로 하나만 사용합니다. 자세한 owner/UI 계약은
[macOS Runtime Architecture](architecture.md#7-2-vital-files-upload와-replay-경계)를
따릅니다.

Runtime Control PWA와 headless `vitalserver-platform-agent`는 Helper app bundle에
함께 포함됩니다. Agent executable은 app 전체 서명 전에 nested code로 먼저
서명되며 launchd plist는 app 내부 executable을 직접 실행합니다. `make devtools/app`,
`make dist/pkg/*`, `make dist/dmg/*`, `make dist/update/*`는 `make pwa/build`를 먼저
실행합니다. 빌드 머신에서는 packaging 전에 한 번 `make pwa/install`을 실행해야
하며, 현장 Mac에는 npm/Vite나 registry 접근이 필요하지 않습니다.

## Build and Runtime Validation Contracts

Packaging workflow 이름은 각 단계가 보장하는 상태를 뜻합니다. `compile`은 artifact 생성 계약이고, installed runtime 상태를 추정하지 않습니다. Guest bootstrap 완료와 runtime contract는 별도 runtime smoke가 소유합니다. `make dist/dmg/dev`와 `make dist/dmg/release`는 각각 dev/release 현장 전달 표준 gate이며, review → release-contract → package environment preflight → PWA build → clean golden-rootfs compile → DMG artifact verify → golden runtime smoke 순서로 실행합니다. cache 재사용 여부는 `make dist/dmg/dev/cached`라는 별도 target이 소유합니다. 같은 `compile` target을 변수로 cached/clean mode 사이에서 바꾸지 않습니다.

| Target | Contract |
|---|---|
| `make dist/dmg/dev` | 현장 전달 표준 dev DMG gate입니다. review, clean golden-rootfs compile, artifact verify, golden runtime smoke를 순서대로 통과해야 합니다. |
| `make dist/dmg/dev/cached` | 현재 Guest deploy source 계약 fingerprint와 rootfs receipt가 모두 일치하는 golden cache만 재사용하는 반복 개발용 DMG packaging target입니다. review, artifact verify, runtime smoke를 실행하지 않으므로 현장 전달 proof가 아닙니다. |
| `make dist/dmg/dev/compile` | dev DMG를 clean golden rootfs에서 생성합니다. Rootfs 준비 proof와 package input은 검증하지만 installed runtime success를 뜻하지 않습니다. |
| `make dist/dmg/dev/verify` | 이미 생성된 dev DMG artifact readback과 현재 golden rootfs runtime smoke를 보는 진단 target입니다. Compile은 실행하지 않으며, verified golden cache가 없거나 stale이면 fail-fast합니다. DMG 자체를 boot한 proof도 아닙니다. |
| `make dist/pkg/dev/compile` | dev PKG를 clean golden rootfs에서 생성합니다. |
| `make dist/pkg/dev/runtime-smoke` | dev PKG와 같은 golden runtime contract를 검증합니다. |
| `make dist/pkg/dev/verify` | package plan/template review, PWA Runtime Control contract/check/test, log archive/retention tests, dev PKG compile, runtime smoke를 실행하는 package-level gate입니다. 현장 전달 proof는 DMG gate가 소유합니다. |
| `make dist/dmg/release` | release branch guard와 review를 거친 뒤, clean golden-rootfs compile, DMG artifact verify, golden runtime smoke를 모두 실행하는 release 현장 전달 gate입니다. |
| `make dist/pkg/release/verify` | release PKG 생성 후 runtime smoke를 실행합니다. |

`dev`와 `release`는 단순 default가 아니라 artifact identity입니다. public profile target은 각각의 release manifest를 직접 소유하므로 command-line `VM_RELEASE_FILE`로 다른 profile을 끼워 넣을 수 없습니다.

`compile passed`는 `installed runtime passed`와 다릅니다. DMG compile은 clean rootfs 기반 산출물 생성을 의미하고, artifact readback과 golden runtime smoke는 각각 별도 proof입니다. 현장 전달 전에는 이 proof를 모두 묶는 `make dist/dmg/dev` 또는 `make dist/dmg/release`만 사용합니다. `make dist/dmg/dev/compile`과 `make dist/dmg/dev/verify`는 failing phase를 분리해 진단할 때 쓰는 단계 target이며, 둘 중 하나만으로 현장 전달을 선언하지 않습니다. `verify`의 runtime smoke는 verified golden cache를 요구할 뿐 cache miss/stale 상태에서 compile을 시작하지 않습니다. Runtime smoke failure는 fallback으로 보정하지 않고 failing stage, runId, manifest, bootstrap log, launcher log를 통해 실패 상태를 드러내야 합니다. `make dist/dmg/dev/cached`는 빠른 local packaging을 위한 target이므로 review, artifact readback, golden runtime smoke를 실행하지 않습니다. 어느 DMG build target도 실제 target Mac의 install-provision side effect를 실행하지 않으므로, 설치 후 동작 가능성은 `make dist/install/dev/verified` 또는 설치 후 `make dist/installed/health`로 별도 확인합니다. DMG의 review, artifact verify, runtime smoke는 내부 단계로 유지하되, 현장 전달 public workflow는 profile별 `dist/dmg/{dev|release}` 하나로 고정합니다.

Package environment preflight는 rootfs compile 전에 Host-owned `swift`, `codesign`, `pkgbuild`, DMG의 `hdiutil`, output path와 기존 DMG attachment를 확인합니다. rootfs receipt, compiled Guest deploy material, golden kernel/initrd 검증은 compile 뒤 package preflight가 맡습니다. 따라서 아직 만들어지지 않은 rootfs를 앞 단계가 추정하지 않으면서도, VM/Docker compile과 무관한 Mac packaging blocker는 먼저 드러납니다.

### Compile material receipt

`compile`은 rootfs만 만들지 않습니다. Golden VM에서 실제로 실행한 Guest deploy material의 digest도 rootfs sidecar(`rootfs-base.raw.gz.manifest.json`, schema v3)에 기록합니다. digest에는 compose, Guest tools, Docker image bundle, product source와 함께 rootfs compile 의미를 가진 `ubuntu`, `runtimeData`, `dockerImages` metadata가 포함됩니다. 반대로 Host가 run마다 쓰는 `guestClockUtc`, rootfs `runId`, runtime-smoke 설정, `host-time.json`은 material identity에 넣지 않습니다.

Guest Docker compile은 Docker side effect 전에 `Support/Guest/compose.yaml`의 product service, image, build Dockerfile, deploy include를 같은 명시 input으로 대조합니다. image 또는 Dockerfile이 config와 다르거나 Guest deploy에 포함되지 않으면 compile은 Docker pull/build 전에 실패합니다. export는 반드시 `docker image save --platform <guest platform>`으로 platform을 고정하고, 생성된 archive의 expected tag, legacy Config/Layer reference, OCI descriptor closure와 SHA-256을 compile 안에서 검증합니다. 실제 registry, Docker daemon, pull/build/export 실패는 이 검사를 대신하는 package preflight가 아니라 compile failure evidence로 남습니다.

Host compile이 product image를 build/pull/export하는 유일한 경계입니다. Guest bootstrap은 검증된 bundle을 `docker load`로 소비하고 Compose를 `up --pull never --no-build`로만 시작합니다. image가 빠졌을 때 Guest가 pull하거나 다시 build해서 상태를 보정하지 않습니다. 따라서 tag 누락은 Guest fallback이 아니라 명시적인 bootstrap/Compose failure로 남습니다. Guest가 Compose에 전달하는 환경 파일은 개발 Mac의 `.env`를 복사하지 않고, explicit `runtime-config.json`과 `runtime-settings.json`에서 `/mnt/runtime/compose.env`로 materialize합니다. compiled deploy share는 immutable input이고, runtime별 환경 상태는 runtime disk에 둡니다.

Package 단계는 Docker image를 다시 만들거나 Guest source를 다시 stage하지 않습니다. `--guest-deploy-source`로 compile이 사용한 material만 받아 Host-owned run metadata를 새로 쓴 뒤 receipt와 다시 대조합니다. runtime smoke도 같은 순서로 restage한 material을 cached rootfs receipt와 대조한 뒤에만 VM을 부팅합니다. 따라서 compile 이후 apt snapshot, Docker platform, runtime-data contract, Guest source가 달라지면 package 또는 smoke는 성공으로 진행하지 않습니다.

`dist/dmg/dev/cached`의 fingerprint는 Guest support/tools만이 아니라 실제 deploy source, Docker build source, deploy serializer, rootfs receipt schema, effective build config와 rootfs size를 포함합니다. receipt와 fingerprint가 모두 일치할 때만 cache를 재사용합니다. 하나라도 다르거나 cache가 없으면 이전 golden `vm-disk.img`를 계속 쓰지 않고 새 Ubuntu base disk에서 compile합니다.

Guest-tools wheel은 temporary build output에서 만든 뒤 compiled deploy material에만 복사합니다. source tree의 `packages/vitalserver-guest-tools/dist`는 compile input도, compile output도 아닙니다. 따라서 같은 delivery run의 wheel staging이 이후 runtime-smoke의 rootfs fingerprint를 바꾸지 않습니다.

Guest Tools의 air-gap dependency authority는 repository root `uv.lock`이 아니라 CPython 3.12와 Guest architecture별 `packages/vitalserver-guest-tools/requirements/guest-runtime-<target>.txt`입니다. Wheelhouse staging은 hash-pinned lock을 target platform wheel로 materialize한 뒤, 생성한 Guest Tools wheel까지 포함한 전체 requirements를 `--no-index`로 다시 resolve합니다. 따라서 project metadata에 새 dependency가 추가됐지만 target lock/wheel이 빠진 경우 golden VM을 시작하기 전에 compile failure로 끝납니다. Linux ARM64 target은 Ubuntu 24.04의 glibc contract 안에서 `manylinux_2_28_aarch64`와 이전 `manylinux2014_aarch64` wheel을 모두 명시적으로 허용합니다. 이는 missing wheel을 network에서 보정하는 fallback이 아니라, 한 dependency closure 안에 공존하는 호환 platform tag 계약입니다.

Runtime smoke는 Host가 제공한 explicit deploy contract도 검증합니다. Devtools가 VM을 직접 시작하는 runtime-smoke 경로에서도 `data/deploy/host-time.json`을 써야 하며, Guest는 boot 초기에 `tirosh-vitalserver-sync-host-time.service`로 이 값을 적용한 뒤 Docker, runtime-observation, observability, compose service를 시작합니다. `host-time.json`이 missing/invalid이면 NTP나 현재 Guest clock으로 보정하지 않고 smoke failure로 처리합니다.

`runtime-boot-smoke-manifest.json`은 아래 stage를 모두 통과해야 합니다.

| stage | 검증 의미 |
|---|---|
| `bootstrap-result` | guest bootstrap이 completed result를 기록 |
| `runtime-observation` | guest runtime observation artifact가 생성되고 decode 가능 |
| `systemd-units` | 필수 guest systemd units가 설치/활성화됨 |
| `http` | guest HTTP와 host proxy path가 응답 |
| `compose-services` | expected compose services가 running/healthy contract를 보고 |
| `disk-health` | guest disk/mount/runtime data shape가 명시 상태로 확인 |
| `capabilities` | update shutdown, maintenance operation, product service control 등 Guest capability가 보고 |
| `guest-control-operations` | Guest Control service/maintenance operation path가 동작 |
| `feature-readiness` | backup, observability, runtime control feature readiness가 명시 상태로 확인 |

성공 로그는 `Golden disk runtime boot smoke passed`처럼 명시적인 최종 pass line을 남겨야 합니다. 중간에 `No VM launcher process is running` 같은 cleanup line이 있어도 최종 pass line이 없으면 성공으로 해석하지 않습니다.

runtime boot smoke는 manifest가 생길 때까지 timeout만 기다리지 않습니다. 현재 run의 `bootstrap-result.json.status=failed`를 발견하면 즉시 `runId`, `stage=bootstrap-result`, `reasonCodes`, bootstrap result 경로와 launcher log 경로를 출력하고 실패합니다. 이전 run의 bootstrap result는 smoke 시작 시 무효화하므로 stale failure를 현재 run failure로 해석하지 않습니다.

Release package와 DMG build는 expensive host packaging 전에 preflight를 통과해야 합니다. Preflight는 tool, package input, golden runtime `Image`/`initrd.img`, rootfs receipt, compiled Guest deploy material, output path, DMG attachment을 확인합니다. Docker pull/build와 Guest source staging은 package가 아니라 clean golden compile이 소유합니다. Package가 현재 Docker registry나 worktree를 다시 읽어 compile material을 바꾸지 않습니다.

`VitalServer Helper`는 최상위 product release입니다. platform별 build는 같은 Helper release 아래의 variant이며, 세부 변경 범위는 Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, VM Image, VitalServer component version으로 설명합니다.

`make devtools/build`는 manifest metadata를 Swift `Bootstrap/Composition/GeneratedVersion.swift`와 Helper app의 `GeneratedRelease.swift`에 반영하고, `make devtools/app`은 app bundle `Info.plist`의 `CFBundleShortVersionString`에 같은 helper version을 씁니다. `make dist/pkg/dev`/`make dist/pkg/release`, `make dist/update/dev`/`make dist/update/release`, `make dist/image-update/dev`/`make dist/image-update/release`는 release manifest 값을 artifact name, package version, update bundle version, compatibility metadata에 반영합니다. `services.*.displayName`은 Helper UI의 service 표시명 source of truth입니다. Artifact identity, 표시명, update compatibility, optional container service 정책은 manifest가 소유합니다. Guest image 변경은 manifest와 immutable Compose/VM Docker plan을 함께 변경하고 release-contract로 대조합니다.

Update bundle manifest는 `schemaVersion: 3`, `channel`, `helperVersion`, `releaseLabel`, `targetPlatform`, `minUpdaterVersion`, `components`를 기준으로 작성합니다. `components`에는 `helperUI`, `updater`, `supervisor`, `vmDriver`, `serviceStack`, `vmImage`, `vitalServer`처럼 실제 변경 범위를 드러내는 version을 넣습니다. platform-specific artifact는 `targetPlatform`과 component version suffix로 제한하고, 공통 Service Stack이나 VM Image는 같은 Helper release 아래에서 platform 간 공유할 수 있습니다.

Layer별 platform dependency도 manifest 설계 기준입니다. Helper UI와 VM Driver는 platform-specific이고, Updater는 host/platform-specific compatibility gate이며, Supervisor는 host/platform-aware health/recovery loop입니다. Service Stack은 guest/service-specific 실행 세트이고, VM Image는 Linux guest OS image artifact입니다.

Update bundle kind는 두 개로 제한합니다.

| bundleKind | 생성 target | UI 위치 | 포함 범위 |
|---|---|---|---|
| `product-update` | `make dist/update/release` | Update 탭 | Helper UI, Native Shell, Runtime Control API, Updater, Supervisor, VM Driver, Service Stack, 개별 service/container, host proxy, migrations |
| `vm-image-update` | `make dist/image-update/release` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifact |

Hotfix, service-only update, updater bridge update는 별도 kind가 아니라 `product-update` metadata로 표현합니다.

## Bundled observer services

기본 Service Stack에는 VitalServer app, Redis, recorder ingress, edge/nginx, Redis UI, Swagger UI와 함께 `vitaldb-observer` container가 포함됩니다. `vitaldb-observer`는 Redis와 proxy/access log를 읽어 recorder/bed/anomaly snapshot을 계산하지만, 자체 SQLite를 소유하지 않습니다. Runtime v2의 최종 observation/read-model SoT는 Guest/Postgres이며, Host runtime observability SQLite는 transitional diagnostics 또는 migration evidence로만 남습니다.

```text
vitaldb-observer
  -> /health
  -> /ready
  -> /api/v1/observations
  -> Guest Control VitalDB writer
  -> Postgres read model
  -> Guest Control API /runtime/vitaldb/*
  -> Runtime Control API /runtime/vitaldb/*
```

Docker image bundle과 guest deploy 대상은 `config/vm-build.toml`이 소유합니다. observer image, Dockerfile, guest deploy `include` 항목을 변경할 때는 Makefile literal을 추가하지 말고 TOML 값을 수정합니다.

## Package 구성

현재 repository의 `make dist/pkg/dev`는 `.pkg`까지 가기 위한 개발 검증용 packaging target입니다. 최종 배포 산출물은 `dist/`에 두고, `.tmp/`는 중간 작업물 전용으로 사용합니다.

```sh
make dist/pkg/dev
make dist/install/dev
make dist/installed/health
make dist/uninstall/dev
```

`make dist/pkg/dev` 생성물:

```text
dist/VitalServerHelper-<version>.pkg
```

패키징 시간이 길면 압축 단계에서 CPU를 더 쓰도록 설정할 수 있습니다. `rootfs-base.raw.gz`와 `vitalserver-images.tar.gz` 생성은 `VM_COMPRESSION_THREADS` 값을 사용합니다.

```sh
VM_COMPRESSION_THREADS=8 make dist/pkg/dev
```

이 설정은 Python/uv package를 병렬화하는 옵션이 아닙니다. 빌드 머신에 `pigz` binary가 있을 때만 병렬 gzip 경로를 사용합니다. `pigz`가 없으면 자동으로 Python gzip fallback을 타며, 이 fallback은 single-thread로 동작합니다.

```sh
command -v pigz
brew install pigz
VM_COMPRESSION_THREADS=8 make dist/pkg/dev
```

정상적으로 병렬 압축을 타면 build log에 아래처럼 표시됩니다.

```text
using pigz compression threads=8
```

아래처럼 표시되면 `pigz`를 찾지 못한 것이고 병렬 압축을 사용하지 않은 것입니다.

```text
using Python gzip compression
```

`pigz`는 build machine 전용 optional accelerator입니다. 최종 `.pkg`, 병원 Mac runtime, air-gapped target 환경에는 설치할 필요가 없습니다. `make -j`는 일부 target을 병렬 실행할 수 있지만, golden VM 부팅과 Swift binary signing이 같은 중간 산출물을 공유하므로 기본 권장 경로는 `VM_COMPRESSION_THREADS`와 `pigz`로 압축 병목을 줄이는 것입니다.

전달용 release DMG가 필요하면 `make dist/dmg/release`를 실행합니다. DMG에는 단일 PKG만 들어갑니다.

```text
dist/VitalServerHelper-<version>.dmg
```

설치 후 구조:

```text
/Applications/VitalServer Helper.app
/usr/local/bin/vitalserver-vm
/usr/local/bin/vitalserver-proxy-run
/usr/local/bin/tirosh-vitalserver-uninstall
/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.vm.plist
/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.proxy.plist
/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.watchdog.plist
/Library/Application Support/VitalServerHelper/
  backups/
  logs/
    install.log
  status/
    runtime-status.json
  vm/
    runtime/
      Image
      initrd.img
      rootfs-base.raw.gz  # immutable package payload
      rootfs-base.raw.gz.manifest.json # rootfs artifact proof sidecar
      vm-disk.img         # install 시 생성되는 mutable rootfs runtime disk
      runtime-data.img    # install 시 생성/보존되는 Docker/containerd runtime data disk
      vm-config.json      # install 시 생성/수정
      seed.iso            # install 시 생성
      runtime-version.json
    data/
      deploy/
      run/
      vital-files/
      vr-release/
    Support/
      Proxy/vitalserver.conf.template
  nginx/
    sbin/nginx
    lib/
      libpcre2-8.0.dylib
      libssl.3.dylib
      libcrypto.3.dylib
    vitalserver.conf # VM IP 확인 후 생성
    logs/
```

shared/NAT mode에서는 VM IP가 부팅 후에 결정됩니다. 그래서 package는 nginx config에 upstream을 미리 박아두지 않습니다.

```text
launchd
  -> ai.tirosh.vitalserver.helper.watchdog
      -> vitalserver-vm runtime watchdog
      -> health snapshot 확인
      -> 필요 시 VM/proxy launchd kickstart
      -> runtime-status.json 갱신

launchd
  -> ai.tirosh.vitalserver.helper.vm
      -> vitalserver-vm start
      -> VM이 /mnt/tirosh/run/runtime-observation.json 기록

launchd
  -> ai.tirosh.vitalserver.helper.proxy
      -> vitalserver-proxy-run
      -> vm-ip bootstrap evidence를 Runtime Control Guest address owner에 publish
      -> Runtime Control Guest address owner read
      -> direct HTTP probes
      -> nginx config 렌더링
      -> nginx start/reload
      -> Guest address owner 변경 감시
```

이 구조에서 운영자가 `VITALSERVER_PROXY_UPSTREAM`을 직접 설정할 필요는 없습니다.

`vm-disk.img`는 sparse disk라 package payload에 그대로 넣으면 `pkgbuild`가 실패할 수 있습니다. 따라서 package에는 immutable base artifact인 `rootfs-base.raw.gz`를 넣고, 설치 시 `postinstall`에서 `vm-disk.img`를 생성합니다.

### Fresh install disk-space contract

새 VM disk와 runtime data disk가 모두 없는 fresh install은 rootfs expansion과
runtime data disk reservation에 필요한 Host Data volume 공간을 **side effect 전에
합산하여 한 번** 확인합니다. 기본 16 GiB runtime data disk에서는 package payload
copy 뒤 약 28 GiB가 필요하므로, Installer를 시작하기 전에는 최소 32 GiB 이상의
여유 공간을 권장합니다. 정확한 값은 package rootfs artifact 크기와 configured
runtime data disk size에 따라 달라집니다.

이 preflight가 실패하면 `gunzip`, temporary disk 제거, VM disk move, `truncate`를
시작하지 않습니다. 오류에는 `operation`, `required`, `available`이 명시되며,
smaller disk나 empty runtime을 만들어 성공처럼 진행하지 않습니다. 이미 VM disk가
있고 runtime data disk만 없으면 runtime data disk requirement만 검사하고, 둘 다
있으면 existing disk validation을 사용합니다. 현장 진단과 안전한 재시도 절차는
[TS-121](../../troubleshooting/121_pkg_install_insufficient_runtime_disk_space.md)를
따릅니다.

직접 배포되는 `.pkg`는 fresh install 전용입니다. 이미 `/Library/Application Support/VitalServerHelper`, Helper app, runtime tools, LaunchDaemon plist, package receipt가 있거나 Host proxy port가 다른 listener에 점유되어 있으면 `preinstall`에서 실패해야 합니다. 기존 설치본의 교체는 Helper app의 update flow가 소유하며, `.pkg` 설치가 기존 `vm-disk.img`나 partially installed runtime을 재사용해서 upgrade처럼 동작하면 안 됩니다.

## DMG Build 흐름

`make dist/dmg/release`는 최종 전달 매체를 만들지만, 실제로는 아래 dependency chain을 실행합니다.

```text
make dist/dmg/release
  -> release branch guard + distribution review
  -> make pwa/build               # Runtime Control PWA static assets
  -> clean golden-rootfs compile  # fresh VM disk -> rootfs-base.raw.gz
  -> vitalserver-devtools release-dmg
     -> release-pkg staging/pkgbuild
     -> hdiutil create
  -> DMG payload readback
  -> golden runtime boot smoke
```

빌드 단계의 원칙은 아래입니다.

| 단계 | 주 책임 구현 | 이유 |
|---|---|---|
| target dependency 연결 | `make/vm/package.mk` | 개발자가 실행할 명령과 산출물 경로를 한 곳에서 노출 |
| Runtime Control PWA build | `apps/vitalserver-runtime-pwa` Vite build | 현장 Mac에는 npm/Vite를 요구하지 않고 static asset만 배포 |
| Ubuntu/cloud-init/rootfs/nginx/Docker/update bundle 생성 | `packages/vitalserver-devtools` Python package | build-machine 전용 작업이고 입력/출력 검증과 unit test가 필요 |
| Swift binary와 Helper app build/sign | SwiftPM, `codesign`, Make target | macOS toolchain과 app bundle 조립이 필요 |
| PKG root staging | Make + filesystem tools | payload 배치가 명령형이고 `pkgbuild` 입력 구조와 1:1 대응 |
| 설치 후 provisioning | Swift `RuntimeLifecycle` | target Mac 상태, launchd, backup/rollback, health를 하나의 runtime source of truth로 관리 |

따라서 `postinstall`이나 Make target에 provisioning 정책을 다시 넣지 않습니다. `postinstall`은 설치 log를 연결한 뒤 `vitalserver-vm runtime install-provision`을 호출하는 wrapper로 유지합니다.

`install-provision`은 package payload, VM disk/config, cloud-init seed, 권한, launchd service 시작 요청까지 담당합니다. runtime이 실제로 healthy인지 판단하는 일은 `postinstall`이 하지 않습니다. Helper app과 Runtime Control API는 explicit Guest/Host read model을 표시하고, `runtime-status.json`은 diagnostics/status projection artifact로 남깁니다. watchdog은 launchd state, VM/bootstrap evidence, Host operation lease, Guest Control readiness, HTTP health를 읽어 recovery 여부를 판단합니다. 따라서 `.pkg` 성공은 "runtime service start가 요청됨"을 뜻하고, "VitalServer backend가 ready"를 뜻하지 않습니다. Provision 완료 status는 active operation이 아니어야 하며, watchdog이 이어서 Guest-owned state를 반영할 수 있어야 합니다.

Guest compose에 선언된 service가 disabled 설정을 가질 수 있어도, compose bind mount source는 release provisioning이 명시적으로 만들어야 합니다. Redis Relay는 문서화된 설치 preset으로 기본 disabled owner document와 `redis-relay-secrets`, `redis-relay-status` directory를 준비해야 guest compose start가 실패하지 않습니다. 설치 뒤 설정과 secret의 읽기·변경·삭제 및 Compose reconcile은 Runtime Controller가 소유하며 Host `configure`나 Control Panel이 파일을 직접 쓰지 않습니다. Disabled는 process 동작 여부이고 Runtime owner contract의 부재를 뜻하지 않습니다.

Fresh install `postinstall`이 실패하면 wrapper는 실패 로그를 `/private/tmp/tirosh-vitalserver-postinstall-failure.log`에 보존한 뒤 이번 package attempt가 만든 product root, Helper app, runtime tools, LaunchDaemon plist, package receipt를 제거합니다. Cleanup은 package nginx 경로로 확인된 orphan host proxy process도 종료합니다. 이 cleanup은 fresh install 경계에서만 동작하며, 외부 `.vital` 경로나 별도 사용자 데이터 경로는 삭제하지 않습니다.

중간 파일과 최종 파일은 아래 위치를 사용합니다.

| 단계 | 경로 | 의미 |
|---|---|---|
| nginx artifact cache | `.artifacts/nginx/macos/bin/nginx` | repository에 commit하지 않는 pinned build input |
| package work dir | `.tmp/vitalserver-vm-pkg/` | PKG staging, rootfs cache, nginx bundle, Docker bundle |
| package root | `.tmp/vitalserver-vm-pkg/root/` | `pkgbuild --root` 입력 |
| app bundle staging | `.tmp/VitalServer Helper.app` | `/Applications` payload로 들어갈 app |
| PWA static build | `apps/vitalserver-runtime-pwa/dist/` | Helper app resource로 들어갈 Runtime Control PWA |
| golden VM home | `.tmp/vitalserver-vm-golden/` | package용 clean rootfs를 만들기 위한 임시 VM home |
| DMG staging | `.tmp/vitalserver-vm-dmg/` | DMG root에 들어갈 파일 배치 |
| PKG output | `dist/VitalServerHelper-<version>.pkg` | installer payload |
| DMG output | `dist/VitalServerHelper-<version>.dmg` | 사용자 전달 매체 |

DMG root에는 `Install VitalServer Helper.pkg`만 둡니다. 사용자는 pkg를 열어 macOS Installer로 설치합니다.

## DMG 설치 흐름

사용자 관점의 설치 순서는 아래입니다.

```text
1. VitalServerHelper-<version>.dmg mount
2. Install VitalServer Helper.pkg 실행
3. macOS Installer가 payload 복사
4. PKG postinstall 실행
5. Swift runtime install-provision이 runtime instance provision
6. launchd VM/proxy/watchdog service 등록 및 정책 적용
7. Helper.app, watchdog, CLI가 status/health 확인
```

실제 코드 호출은 아래처럼 이어집니다.

```text
Install VitalServer Helper.pkg
  -> payload copy
    -> /Applications/VitalServer Helper.app
    -> /usr/local/bin/vitalserver-vm
    -> /usr/local/bin/vitalserver-proxy-run
    -> /Library/Application Support/VitalServerHelper/vm/runtime/rootfs-base.raw.gz
    -> /Library/Application Support/VitalServerHelper/vm/data/deploy/*
    -> /Library/Application Support/VitalServerHelper/nginx/*
    -> /Library/LaunchDaemons/ai.tirosh.vitalserver.helper.*.plist
  -> rendered postinstall from Support/Packaging/postinstall.template
    -> vitalserver-vm runtime install-provision
      -> read /private/tmp/tirosh-vitalserver-install.json if present
      -> create runtime/data/log directories
      -> write deploy/runtime-config.json
      -> gunzip rootfs-base.raw.gz into runtime/vm-disk.img if missing
      -> truncate vm-disk.img to configured diskGiB
      -> write runtime/vm-config.json
      -> create runtime/seed.iso
      -> write runtime/runtime-version.json
      -> chown/chmod installed files
      -> write proxy port into proxy LaunchDaemon plist
      -> launchctl bootstrap/kickstart VM/proxy/watchdog services when startAfterInstall=true
      -> launchctl enable/disable according to startOnBoot
      -> remove install settings JSON
```

VM service가 시작되면 `vitalserver-vm start`가 `vm-config.json`을 읽어 Apple Virtualization VM을 띄웁니다. guest cloud-init은 `seed.iso`의 `runcmd`로 `/mnt/tirosh/deploy/bootstrap.sh`를 실행합니다. guest bootstrap은 Docker image bundle을 load하고 Compose stack 안의 edge nginx container를 구성한 뒤 `/mnt/tirosh/run/runtime-observation.json`에 diagnostics snapshot을, `/mnt/tirosh/run/vm-ip`에 bootstrap Guest address evidence를 기록합니다. proxy service의 `vitalserver-proxy-run`은 loaded bootstrap address를 `PUT /platform/runtime-endpoint`로 Runtime Control owner에 publish하고, host nginx routing address는 `GET /platform/runtime-endpoint` owner read에서만 가져옵니다. Proxy readiness는 direct HTTP probes로 판단합니다. `runtime-observation.json.guestHTTP`는 proxy routing readiness gate가 아니고, `vm-ip`는 routing fallback이 아닙니다. `vm-ip` publish/read failure는 명시 로그와 typed Guest address read failure로 남아야 하며, `runtime-status.json`이나 `runtime-observation.json.vmIP` fallback state를 만들지 않습니다.

설치 시 설정값은 MDM 또는 고급 설치 wrapper가 `installer` 실행 전에 `/private/tmp/tirosh-vitalserver-install.json`에 쓸 수 있습니다. 이 파일은 partial JSON이며 `postinstall` 이후 삭제됩니다. 일반 사용자 설치는 기본값으로 진행하고, 설치 후 Helper app의 Settings에서 runtime 설정을 변경합니다.

Uninstall 로직은 Helper app에 중복 구현하지 않고, 설치된 `/usr/local/bin/tirosh-vitalserver-uninstall`을 관리자 권한으로 호출합니다. Helper app을 열 수 없는 깨진 설치 상태에서는 같은 command를 Terminal 또는 MDM/Jamf에서 root로 실행합니다.

기본 Uninstall은 먼저 VM 안의 Redis volume에서 복구 가능한 Redis backup을 생성합니다. 이 backup이 완료되지 않으면 제거를 중단합니다. 이후 Helper app, LaunchDaemon, runtime tools, uninstaller, VM disk, package receipt를 제거하지만 `.vital` 파일 경로, logs, rollback backups, Redis backups는 보존합니다. Clean Uninstall은 `--clean`을 전달해 Redis backup 생성과 보존 단계를 건너뛰고 VM 영역, logs, backups, Redis backups, 설정된 vital files directory까지 삭제합니다. Helper UI에서 시작한 uninstall은 관리자 승인 후 background uninstaller를 시작했다는 handoff까지만 표시하고 Helper app을 종료합니다. 실제 cleanup 진행과 실패/완료 로그는 root uninstaller가 `/private/tmp/tirosh-vitalserver-uninstall.log`에 기록합니다.

Fresh install 차단 조건과 uninstall 제거 대상은 같은 계약을 따라야 합니다. `preinstall`이 검사하는 `/Library/Application Support/VitalServerHelper`, Helper app, runtime tools, uninstaller, LaunchDaemon plist, loaded launchd service, package receipt, Host proxy port listener가 uninstall 이후 남으면 다음 `.pkg` 설치는 실패해야 합니다. Package receipt는 현재 installer receipt인 `ai.tirosh.vitalserver.helper`만 검사하고 정리합니다.

```text
VitalServer Helper.app
  운영 중:
    Status
    Settings
    Update
    Rollback
    Logs
    Uninstall
    Clean Uninstall

Fallback:
  sudo /usr/local/bin/tirosh-vitalserver-uninstall
  sudo /usr/local/bin/tirosh-vitalserver-uninstall --clean
```

### Troubleshooting Tools recovery artifact

Fresh install이 기존 Host state 때문에 막힌 현장에는 일반 installer와 별도로 reset cleanup만 수행하는 복구 artifact를 전달합니다. 이 artifact는 package가 아니라 DMG와 같은 command 기반 `Troubleshooting Tools` 폴더입니다.

```text
VitalServerHelperTroubleshootingTools-<version>/
```

빌드 target:

```sh
make dist/troubleshooting/dev
make dist/troubleshooting/release
```

이 target은 제품을 설치하거나 update하지 않습니다. DMG와 같은 command 기반 `Troubleshooting Tools` 폴더를 staging하고, command들은 사용자 temp wrapper log와 작업별 root log에 진행 상태와 실패 원인을 남깁니다. GUI를 열 수 없는 깨진 설치 상태를 다루기 위한 artifact이므로 Helper app, Runtime Control API, 기존 설치된 uninstaller가 반드시 살아 있다고 가정하면 안 됩니다.

작성 원칙:

- package를 만들지 않고 `.command` 파일과 필요한 bundled CLI만 제공합니다.
- 사용자가 보는 command 이름은 `Reset VitalServer Helper for Reinstall.command`로 두고, DMG 안에서는 `Troubleshooting Tools` 폴더 아래에 배치합니다.
- reset command entrypoint는 bundled `vitalserver-troubleshooting-reset-for-reinstall`이고, 이 wrapper가 sibling `vitalserver-vm-reset-installer`의 `runtime uninstall --force-clean-uninstaller`를 호출합니다. 별도 설정이나 fallback mode를 숨겨 두지 않습니다.
- 제거 대상은 Vital Server Helper가 소유한 explicit path, LaunchDaemon label, package receipt, runtime process, host proxy listener로 제한합니다.
- clean reset 대상에는 `productRoot` 전체가 포함됩니다. 따라서 product root 아래의 VM pid file, run marker, status documents, runtime state, VM disk, cloud-init seed, logs, rollback backups, Redis backups도 함께 제거됩니다.
- VM pid file이 missing이면 cleanup success로 추정하지 않습니다. force clean recovery는 explicit launchd state를 읽고 VM/sleep-prevention service unload를 계속 시도해야 합니다.
- 외부 nginx, Homebrew, Docker, 사용자 문서, 병원 데이터 경로는 product-owned state로 명시되지 않은 한 제거하지 않습니다.
- 기존 `/usr/local/bin/tirosh-vitalserver-uninstall`이 있으면 같은 uninstall 계약을 사용할 수 있지만, 없거나 실행 불가능한 상태도 명시 failure로 보고해야 합니다.
- fresh install preflight와 reset command 제거 대상은 같은 state contract를 공유해야 합니다.
- 완료 후에도 preflight blocker가 남으면 새 installer가 계속 실패해야 하며, recovery command가 그 blocker를 empty success로 바꾸면 안 됩니다.

## 인터페이스 계약

현재 제품화 흐름은 여러 실행 환경을 건너므로, 각 경계의 입력과 출력 계약을 분리해서 관리합니다.

| 경계 | 호출자 | 피호출자 | 입력 계약 | 출력/부작용 |
|---|---|---|---|---|
| build orchestration | `make/vm.mk` | `vitalserver-devtools` | `vm-build.toml`, source tree, optional Make overrides | `.tmp/vitalserver-vm-pkg/*`, `dist/*` |
| Ubuntu/rootfs build | `make devtools/golden-rootfs` | Python `ubuntu`, `cloud-init`, Swift launcher | Ubuntu cloud image URL, apt snapshot, deploy bundle, Docker image bundle, bootstrap script | clean `vm-disk.img`, compressed `rootfs-base.raw.gz` |
| nginx bundle | `make devtools/nginx/bundle` | Python `nginx-bundle` | pinned macOS nginx binary, expected version | self-contained `nginx/sbin`, `nginx/lib` bundle |
| Docker image bundle | `make devtools/docker/images` | Python `docker-images` | Compose product contract, Dockerfile, image list, deploy includes, build platform | `vitalserver-images.tar.gz` |
| PKG/DMG staging | `vitalserver-devtools release-pkg` / `release-dmg` | Python build CLI, Swift, macOS packaging tools | release manifest, app source, rootfs receipt, compiled Guest deploy material, nginx binary, templates | package root under `.tmp/vitalserver-vm-pkg/root`, `dist/*` |
| install provisioning | PKG `postinstall` | `vitalserver-vm runtime install-provision` | installed payload, optional `/private/tmp/tirosh-vitalserver-install.json` | `vm-disk.img`, `vm-config.json`, `seed.iso`, permissions, launchd services, degraded runtime status until health is observed |
| runtime status | RuntimeLifecycle | `runtime-status.json` | health/install/update/rollback result | diagnostics/status projection |
| runtime progress | RuntimeLifecycle | `runtime-progress.json` | install/update/rollback/restore workflow step result | diagnostics/export progress artifact; not Runtime Control current read model or health/recovery owner |
| VM launch | launchd | `vitalserver-vm start` | `VITALSERVER_VM_HOME`, `VITALSERVER_VM_DETACHED=1`, `runtime/vm-config.json` | Virtualization.framework VM process |
| watchdog | launchd | `vitalserver-vm runtime watchdog` | runtime files, launchd state, VM/bootstrap evidence, Guest Control readiness, HTTP health | runtime status update, VM/proxy kickstart |
| host proxy | launchd | `vitalserver-proxy-run` | Runtime Control Guest address owner read, direct HTTP probes, `vm-ip` owner-publish evidence, proxy template, nginx binary | rendered host nginx config, nginx process |
| guest bootstrap | cloud-init | `bootstrap.sh`, Guest tools wheel | VirtioFS mounts, `runtime-config.json`, Docker bundle | Docker Compose stack, edge nginx container, runtime observation marker |
| update verification | operator/Helper | `vitalserver-vm runtime verify-bundle` | bundle tarball | manifest/checksum validation |
| update apply | operator/Helper | `vitalserver-vm runtime apply-bundle` | verified bundle tarball | staged bundle, backup, artifact replacement, migrations, health check |

이 표가 현재 source of truth입니다. Shell은 installer/launchd wrapper로 제한하고, manifest parsing, checksum 검증, backup, rollback 정책은 Swift runtime lifecycle command가 담당합니다.

Ubuntu/rootfs build는 floating `.../releases/<series>/release` URL을 사용하지 않습니다. 기본 Noble source는 검증한 cloud image serial인 `release-20260518`처럼 고정된 release directory를 가리켜야 합니다. 새 serial이나 Ubuntu series로 바꿀 때는 `boot -> healthy -> prepare update shutdown -> guest poweroff handoff -> VM process exit` 흐름을 반복 검증한 뒤 config를 업데이트합니다. 이 규칙은 rootfs/kernel provenance가 빌드 시점마다 바뀌어 update shutdown failure의 원인을 숨기지 않도록 하기 위한 packaging contract입니다.

### 설치 설정 계약

설치 시 optional settings 파일은 아래 경로를 사용합니다.

```text
/private/tmp/tirosh-vitalserver-install.json
```

파일이 없으면 기본값을 사용합니다.

| 설정 | 기본값 | 현재 계약 |
|---|---:|---|
| `cpuCount` | 8 | 7-64 |
| `memoryGiB` | 8 | 4-64 GiB, 4 GiB 단위 |
| `diskGiB` | 32 | 4-512 GiB, 4 GiB 단위. 설치 후에는 증가만 허용 |
| `networkMode` | `shared` | `shared` 또는 `bridged` |
| `proxyPort` | 80 | 1-65535, LaunchDaemon plist에 저장하고 Runtime CLI/Helper가 해당 값을 읽음 |
| `vitalFilesDirectory` | `/Library/Application Support/VitalServerHelper/vm/data/vital-files` | absolute path |
| `adminPassword` | `admin` | admin 계정 reset 값. empty가 아니면 guest runtime에 적용 |
| `vmHostname` | `tirosh-vitalserver` | hostname-safe 문자열 |
| `sshAuthorizedKeys` | `[]` | optional OpenSSH public key 배열. 제공한 key만 cloud-init `ubuntu` 계정에 등록하며 password SSH는 항상 비활성화 |
| `vitalServerURL` | empty | optional absolute `http`/`https` URL. Reverse proxy/HTTPS/domain 운영 시 Status와 runtime advertised URL에 사용 |
| `remoteConsoleURL` | empty | optional absolute `http`/`https` URL. Remote Console이 VitalServer와 다른 도메인일 때 사용 |
| `publicHost` | empty | legacy guest compatibility field. `vitalServerURL`이 있으면 Host가 host를 파생 |
| `publicPort` | 80 | legacy guest compatibility field. `vitalServerURL`이 있으면 Host가 port를 파생 |
| `startAfterInstall` | true | bool |
| `startOnBoot` | true | bool |

현재 settings JSON은 partial override 계약입니다. 파일을 제공하는 installer UI, MDM, 또는 설치 wrapper는 바꾸고 싶은 필드만 쓰면 됩니다. 누락된 필드는 기본값을 사용합니다. 기존 numeric/URL 범위를 벗어난 값은 무시하지만, `sshAuthorizedKeys`처럼 보안 접근 경로를 여는 값이 제공됐는데 형식이 맞지 않으면 설치 설정 로드가 실패합니다.

예시:

```json
{
  "cpuCount": 8,
  "memoryGiB": 16,
  "diskGiB": 128,
  "proxyPort": 8080,
  "vitalFilesDirectory": "/Users/Shared/TiroshVitalFiles",
  "adminPassword": "change-me",
  "sshAuthorizedKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test"
  ],
  "vitalServerURL": "https://vitaldb.tirosh.ai/",
  "remoteConsoleURL": "https://console.tirosh.ai/",
  "startAfterInstall": true,
  "startOnBoot": true
}
```

설치 wrapper는 `installer` 실행 전에 이 파일을 씁니다.

```sh
sudo install -m 0600 /path/to/install-settings.json /private/tmp/tirosh-vitalserver-install.json
sudo installer -pkg dist/VitalServerHelper-<version>.pkg -target /
```

개발용 Make target은 같은 계약을 `VM_INSTALL_SETTINGS`로 감쌉니다.

```sh
VM_INSTALL_SETTINGS=/path/to/install-settings.json make dist/install/dev
```

`postinstall`이 설정을 읽어 runtime provisioning에 반영한 뒤 settings 파일을 삭제합니다.

### Proxy Port 계약

v1 기본 proxy port는 80입니다.

```text
external client
  -> target Mac host nginx :80
  -> Linux VM edge nginx :80
  -> VitalServer container :18080
```

`proxyPort`는 설치 설정과 LaunchDaemon environment로 전달됩니다. Runtime CLI와 Helper app은 설치된 proxy LaunchDaemon plist에서 `VITALSERVER_PROXY_PORT`를 읽어 health/open URL에 반영합니다.

```text
install settings JSON
  -> postinstall
  -> proxy LaunchDaemon EnvironmentVariables:VITALSERVER_PROXY_PORT
  -> vitalserver-proxy-run
  -> RuntimeLifecycle status/health
  -> Helper app health/open URL
```

### Update Bundle 계약

`make dist/update/release`는 현재 아래 artifact를 만들 수 있습니다.

| artifact type | 생성 여부 | Swift verify | Swift apply |
|---|---:|---:|---:|
| `rootfs-base` | `make dist/image-update/release`에서만 포함 | 예 | `rootfs-base.raw.gz` 교체 |
| `app-bundle` | 기본 포함 | 예 | `/Applications/VitalServer Helper.app` 교체 |
| `runtime-tools` | 기본 포함 | 예 | `/usr/local/bin` Updater/Supervisor/VM Driver tools 교체 |
| `nginx-bundle` | 기본 포함 | 예 | host nginx bundle 교체 |
| `guest-deploy` | 기본 포함 | 예 | VM shared deploy bundle 교체 |
| `migration` | optional | 예 | executable이면 순차 실행 |

따라서 현재 update apply의 실제 효과는 아래입니다.

```text
verify bundle
stage bundle
backup managed artifacts/runtime-version
stop services
replace app/runtime-tools/nginx/guest-deploy artifacts
replace rootfs-base only when the bundle includes rootfs-base
run executable migrations
write runtime-version.json
restart services if previously running
health check
rollback on failure
```

중요한 제약은 `rootfs-base.raw.gz`와 `vm-disk.img`의 역할 차이입니다.

```text
rootfs-base.raw.gz = immutable base artifact
vm-disk.img        = installed mutable runtime instance
```

update에서 rootfs base를 교체해도 기존 `vm-disk.img` 내부 OS와 application runtime은 자동으로 교체되지 않습니다. 이미 설치된 VM 내부를 바꾸는 작업은 migration, guest deploy 변경, Docker image bundle 갱신 같은 별도 artifact로 정의해야 합니다.

설치 테스트는 실제 시스템 경로를 사용합니다.

| 경로 | 내용 |
|---|---|
| `/usr/local/bin` | VM launcher/runtime lifecycle CLI, proxy runner |
| `/Library/LaunchDaemons` | VM/proxy 자동 실행 plist |
| `/Library/Application Support/VitalServerHelper` | VM image, deploy bundle, nginx runtime |
| `/Library/Application Support/VitalServerHelper/logs/install.log` | installer provisioning log, 10 MiB 기준 rotation |
| `/Library/Application Support/VitalServerHelper/status/runtime-status.json` | diagnostics/status projection |
| `/Library/Application Support/VitalServerHelper/status/runtime-progress.json` | diagnostics/export workflow progress artifact; Helper/API current read model이나 health/recovery 입력 아님 |

repo에서 개발 설치를 검증할 때는 설치 후 `make dist/installed/health`로 launchd load 상태, VM IP, guest HTTP, host proxy HTTP를 확인합니다. pkg만 전달받은 설치 환경에서는 Helper app Status 탭이나 설치된 `vitalserver-vm` CLI를 사용합니다.

개발 중 설치/제거를 반복할 때는 `make dist/uninstall/dev`를 사용합니다. 이 target은 `/Library/Application Support/VitalServerHelper`, 관련 LaunchDaemon plist, `/usr/local/bin/vitalserver-*`를 제거하므로 운영 환경에서는 사용하지 않습니다.

설치된 Mac mini/Mac Studio에서 사용자가 CLI로 제거할 때는 아래 명령을 사용합니다.

```sh
sudo tirosh-vitalserver-uninstall
```

이 명령은 Redis backup을 생성한 뒤 VM/proxy/guest-log-sync/watchdog LaunchDaemon을 unload하고, package가 설치한 runtime 파일과 Helper app을 제거합니다. 기본 모드는 `.vital` 파일 경로, logs, rollback backups, Redis backups를 보존합니다. 완전 삭제가 필요하면 `sudo tirosh-vitalserver-uninstall --clean`을 사용합니다. Clean Uninstall은 Redis backup 보존 없이 VM 영역과 backup 영역까지 제거합니다. GUI 제품에서는 Helper app의 “Uninstall”과 “Clean Uninstall”이 background uninstaller를 시작한 뒤 종료합니다. 삭제 완료 여부는 `/private/tmp/tirosh-vitalserver-uninstall.log`를 확인합니다.

`.pkg`로 재설치하려면 먼저 uninstall 또는 clean uninstall을 완료해야 합니다. `preinstall`은 stale install artifact를 정리하지 않고 설치 실패로 보고합니다. 삭제와 재설치 책임을 분리해야 fresh install과 update가 서로의 state를 추정하지 않습니다.

### nginx release artifact

`make dist/pkg/dev`와 `make dist/pkg/release`는 package에 넣을 macOS nginx bundle까지 포함해서 만듭니다. `make devtools/nginx/bundle`은 기본적으로 build machine의 nginx를 release artifact cache로 복사한 뒤, `config/vm-build.toml`의 `[nginx]` 설정으로 bundle을 만듭니다. 기본 artifact 경로는 아래입니다.

```text
.artifacts/nginx/macos/bin/nginx
```

이 파일은 repository에 commit하지 않는 build-machine 입력 cache입니다. 로컬 unsigned build에서는 Homebrew nginx를 자동으로 복사해 release artifact를 만듭니다.

```sh
make devtools/nginx/bundle
```

기본 source binary는 `/opt/homebrew/opt/nginx/bin/nginx`입니다. 다른 위치에서 artifact cache를 만들려면 source path를 명시합니다.

```sh
VM_NGINX_SOURCE_BIN=/path/to/nginx make devtools/nginx/artifact
```

build tooling은 이 binary의 `nginx -v` 출력이 선택된 release manifest의 `services.hostProxy.image`와 맞는지 확인한 뒤, 실행 파일과 비시스템 dylib를 package 내부로 복사합니다. artifact cache가 없거나 release manifest와 맞지 않으면 `source_binary_path`에서 캐시를 다시 채웁니다.

```text
nginx/sbin/nginx
  -> @executable_path/../lib/libpcre2-8.0.dylib
  -> @executable_path/../lib/libssl.3.dylib
  -> @executable_path/../lib/libcrypto.3.dylib
  -> /usr/lib/libz.1.dylib
  -> /usr/lib/libSystem.B.dylib
```

즉 운영 target Mac에 Homebrew가 없어도 host proxy가 뜰 수 있는 구조입니다. 임시로 다른 binary를 bundle 입력으로 직접 쓰려면 명시적으로 override합니다. 이 경우 artifact cache 생성 단계는 건너뜁니다.

```sh
VM_NGINX_BIN=/path/to/nginx \
make devtools/nginx/bundle
```

air-gapped 제품 package는 외부 Docker registry 없이 container를 시작할 수 있어야 합니다. 현재 package flow는 `make devtools/docker/images`로 아래 image를 하나의 bundle로 만들고, 설치 후 guest bootstrap에서 `docker load`를 먼저 수행합니다.

```text
vitalserver:2.3.4
redis:3.2.12-alpine
ghcr.io/joeferner/redis-commander:0.9.0
swaggerapi/swagger-ui:v5.17.14
nginx:1.24-alpine
```

Docker image bundle은 guest VM architecture에 맞춰 `linux/arm64`로 생성합니다. Apple Virtualization Framework 기반 guest가 arm64 Ubuntu로 부팅되므로, amd64 image를 넣으면 guest에서 `exec format error`가 발생합니다. Redis Commander는 Docker Hub의 `latest`가 아니라 GHCR의 pinned multi-arch image를 사용합니다.

Golden rootfs compile은 Docker image bundle을 먼저 만들고 guest deploy bundle에 포함한 뒤, rootfs smoke의 `docker-service` stage에서 Docker daemon을 명시 시작하고 `docker-image-load` stage에서 `docker load`로 검증합니다. Compose smoke가 registry pull에 성공해서 통과하는 것은 air-gapped proof가 아니므로 rootfs artifact proof로 인정하지 않습니다.

생성/설치 경로는 아래와 같습니다.

```text
.tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz
/Library/Application Support/VitalServerHelper/vm/data/deploy/docker-images/vitalserver-images.tar.gz
```

Docker image만으로는 충분하지 않습니다. Guest VM이 처음 부팅될 때 `docker.io`, Docker Compose 같은 runtime package를 apt로 설치해야 한다면 air-gapped 환경에서 실패합니다. 그래서 제품용 package는 개발용 VM disk가 아니라 별도 golden VM home에서 만든 clean rootfs base를 사용합니다. VM 내부 edge nginx는 OS package가 아니라 `nginx:1.24-alpine` container로 실행합니다. Golden rootfs의 Ubuntu cloud image URL과 apt snapshot은 `config/vm-build.toml`의 `guest.ubuntu.base_url`, `guest.ubuntu.apt_snapshot`이 함께 소유합니다.

```sh
make devtools/golden-rootfs
make dist/pkg/dev
```

기본 package용 rootfs는 `8G`(8 GiB)입니다. `VM_ROOTFS_SIZE`의 `G` suffix는 build tool 입력 형식이며 GiB 기준으로 해석합니다. `make devtools/golden-rootfs`는 `.tmp/vitalserver-vm-golden` 아래에서 VM을 임시로 띄우고 `prepare-airgap-rootfs.sh`만 실행한 뒤 `.tmp/vitalserver-vm-pkg/rootfs-base.raw.gz`를 생성합니다. 이 스크립트는 OS package를 설치하고 `/mnt/tirosh/run/rootfs-ready` marker와 `/mnt/tirosh/run/rootfs-runtime-manifest.json` manifest를 기록한 뒤 종료됩니다. Manifest의 apt plan runId/snapshot proof, Docker service start, runtime version, Docker image load, Docker smoke, disk-space, compose build/up, edge-ready, cleanup stage가 모두 통과하지 않으면 rootfs 압축 단계는 실패해야 합니다. 이 smoke는 disposable container start와 실제 deploy Compose stack readiness를 검증하며 운영 Redis volume을 golden rootfs에 섞지 않습니다.

Kernel panic, ext4 read-only remount, `docker-image-load` timeout은 resource를 낮춰 우회하지 않고 terminal compile failure proof로 기록합니다.

Fresh install bootstrap도 Docker image bundle을 로드한 직후 `redis:3.2.12-alpine` smoke container를 `--network none`으로 실행합니다. 이 단계가 실패하면 `bootstrap-result.json`은 `guest-bootstrap-docker-runtime-failed` reason code를 기록하고 compose up으로 진행하지 않습니다. Docker version 출력이나 compose binary 존재만으로는 rootfs가 준비됐다고 보지 않습니다.

반복 개발 중에는 receipt와 fingerprint가 모두 같은 golden rootfs cache만 재사용합니다. cache가 없거나 contract input, effective build config, rootfs size, receipt가 달라지면 `make dist/pkg/dev`도 이전 golden disk를 이어 쓰지 않고 새 Ubuntu base에서 다시 만듭니다. VM build를 제품 compile로 보고 clean golden rootfs부터 다시 만들려면 profile target을 사용합니다. 캐시 재사용은 빠른 packaging target의 의미이고, `compile` target의 의미가 아닙니다.

```sh
make dist/pkg/dev/compile
make dist/dmg/dev/compile
```

release 검증처럼 clean rootfs와 release branch guard를 함께 적용하려면:

```sh
make dist/pkg/release
make dist/dmg/release
```

VM compile 여부는 profile target이 소유합니다. 동일 의미의 긴 `VAR=value` 호환 명령은 유지하지 않습니다. 특히 `dist/dmg/dev/compile`의 clean 의미를 변수로 끄지 않습니다. 현장 전달에는 `make dist/dmg/dev`를 사용하고, cache-preferred 개발 산출물만 필요하면 `make dist/dmg/dev/cached`를 사용합니다.

## Update Bundle

온라인/오프라인 업데이트는 같은 bundle tarball을 입력으로 사용합니다.

```sh
make dist/update/release
make dist/update/verify/release
```

VM Image/rootfs/base OS까지 포함하는 업데이트는 별도 target을 사용합니다. 이 bundle은 `vm-image-update`로 취급하고 Danger Zone에서 다룹니다.

```sh
make dist/image-update/release
make dist/image-update/verify/release
```

`make dist/update/release`는 Product Update artifact staging을 `packages/vitalserver-devtools` CLI에서 수행하고 `app-bundle.tar.gz`, `runtime-tools.tar.gz`, `nginx-bundle.tar.gz`, `guest-deploy.tar.gz`를 기본 포함합니다. `app-bundle.tar.gz`에는 Swift Helper app과 Runtime Control PWA static assets (`Contents/Resources/runtime-control-pwa`)가 함께 들어갑니다. 따라서 Helper UI, PWA UI, Native Shell, Runtime Control API, Updater/Supervisor/VM Driver tools, host nginx, Service Stack/guest deploy bundle까지 같은 online/offline Product Update 계약으로 배포할 수 있습니다.

update bundle도 압축이 필요합니다. 다만 압축 대상은 update artifact 단위입니다. 일반적인 현장 업데이트는 작은 `.tar.gz` artifact를 교체하는 흐름이고, 무거운 `rootfs-base.raw.gz`를 매번 다시 압축하거나 배포하는 흐름이 아닙니다.

| artifact | 압축 파일 | Product Update 포함 여부 | 비고 |
|---|---|---|---|
| Helper UI + Runtime Control PWA | `app-bundle.tar.gz` | 기본 포함 | `/Applications/VitalServer Helper.app` 교체. PWA는 app resource static asset으로 포함 |
| Updater/Supervisor/VM Driver tools | `runtime-tools.tar.gz` | 기본 포함 | `/usr/local/bin` local control tools 교체 |
| host nginx bundle | `nginx-bundle.tar.gz` | 기본 포함 | host proxy binary/dylib 교체 |
| Service Stack / guest deploy bundle | `guest-deploy.tar.gz` | 기본 포함 | VM shared deploy script/config, compose, container image bundle 교체 |
| migration | executable files | 기본 포함 | cloud-init seed refresh 등 설치된 VM/runtime 상태 변경 |
| Docker images | `vitalserver-images.tar.gz` | 필요 시 포함 | container image 갱신이 있을 때만 무겁게 포함 |
| VM Image / rootfs base | `rootfs-base.raw.gz` | `make dist/image-update/release`에서만 포함 | 신규 설치 또는 base OS/package 변경용. 기존 `vm-disk.img`를 자동 교체하지 않음 |

따라서 “bundle을 만든다”는 것은 보통 작은 product artifact를 압축해 묶는다는 뜻입니다. rootfs나 Docker image 갱신이 없는 Product Update bundle은 package build보다 훨씬 가벼워야 합니다.

기본 update bundle에는 `apps/vitalserver-macos-runtime/Support/Build/migrations` 아래의 기본 migration들이 포함됩니다. 구버전 Helper가 bundle을 적용해도 이 migration은 실행되므로, 새 `guest-deploy/bootstrap.sh`가 다음 VM 부팅에서 실행될 수 있습니다.

추가 마이그레이션 실행 파일을 bundle에 포함하려면 build CLI를 직접 호출합니다.

```sh
uv run --project packages/vitalserver-devtools vitalserver-devtools \
  --config config/vm-build.toml \
  release-update-bundle \
  --release-file apps/vitalserver-macos-runtime/release.json \
  --migration release/migrations/001-example
```

생성물:

```text
dist/update-bundles/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
```

tarball 내부 구조:

```text
update-bundle-<channel>-<kind>-<releaseLabel>/
  manifest.json
  checksums.txt
  signature
  app-bundle.tar.gz
  runtime-tools.tar.gz
  nginx-bundle.tar.gz
  guest-deploy.tar.gz
  migrations/
```

`make dist/image-update/release`로 만든 bundle에는 위 목록에 `rootfs-base.raw.gz`가 추가됩니다.

`manifest.json`은 `schemaVersion: 3`을 사용합니다. `channel`, `helperVersion`, `releaseLabel`은 required입니다. `helperVersion`은 package-safe numeric version이고, `releaseLabel`은 dev/stable artifact identity입니다. `artifacts`와 `migrations`는 모두 `checksums.txt`와 manifest 자체의 sha256/size 값으로 검증됩니다.

현재 `signature`는 `unsigned` placeholder입니다. 이 파일은 호환 레이어가 아니라 bundle 계약의 고정 자리이며, release hardening 단계에서 실제 signature 검증으로 교체합니다.

설치된 Mac mini/Mac Studio에서는 Swift runtime lifecycle command가 bundle을 검증하고 적용합니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime stage-bundle /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
sudo /usr/local/bin/vitalserver-vm runtime rollback
```

`apply-bundle`은 mutable `vm-disk.img`를 보존하고, replaceable artifact만 backup/rollback 대상으로 삼습니다. 적용 전 backup을 만들고 VM/proxy를 중지한 뒤 artifact를 교체하고 executable migration을 순서대로 실행합니다. 새 runtime은 `guest-deploy`가 포함된 update에서 cloud-init seed를 갱신하고 Guest Control update activation operation을 생성해 VM 내부 Docker image load와 compose recreate를 수행합니다. 기존에 서비스가 실행 중이었다면 재시작 후 health check를 통과해야 성공 처리합니다. migration 또는 health check 실패 시 `rollback`으로 직전 backup을 복원합니다.

지원 artifact type:

| type | artifact name | 적용 대상 |
|---|---|---|
| `rootfs-base` | `rootfs-base.raw.gz` | `vm-image-update` bundle에 포함된 경우에만 이후 provisioning 기준 rootfs base 교체 |
| `app-bundle` | `app-bundle.tar.gz` | `/Applications/VitalServer Helper.app` |
| `runtime-tools` | `runtime-tools.tar.gz` | `/usr/local/bin` Updater/Supervisor/VM Driver tools |
| `nginx-bundle` | `nginx-bundle.tar.gz` | host nginx bundle |
| `guest-deploy` | `guest-deploy.tar.gz` | VM shared deploy bundle |

### Guest deploy 변경 반영 정책

`guest-deploy.tar.gz`는 host shared directory의 `vm/data/deploy`를 교체합니다. 여기에 `bootstrap.sh`, `guest-tools.toml`, compose, guest bin/systemd, Docker image bundle이 포함됩니다. 단순 파일 교체만으로 VM 내부 Docker daemon이나 systemd unit이 자동 갱신되는 것은 아니므로, update bundle은 아래 경로로 반영합니다.

```text
apply-bundle
  -> guest-deploy 교체
  -> 기본 migration으로 seed.iso 갱신
  -> VM 재시작 시 bootstrap.sh 재실행
  -> 새 runtime이면 Guest Control update activation operation 생성
  -> VM 내부에서 Docker image load + compose recreate
  -> Guest Control stack status와 bootstrap result 갱신
```

따라서 `bootstrap.sh` 같은 guest deploy 수정은 새 update bundle을 만들면 포함됩니다. 이미 설치된 현장에서는 해당 bundle을 적용해야 실제 `/Library/Application Support/VitalServerHelper/vm/data/deploy`와 VM 내부 runtime에 반영됩니다.

설치 후 runtime 설정 변경은 아래 command가 source of truth입니다.

```sh
sudo /usr/local/bin/vitalserver-vm runtime configure \
  --cpu 8 \
  --memory-gib 8 \
  --network shared \
  --bridged-interface "<interface-id-if-bridged>" \
  --proxy-port 80 \
  --vital-files-dir "/Library/Application Support/VitalServerHelper/vm/data/vital-files" \
  --vitalserver-url "http://127.0.0.1:80/" \
  --remote-console-url "http://127.0.0.1:18321/" \
  --public-host "127.0.0.1" \
  --public-port 80 \
  --start-on-boot true \
  --admin-password-file "/private/tmp/admin-password" \
  --restart
```

이 command는 SQLite `host_runtime_settings`에 desired revision을 먼저 저장하고, `vm-config.json`, deploy `runtime-config.json`, `runtime-settings.json`을 boot materialization으로 생성·재검증한 뒤 proxy LaunchDaemon plist와 launchd enable/disable 정책을 갱신합니다. `--restart`는 같은 configure 요청에서 실제로 변경된 구성요소만 activation합니다. Apply로 이미 저장된 설정을 나중에 활성화하는 Helper의 `Restart VM Runtime` 액션은 별도 typed intent인 `--restart-vm-runtime`을 사용합니다. 이 명령은 현재 파일 diff가 없어도 `restartAfterSettingsApply` VM workflow를 실행하며, Platform Agent를 포함한 전체 repair를 호출하지 않습니다. 새 VM lifecycle run ID와 materialized settings revision을 결합하고 runtime health가 통과한 뒤에만 desired payload를 applied payload로 복사하고 applied revision을 갱신하므로, 성공 반환은 실제 재시작과 설정 적용 증명을 포함합니다. VM start, lifecycle binding, health 중 하나라도 실패하면 applied revision/payload는 이전 값으로 남고 command는 실패합니다. Schema v6처럼 applied revision만 있고 당시 payload가 없는 설치는 v7 migration에서 그 증명을 명시적으로 무효화해 `Requires VM restart`로 유지하며, 현재 desired payload나 `applied-vm-config.json`으로 추정하지 않습니다. Fresh-install 기본 `runtime-config.json`은 `publicHost`, `publicPort`, `vitalServerURL`, `remoteConsoleURL`이 서로 일치해야 하며 writer는 저장 전에 encode/decode round trip을 검증합니다. Helper UI는 advertised service URL 입력에 local 기본 URL을 채우며, Apply 시 빈 값이나 absolute `http`/`https` URL 형식이 아닌 값은 실패시킵니다. remote client가 접속해야 하는 운영 환경에서는 `127.0.0.1` 기본값을 외부에서 도달 가능한 URL로 바꿔야 합니다. Helper app의 admin password 입력은 기존 값을 표시하지 않고, 운영자용 admin password reset을 선택했을 때만 `/private/tmp` 아래 0600 임시 파일을 만들고 `--admin-password-file`을 전달합니다. CLI의 `--admin-password`는 개발/수동 복구용으로 남기지만, 운영 UI에서는 argv/log 노출을 줄이기 위해 file 입력을 사용합니다.

Authoritative Host runtime state는 단계적으로 `runtime/runtime-state.sqlite`로 이전합니다. JSON/JSONL은 diagnostics projection 또는 SQLite 설정에서 생성한 boot contract이며 fallback state source가 아닙니다. Aggregate cutover가 완료되면 packaging은 DB schema/readiness와 boot document round-trip proof가 완료되기 전에 서비스를 시작하면 안 됩니다. 현재 cutover 상태와 상세 ownership 규칙은 [Host runtime state persistence](host-runtime-state-persistence.md)를 참고합니다.

Golden-rootfs, runtime-smoke, local dev VM도 installed launcher와 같은 Host settings owner 계약을 사용합니다. `internal/vm/stage`는 Guest deploy가 `vm-config.json`, `runtime-config.json`, `runtime-settings.json`을 모두 배치한 뒤 restart 없는 `runtime configure`를 호출하여 workspace의 `runtime-state.sqlite`를 초기화하고 materialized revision을 증명해야 합니다. 이 단계가 없으면 launcher는 JSON을 fallback으로 읽지 않고 시작 전에 실패합니다. 증상과 확인 절차는 [TS-132](../../troubleshooting/132_golden-rootfs-launcher-missing-host-settings-sqlite.md)를 참고합니다.

Golden rootfs 종료와 압축은 같은 Host lifecycle owner를 사용합니다. 종료 wait는 SQLite `vm_lifecycle.state=stopped`와 해당 `VM_HOME`의 launcher process 부재를 모두 확인하고, rootfs 압축도 같은 SQLite stopped proof와 process 부재를 독립적으로 검증합니다. `run/vm-lifecycle.json`은 diagnostic projection이며 disposable Golden VM에서 생성되지 않아도 됩니다. SQLite cutover 뒤 압축만 JSON을 요구하던 실패는 [TS-138](../../troubleshooting/138_golden-rootfs-compression-requires-removed-lifecycle-json.md)을 참고합니다.

Runtime repair와 uninstall은 같은 service set을 사용하지 않습니다. Runtime repair/stop은 `RuntimeManagedService.stopOrder`만 내리므로 Platform Agent control plane을 유지합니다. Graceful uninstall과 force-clean recovery는 전용 stop 계약에서 `uninstallOrder`를 사용해 Platform Agent를 마지막에 내리고, readiness도 같은 service set을 검증합니다. HostCLI health는 Platform API listener가 아니라 SQLite `vm_lifecycle` owner를 직접 읽습니다. Runtime stop 경계는 [TS-131](../../troubleshooting/131_settings-vm-restart-invalid-config-and-platform-agent-stop.md), uninstall 회귀와 검증 규칙은 [TS-136](../../troubleshooting/136_clean-uninstall-leaves-platform-agent-loaded.md)을 참고합니다.

admin password reset은 VitalServer 본체의 사용자 계정 기능을 확장하거나 수정하는 기능이 아닙니다. VitalServer UI의 비밀번호 변경은 현재 비밀번호를 아는 사용자가 본인 계정을 변경하는 흐름이고, Helper의 reset은 설치/운영 관리자가 `admin` 계정을 복구하거나 초기화하기 위한 패키징 레벨의 유지보수 기능입니다. 위험도가 높은 설정이므로 향후 운영 정책에 따라 Helper UI에서 제거하고 CLI 또는 recovery flow로만 남길 수 있습니다. deploy `runtime-config.json`은 admin reset 값을 포함하므로 install/configure 직후 0600 권한으로 제한합니다.

설치 후 Helper에서 바로 변경하는 범위와 별도 기능으로 분리해야 하는 범위는 아래처럼 구분합니다.

| 범위 | 처리 |
|---|---|
| CPU, memory, network, bridged interface | `vm-config.json` 갱신 후 restart |
| proxy port | proxy LaunchDaemon environment 갱신 후 restart |
| Vital files directory | VM shared directory와 guest runtime config 갱신 후 restart |
| advertised URLs, admin password reset | guest `runtime-config.json`/`runtime-settings.json` 갱신 후 restart |
| start on boot | `launchctl enable/disable system/<label>`로 VM/proxy/watchdog 정책 갱신 |
| disk size | 별도 resize/migration flow 필요 |
| VM hostname | `seed.iso`/guest hostname 재생성 또는 guest migration flow 필요 |

rootfs base 교체는 이후 install/provisioning 기준 artifact를 바꾸는 동작입니다. 이미 생성된 `vm-disk.img` 내부에 새 rootfs를 자동 전개하지 않습니다.

Shell은 installer/launchd wrapper로만 남깁니다. Bundle manifest parsing, checksum 검증, backup, rollback 정책은 Swift runtime lifecycle command가 담당합니다.

남은 제품화 항목은 아래입니다.

Swagger UI는 VM guest deploy bundle의 `deploy/docs`를 읽어 multi-spec catalog를 제공합니다. 기본 포함 spec은 `api/vitalserver.openapi.yaml`(VitalServer), `runtime/runtime-control.openapi.json` (Runtime Control API), `api/recorder-ingress.openapi.yaml`(Recorder Ingress API)입니다. macOS bundle은 Runtime Control API를 기존 `/swagger/docs/macos-runtime/runtime-control.openapi.json` 경로에도 복사해 호환성을 유지합니다. 기존 `/swagger/openapi.yaml` 호환 경로는 유지합니다.

| 항목 | 필요한 이유 |
|---|---|
| Developer ID signing | launchd/Virtualization binary 배포 신뢰성 확보 |
| notarization | Gatekeeper 환경에서 설치 마찰 감소 |
