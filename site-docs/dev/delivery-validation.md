# Delivery & Validation

이 문서는 Vital Server Helper를 만들고, 검증하고, release 전에 확인하는 기준을 정리합니다.

목표는 단순히 build가 성공했는지 보는 것이 아닙니다. 설치 파일, update bundle, guest service,
testkit이 같은 기준으로 검증되고, 실패했을 때 원인을 다시 찾을 수 있어야 합니다.

## 1. 무엇을 확인하나

Delivery는 사용자가 받는 결과물을 준비하는 일입니다. Validation은 그 결과물이 실제로 동작하는지
확인하는 일입니다.

Vital Server Helper는 Mac app 하나만 배포하지 않습니다. macOS Helper package, Linux guest service,
Docker image bundle, update bundle, reset command까지 함께 다룹니다. 병원이나 연구실처럼
네트워크 접근이 제한될 수 있는 환경에서도 같은 절차로 확인할 수 있어야 합니다.

### 1-1. 기본 원칙

| 원칙 | 뜻 |
|---|---|
| 같은 결과물은 같은 절차로 검증 | release machine이 달라도 검증 기준은 같아야 함 |
| 실패는 남긴다 | build 실패, health 실패, rollback 실패는 기록으로 남김 |
| 상태를 섞지 않는다 | missing, invalid, failed, stale, empty를 서로 바꾸지 않음 |
| 문서와 구현을 같이 본다 | 운영 절차가 바뀌면 release/dev 문서도 함께 바뀜 |
| VM build는 product compile | kernel panic, guest boot failure, rootfs proof failure, runtime smoke failure를 숨기지 않음 |
| VM compile input은 증명한다 | Ubuntu image URL, apt snapshot, rootfs runId, guest failure marker, apt plan, smoke manifest를 compile proof로 확인 |

### 1-2. 결과물이 하나가 아닌 이유

Helper는 Host와 Guest를 함께 다룹니다. Host는 Mac에서 app, proxy, process, file을 관리하고,
Guest는 Vital Server service stack을 실행합니다.

그래서 release 결과물도 여러 개입니다. 일반 app update와 VM image update도 구분해야 합니다.
일반 update에 rootfs 교체를 섞으면 rollback과 장애 원인 추적이 어려워집니다.

## 2. 무엇을 만들까

Release 전에 만드는 결과물은 목적이 다릅니다. 먼저 “어떤 상황에서 쓰는 파일인가”를 구분합니다.

### 2-1. Release 결과물

| 결과물 | 쓰는 상황 |
|---|---|
| DMG | 신규 Mac에 Helper를 설치할 때 |
| PKG | macOS installer가 실제로 설치하는 payload |
| Reset command | 재설치가 막힌 Mac에서 관련 데이터와 기능을 강제로 정리할 때 |
| Existing VitalServer data import command | 기존 VitalServer data directory를 Helper import용 archive로 만들 때 |
| Product Update bundle | Helper UI, runtime tools, proxy, service stack을 update할 때 |
| VM Image update bundle | guest rootfs/base image class를 바꿀 때 |
| Docker image bundle | 네트워크가 제한된 guest에서 service stack을 실행할 때 |
| guest deploy bundle | guest 내부 service activation에 필요한 입력 |

### 2-2. 릴리스 작업용 명령어

아래 명령어는 릴리스 담당자가 build machine에서 결과물을 만들고 검증할 때 사용합니다.
현장 Mac에서는 이 `make` 명령어를 실행하지 않습니다. 현장에는 생성된 DMG, PKG, update bundle을
전달하고, reset command와 existing VitalServer data import command는 DMG의 `Troubleshooting Tools` 폴더에서 실행합니다.

| 목적 | command |
|---|---|
| release DMG 현장 전달 gate | `make dist/dmg/release` (review → release-contract → environment preflight → PWA build → clean compile → artifact verify → runtime smoke) |
| release Troubleshooting Tools 생성 | `make dist/troubleshooting/release` |
| release Product Update bundle 생성 | `make dist/update/release` |
| release Product Update bundle 검증 | `make dist/update/verify/release` |
| VM Image update bundle 생성 | `make dist/image-update/release` |
| VM Image update bundle 검증 | `make dist/image-update/verify/release` |

### 2-3. 검증 환경용 명령어

아래 명령어는 개발자 또는 QA 검증 환경에서 사용합니다. 현장 운영자가 일반 절차로 실행하는
명령어는 아닙니다.

| 목적 | command |
|---|---|
| 설치된 runtime health 확인 | `make dist/installed/health` |
| dev DMG 현장 전달 표준 gate | `make dist/dmg/dev` |
| dev DMG cache-preferred 로컬 패키징 | `make dist/dmg/dev/cached` |
| dev DMG clean compile 단계만 실행 | `make dist/dmg/dev/compile` |
| 생성된 dev DMG와 golden runtime 검증 | `make dist/dmg/dev/verify` |
| dev PKG를 VM compile 포함해 생성 | `make dist/pkg/dev/compile` |
| dev PKG golden runtime boot 계약 검증 | `make dist/pkg/dev/runtime-smoke` |
| dev PKG 설치 전 표준 검증 | `make dist/pkg/dev/verify` |
| release manifest/Compose/VM Docker plan 사전 대조 | `make devtools/release-contract` |
| golden rootfs만 compile | `make devtools/golden-rootfs/compile` |
| testkit release wheel 설치 | `make testkit/install-release TESTKIT_VERSION=<version>` |

build 세부 구현은 `packages/vitalserver-devtools`와
`docs/runtime/macos/packaging.md`를 기준으로 봅니다.

`release-contract`는 release manifest의 Guest image catalog와 immutable
`Support/Guest/compose.yaml`, `config/vm-build.toml` Docker plan을 Docker export와
rootfs cache 판단 전에 대조합니다. 이 단계는 source를 자동 수정하지 않으며, mismatch는
path, service/field, expected/actual image를 남기고 compile failure로 끝납니다. Swift
`Generated*.swift`만 release metadata에서 파생합니다.

Golden rootfs compile은 VM을 띄우는 단순 준비 단계가 아니라 제품 compile 단계입니다.
`guest.ubuntu.base_url`과 `guest.ubuntu.apt_snapshot`은 함께 rootfs compile input입니다.
`prepare-airgap-rootfs.sh`는 실제 package install 전에 direct Ubuntu snapshot source를 적용하고 apt plan을
기록합니다. Host가 제공한 `guestClockUtc`와 snapshot package index가 맞지 않거나, Python/util-linux,
Docker/container runtime처럼 base runtime을 바꾸는 upgrade가
감지되면 rootfs smoke까지 가지 않고 compile failure로 올립니다. `macos-runtime-wait-rootfs-ready`는 현재 run의
`rootfs-failure.json`, manifest stage, launcher log의 kernel panic/Oops/SIGILL을 모두
확인해야 하며, `rootfs-base` 압축은 apt plan proof와 smoke proof가 모두 통과한 경우에만 허용됩니다.

`runtime-smoke`는 compile 뒤의 별도 runtime boot proof입니다. 이 단계는 clean golden runtime으로 VM을
부팅하고 `runtime-boot-smoke-manifest.json`의 `bootstrap-result`, `runtime-observation`, `systemd-units`,
`http`, `compose-services`, `disk-health`, `capabilities`, `command-dispatch`, `feature-readiness` stage가
모두 passed인지 확인합니다. Devtools direct start 경로도 `data/deploy/host-time.json`을 써야 하며,
Guest가 이 Host-owned time contract를 적용하지 못하면 smoke failure입니다.

DMG dev target은 역할을 분리합니다. `dist/dmg/dev`는 review, release-contract, package environment preflight,
PWA build, clean rootfs compile, artifact verify, golden runtime smoke를 한 번에 실행하는 현장 전달 표준 gate입니다. `dist/dmg/dev/cached`는 현재 Guest
source contract fingerprint와 rootfs receipt가 일치할 때만 golden cache를 재사용하는 빠른 로컬 패키징
target입니다. `dist/dmg/dev/compile`은 clean
rootfs로 산출물을 만드는 compile 단계이고, `dist/dmg/dev/verify`는 이미 생성된 DMG artifact와 golden
runtime boot contract를 검증하는 diagnostic 단계입니다. `verify`는 verified golden cache가 없거나 stale이면
compile을 대신 시작하지 않고 fail-fast합니다. `cached`, `compile`, `verify` 중 어느 하나도
현장 전달 proof를 뜻하지 않습니다. review, artifact verify, runtime smoke는 `internal/vm/dmg/dev/*` 단계로
유지하되 public 현장 전달 workflow는 `dist/dmg/dev` 하나로 고정합니다. 그래도 `dist/dmg/dev`가
통과했다는 사실만으로 fresh install, installed runtime, update/rollback 동작이 검증된 것으로 보지
않습니다. 이 target은 실제 target Mac의 install provisioning side effect를 실행하지 않으므로 fresh
install에서 만들어야 하는 Host-owned config directory 누락은 잡지 못합니다. Guest compose bind source,
runtime smoke, installed health까지 확인해야 하는 변경은 `make dist/dmg/dev` 후 설치된 환경에서
`make dist/installed/health`로 확인합니다.
`compile`의 clean 의미는 변수로 끄지 않습니다. 같은 target 이름이 cached compile과 clean compile을
오가면 검증 결과를 해석할 때 외부 실행 변수를 다시 추적해야 합니다. 캐시를 재사용하는 개발 산출물만
필요하면 `make dist/dmg/dev/cached`를 사용하고, 현장 전달 proof가 필요하면 `make dist/dmg/dev`를
사용합니다.

Compile은 rootfs와 함께 실제 Guest deploy material digest를 receipt에 기록합니다. package와 runtime
smoke는 source를 다시 조립하지 않고 compile material을 restage한 뒤, `guestClockUtc`, runId,
runtime-smoke 설정, `host-time.json`만 제외한 동일 digest를 receipt와 대조합니다. apt snapshot,
Docker platform, runtime-data contract, Guest source가 달라지면 VM boot나 package 생성 전에 실패합니다.

Guest-tools wheel은 temporary build output에서 만든 뒤 compiled deploy material에만 복사합니다. source
tree의 `packages/vitalserver-guest-tools/dist`는 rootfs fingerprint input이나 compile output이 아니므로,
wheel staging이 같은 delivery run의 뒤 단계 fingerprint를 바꾸지 않습니다.

Package environment preflight는 rootfs compile 전에 Host-owned `swift`, `codesign`, `pkgbuild`, DMG의
`hdiutil`, output path와 existing DMG attachment를 확인합니다. rootfs receipt와 compiled Guest deploy
material은 아직 존재할 수 없으므로, 그 검증은 clean compile 뒤 package preflight가 맡습니다.

Host compile만 product image를 build/pull/export합니다. Guest는 검증된 image bundle을 load하고
Compose를 `up --pull never --no-build`로 실행합니다. image 누락을 Guest pull/build로 보정하지 않으므로,
누락은 bootstrap/Compose failure로 남습니다. Compose 환경 파일도 개발 Mac `.env`가 아니라 explicit
`runtime-config.json`과 `runtime-settings.json`에서 `/mnt/runtime/compose.env`로 생성합니다.
runtime boot smoke가 `bootstrap-result.json.status=failed`를 보면 timeout까지 기다리지 않고 runId,
`stage=bootstrap-result`, reasonCodes, bootstrap result와 launcher log 경로를 즉시 출력합니다.

## 3. 무엇을 검증할까

검증은 “켜진다”에서 끝나지 않습니다. 설치, update, rollback, health check, recorder 관측,
log 수집까지 이어지는 경로를 확인해야 합니다.

### 3-1. Release 확인 항목

| 확인할 것 | 이유 |
|---|---|
| Product Update와 VM Image Update 구분 | update 범위와 rollback 범위를 분리하기 위해 |
| update 적용 전후 health check | update가 상태를 악화시키지 않았는지 확인하기 위해 |
| rollback 실패 기록 | 복구 실패는 다음 release에서 반드시 다뤄야 하기 때문에 |
| package별 변경 범위 | 운영자가 어떤 부분이 바뀌었는지 알아야 하기 때문에 |
| release note | 설치/운영 판단에 필요한 변경점을 남기기 위해 |

### 3-2. 검증 시나리오

Testkit은 실제 Recorder 장비를 항상 연결할 수 없는 상황에서 수집 경로를 반복 확인하기 위한
도구입니다. 여러 Recorder가 동시에 데이터를 보내는 상황, 일정 시간 동안 계속 데이터가 들어오는
상황, release 전 기본 smoke test를 재현하는 데 사용합니다.

`.vital` file validation scenario는 계획 중이며, 현재 preview 검증 범위에는 포함하지 않습니다.

| 범위 | 확인하는 것 |
|---|---|
| unit test | 상태 판단 규칙, contract, parser, formatter |
| integration test | observer, Product Lab/dev testkit, API client, package plan |
| testkit smoke | dev simulated recorder와 Vital Server 연결 |
| testkit load | 반복 `send_data` 처리와 저장 흐름 |
| runtime chaos | permission, update, observability failure injection |
| Health Check scenario | VR observed, missing, stale 상태 |

## 4. 테스트 기준

테스트는 “기능이 한 번 성공한다”를 확인하는 데서 끝나지 않습니다. Helper에서 더 중요한 것은
상태 의미가 깨지지 않는지 확인하는 것입니다.

예를 들어 recorder 목록을 읽지 못한 상황을 빈 목록으로 표시하면, 운영자는 “recorder가 없다”고
이해할 수 있습니다. 하지만 실제 원인은 권한 문제나 service 오류일 수 있습니다. 이런 경우는
기능 실패보다 더 위험합니다. 장애가 정상처럼 보이기 때문입니다.

그래서 새 동작을 추가하거나 책임 위치를 옮길 때는 정상 흐름 하나만 확인하지 않습니다.
`missing`, `invalid`, `failed`, `stale`, `zero`, `empty`가 서로 바뀌지 않는지 확인합니다.

### 4-1. VM 상태 제어 변경 기준

VM start, stop, restart, poweroff는 여러 workflow에서 필요하지만, 상태 제어 책임은 흩어지면
안 됩니다. Settings apply, update, rollback, repair, watchdog, uninstall이 각자 VM을 직접
멈추거나 다시 시작하면 Guest shutdown, Host process, launchd state, progress state가 서로 다른
순서로 움직이면서 같은 장애를 다시 만들 수 있습니다.

VM runtime 상태를 바꾸는 새 코드나 수정은 먼저 아래 기준을 확인합니다.

| 기준 | 확인할 것 |
|---|---|
| 단일 owner | VM start/stop/restart/poweroff는 `RuntimeVMStateControlUseCase` 또는 그 owner wrapper를 통해 실행되는가 |
| Guest shutdown 계약 | Guest shutdown이 필요한 경로는 explicit shutdown preparation과 poweroff 관측을 기다리는가 |
| Host 상태 소유 | Host는 pid file, launchd, process, filesystem 상태를 명시적으로 읽고 실패를 숨기지 않는가 |
| workflow 역할 | update/repair/uninstall workflow는 VM 상태를 추측하지 않고 owner가 제공한 결과만 소비하는가 |
| operation state 보존 | install/uninstall state document는 runtime status message에 덮어 쓰지 않고 별도 read model로 보존되는가 |
| status 기록 범위 | runtime status writer가 clean uninstall로 제거된 product root를 다시 만들지 않는가 |
| recovery 구분 | clean uninstall과 fresh-install recovery가 `--clean`/`--force-clean-uninstaller` 계약으로 분리되어 있는가 |
| progress 분리 | progress viewer marker, UI 메시지, shared log line을 runtime cleanup 성공/실패의 source of truth로 쓰지 않는가 |

특히 아래 변경은 직접 VM 제어 호출을 추가하지 말고 owner entrypoint를 먼저 찾아야 합니다.

| 변경 위치 | 사용해야 하는 방향 |
|---|---|
| Settings apply 후 restart | Configure restart policy가 VM runtime restart requirement를 판단한 뒤, 필요할 때만 Guest shutdown 준비 후 poweroff 관측을 거쳐 restart |
| Product update stop plan | update shutdown-stop port를 통해 VM owner가 stop 순서를 실행 |
| rollback/service-control | service start/stop wrapper가 VM owner를 통과 |
| watchdog recovery | Guest product service 문제는 Guest Control stack reconcile operation을 먼저 사용하고, VM boundary 문제만 watchdog 전용 restart intent로 VM owner를 통과 |
| repair/VM disk replacement | repair intent 또는 best-effort result를 통해 실패 의미를 보존 |
| Helper UI clean uninstall | `--clean` 사용. graceful stop 실패 시 cleanup 진행을 위해 force stop으로 전환하되 fresh install readiness를 성공으로 추정하지 않음 |
| Reset for Reinstall | `--force-clean-uninstaller` 사용. fresh install blocker 제거와 readiness 검증을 recovery contract로 수행 |

검증할 때는 성공 case만 보지 않습니다. VM lifecycle `stopping`/`failed`, Guest Control operation
timeout, pid file missing, launchd loaded/running mismatch, progress `missing-marker`처럼 서로 다른
상태가 서로 섞이지 않는지 확인합니다. Legacy `guest-runtime-state-*` raw string이 보이면 older
diagnostics evidence로만 다루고 current recovery reason으로 승격하지 않습니다.

Product update shutdown에서 Guest Control update-shutdown operation이 accepted 상태 이후 progress나
failure 없이 사라지면 정상 pending으로 보지 않습니다. Guest Control API는 operation read에서
`running`, `failed`, `ready`, `unavailable`을 구분해 보고해야 하며, Host는 typed failure를 받아 update를
실패로 전환해야 합니다. VM kernel panic이 뒤따라 보이더라도 먼저 Guest operation이 explicit state를
남겼는지 확인합니다.

Guest Control update-shutdown operation이 `running` 상태에서 "Redis backup completed. Stopping guest
services." 단계로 오래 머무르면 Guest adapter가 Redis 백업 이후 runtime compose stop 단계에서 멈춘
것입니다. Docker Compose stop의 container grace timeout은 subprocess 자체의 완료를 보장하지 않으므로
Guest operation은 별도 command timeout을 가져야 합니다. Timeout은 Host가 추측해서 넘기지 말고 Guest
dependency failure operation state로 기록되어야 rollback/force-stop 경로가 명시적으로 실행됩니다.
Update shutdown 기준 compose stop grace timeout은 일반 service stop보다 길게 둡니다. Product Lab,
dev testkit, observer, websocket, Redis save처럼 dev/runtime 부하가 있는 상태에서 20초 수준의 stop timeout은
정상 종료 중인 컨테이너를 실패로 오인할 수 있습니다.
Host가 update activation/shutdown 결과를 기다리는 전체 타임아웃은 Guest 측 종료·활성화 단계 최대
실행 시간보다 작아서는 안 됩니다. 현재는 Host와 Guest 경계의 명시적 실패를 보존하기 위해
activation/shutdown 대기 상한을 900초로 맞추었고, 타임아웃이 터지기 전에 Guest는 반드시
`failed` 또는 `failed` 단계 reason code를 남겨야 합니다.
Guest는 final sync와 `systemctl --no-block poweroff` 요청이 성공한 뒤에만
`ready`/`poweroff-requested` operation state를 기록해야 합니다. Poweroff 요청 전에 ready를 먼저 쓰면 Host가
실제 요청 실패나 sync hang을 성공 상태로 오해할 수 있습니다.
Guest가 poweroff target에 도달했더라도 VM process가 종료되지 않을 수 있습니다. `Failed to execute
shutdown binary`, VM lifecycle `stopping`, Guest Control operation timeout 또는 missing VM IP가 함께
보이면 Host는 guest shutdown success를 추정하지 말고 bounded wait 실패로 처리한 뒤 VM runtime
services force-stop 경로로 빠져나와야 합니다. Settings restart도 update shutdown과 같은 VM stop
위험을 가지므로, guest shutdown wait 또는 poweroff wait 실패 시 force-stop 후 runtime start/health
wait로 이어지는 escape hatch가 필요합니다.

Guest time은 Host-owned `host-time.json` contract에서 동기화합니다. 실제 `vitalserver-vm start` entrypoint는 새 lifecycle run 직전에 이 계약을 현재 Host clock으로 다시 씁니다. Bootstrap에서 한 번만 맞추면
rollback, restart, snapshot 기반 VM disk 재사용 뒤 Guest clock이 rootfs/golden 이미지 생성 시점으로
되돌아갈 수 있습니다. Guest는 매 boot 초기에 `tirosh-vitalserver-sync-host-time.service`로
`host-time.json`을 읽고 clock을 맞춘 뒤 Docker, runtime-observation, observability, compose 서비스를
시작해야 합니다. UI나 observer는 timestamp를 현재 시간으로 보정하지 않습니다.
부팅 후 drift 교정은 별도 NTP 상태 계약으로 검증하되, NTP 성공을 boot contract 성공으로 대체하지 않습니다.

Release package와 DMG build도 expensive host packaging 전에 Host-owned preflight를 통과해야 합니다.
`release-pkg`와 `release-dmg`는 Swift build, `pkgbuild`, `hdiutil create` 전에 필수 tool, golden runtime
`Image`/`initrd.img`, `rootfs-base` receipt, compiled Guest deploy material, DMG output attachment 상태를
확인합니다. 이 값들은 package input이므로 누락, 무효, unavailable, mounted/attached blocked 상태를 빈
값이나 late package failure로 바꾸면 안 됩니다. Docker registry와 현재 Guest source는 package preflight가
다시 읽지 않습니다.

Guest compose service 계약은 Docker image bundle을 만드는 compile input입니다. `Support/Guest/compose.yaml`에 선언된 image는
`guest.docker_images.images` 또는 `optional_images`에 있어야 하고, build `dockerfile`은
`guest.docker_images.*_dockerfile`과 일치해야 하며, 해당 path는 `guest.deploy.include`로 설치 payload에
포함되어야 합니다. Redis Relay처럼 UI 설정에서 disabled가 가능한 service도 compose에 항상 존재한다면
package bundle 관점에서는 필수 image/source 계약입니다. 이 검사는 `make dist/dmg/dev/compile`에서
Docker build 전에 실패해야 합니다. export는 `docker image save --platform <guest platform>`으로 고정하고,
compiler가 expected tag, legacy Config/Layer reference, OCI descriptor closure와 SHA-256을 검증한 뒤에만
Guest deploy material로 넘깁니다. 현장 전달 표준 `make dist/dmg/dev`은 clean compile을 포함하므로 같은
누락을 전달 전 gate에서 막아야 합니다.
Installed package deploy도 golden rootfs deploy와 같은 bootstrap contracts를 포함해야 합니다.
`deploy/build-metadata/rootfs-input.json`은 Guest runtime data disk 준비가 읽는 Host-owned contract이며,
package staging이 Ubuntu source, apt snapshot, runtime data disk, Docker platform 값을 명시적으로 써야
합니다. Golden rootfs workspace에만 존재하는 metadata를 installed runtime에서 fallback으로 재생성하면
안 됩니다.
Runtime data contract 검증은 directory root 존재에서 멈추면 안 됩니다. Installed bootstrap은 Docker
image bundle load 전에 `dockerDataRoot`와 `dockerDataRoot/tmp`, `containerdRoot`를 명시적으로 준비해야
하며, golden rootfs smoke도 같은 directory shape를 검증해야 합니다.
Guest bootstrap ordering도 contract의 일부입니다. `tirosh-vitalserver-runtime-data-prepare`가
runtime data disk를 mount하고 Docker `data-root`를 쓴 뒤에만 Docker를 활성화해야 합니다.
`tirosh-vitalserver-container-logs.service`, guest observability, command poller처럼 Docker를 읽거나
Docker service를 당길 수 있는 background service는 이 시점 이전에 `--now`로 시작하면 안 됩니다.
설치 후 Guest bootstrap 순서의 source of truth는 `tirosh-vitalserver-bootstrap` CLI가 실행하는
`GuestBootstrapWorkflow`입니다. `bootstrap.sh`는 deploy share mount, guest-tools wheel 설치,
workflow exec까지만 담당하는 thin wrapper여야 합니다. Docker start, image load, smoke container,
compose start, container log start 같은 순서와 guard는 workflow 테스트로 고정합니다.
`GuestBootstrapWorkflow`는 application layer의 operation order와 guard만 소유하고, 실제 systemd,
Docker, mount, filesystem, curl, JSON write 구현은 `infrastructure/bootstrap_operations.py`가
명시 operations로 제공합니다. application bootstrap code가 infrastructure module을 직접 import하거나
concrete command를 조립하기 시작하면 같은 경계 붕괴가 재발한 것입니다.
Guest maintenance operation은 single-shot command입니다. Guest Control API는 command를 accepted
operation document로 만들고, 이후 worker/adapter가 같은 command를 VM reboot 뒤 다시 실행하지 않도록
operation identity와 terminal state를 보존해야 합니다. 성공 끝까지 trigger를 재사용 가능한 파일로 남겨두면
poweroff 또는 process termination 중 worker가 사라졌을 때 같은 작업이 다음 VM boot에서 다시 dispatch되고,
Settings restart나 watchdog recovery가 update shutdown 경로로 오염될 수 있습니다.
이 규칙은 update shutdown에만 한정하지 않습니다. update activation, datastore repair, Redis backup,
Redis restore처럼 Guest Control maintenance API로 dispatch되는 작업은 모두 accepted/running/failed/ready
operation state를 남기고, invalid command도 failed operation으로 보존해서 같은 invalid trigger가 반복
실행되지 않게 합니다.

Host의 mutating runtime operation owner는 Runtime Control Host operation lease API입니다.
Lease acquire, heartbeat, release는 `/platform/operations/lease/*` owner boundary를 통해 수행해야
하며, CLI는 local-server-mediated owner API를 사용할 수 없으면 파일 fallback으로 lease를 추정하지 않고
unavailable/read failure를 그대로 드러내야 합니다. `runtime-operation-lease.json`은 diagnostics/export
artifact로 남을 수 있지만 active operation ownership의 source of truth가 아닙니다.

Lock은 state를 대신하지 않습니다. Lock은 같은 owner 영역의 동시 write를 막는 장치이고, operation
상태는 Host operation lease API, Guest Control operation document, workflow owner contract로 명시되어야
합니다. workflow state artifact는 diagnostics/export evidence로만 남길 수 있습니다. UI나 watchdog은 lock
파일, pid file, progress marker, workflow artifact를 source of truth로 사용하지 말고 typed owner contract를
읽어야 합니다.
JSONL event append처럼 read-modify-write로 보이는 기록도 lock 대상입니다. Event 유실은 operation
상태를 직접 바꾸지는 않지만, 장애 원인 분석에 필요한 관측 기록을 사라지게 만들 수 있습니다.

Settings apply는 update가 아닙니다. CPU, memory, disk increase, network mode, bridged interface,
Vital files directory처럼 VM runtime 구성 자체가 바뀐 경우만 VM runtime restart requirement를 만듭니다.
URL, admin password, start on boot, auto recovery, sleep prevention, VitalServer Helper backup schedule/retention 변경은
restart requirement를 만들면 안 됩니다. Settings UI가 모든 configure field를 보내더라도 policy는
제출된 field 이름이 아니라 Host가 제공한 명시적 현재 상태와 planned state의 차이를 비교해야 합니다.
Settings UI는 draft 설정과 Host가 읽은 runtime 설정을 분리해서 표시해야 합니다. Status/Info 탭은
draft 값을 현재 적용 상태처럼 보여주면 안 되며, Settings 탭은 VM runtime restart가 필요한 변경과
restart 없이 저장할 때의 pending 상태를 Apply 전에 사용자에게 명시적으로 알려야 합니다.
Settings apply command가 실패하면 Control Panel host composition은 response를 그대로 반환하고
presentation-local state를 mutate하지 않아야 합니다. Local API port처럼 helper UI가 소유한 값도
command success가 확인되기 전에는 failed draft를 현재 상태로 승격하면 안 됩니다.

Settings apply의 activation은 한 종류가 아닙니다. CPU, memory, disk, network, Vital files directory처럼
VM boundary가 바뀌는 설정은 VM runtime restart를 요구합니다. Redis Relay처럼 guest compose service
묶음만 바뀌는 설정은 VM을 재시작하지 않고 Guest Control stack reconcile operation으로 적용해야
합니다. Host는 Guest Control API로 reconcile command를 accepted시키고, `/runtime/operations/{operationId}`
read가 완료 또는 실패를 보고할 때까지 bounded wait합니다. Guest capability가 없거나 operation read가
unavailable/failed이면 성공으로 추정하지 않습니다. Settings UI는 이 차이를 `Change activation`으로
표시하고, container reconcile을 VM restart처럼 설명하면 안 됩니다.

Host는 VM runtime start가 성공했을 때 실제 start에 사용한 VM config를 applied VM config snapshot으로
기록하고, Settings read contract는 saved config와 applied config를 함께 제공해야 합니다. Vital files
directory처럼 VM restart 전에는 적용되지 않는 값은 Status/Info에서 applied snapshot을 기준으로
표시하고, saved config를 현재 runtime state로 승격하면 안 됩니다.

Fresh install에서 `vm-lifecycle.json`이 `bootstrapping`에 머물고 guest `bootstrap-result.json`이
`running`인 채 오래 유지되면 `bootstrap.log`를 먼저 확인합니다. Redis 또는 첫 container start 단계에서
`runc`/Docker가 실패했는데 bootstrap result가 `failed`로 바뀌지 않으면 runtime smoke와 diagnostics가
실제 bootstrap failure reason을 증명할 수 없습니다. Product current health는 이 파일을 VM failure
owner로 읽지 않고 Guest Control readiness/service status와 VM lifecycle을 사용합니다. Guest bootstrap
script는 시작 시 `running` result를 쓰더라도 실패 trap에서 최종 `completed`가 아닌 상태를 반드시
`failed`로 덮어써야 합니다. `running`은 한 번 썼다는 marker가 아니라 아직 완료되지 않은 operation
proof입니다.
Watchdog active-operation guard는 `running` bootstrap result를 active operation으로 취급하지 않습니다.
VM이 kernel panic이나 early termination으로 guest trap을 실행하지 못하면 bootstrap result가
`running`에 머물 수 있으므로, deadline 이후에는 Host lifecycle stale/failure 관측이 recovery 또는
critical 상태로 드러나야 합니다.
VM build는 제품 compile로 취급합니다. `make dist/dmg/dev/compile`, `make dist/pkg/dev/compile`,
`make devtools/golden-rootfs/compile`은 golden rootfs proof를 새로 요구하며, kernel panic,
guest boot failure, rootfs proof failure를 우회하지 않습니다. 다만 compile passed는 installed
runtime passed를 뜻하지 않습니다. Guest bootstrap 완료, Guest Control readiness/service status,
systemd/docker/http 계약은 DMG dev에서는 `make dist/dmg/dev`의 runtime smoke phase가 소유하고, 기존
artifact를 진단할 때는 `make dist/dmg/dev/verify`를 사용합니다. PKG dev에서는
`make dist/pkg/dev/runtime-smoke`가 소유합니다. DMG dev cache-preferred local packaging은
`make dist/dmg/dev/cached`가 소유하고, clean compile 단계는 `make dist/dmg/dev/compile`이 소유합니다.
`compile` target의 cache policy는 실행 변수로 바꾸지 않습니다.
현장 전달 표준 게이트는 `make dist/dmg/dev`입니다. `make dist/pkg/dev/verify`는 compile과 runtime
smoke를 묶은 package-level 검증 workflow이며, DMG artifact readback을 포함한 현장 전달 proof를 대체하지
않습니다. PKG dev verify는 compile 전에 package plan/template unit review, PWA Runtime Control
contract/check/test, log export archive/rotation/retention test를 실행합니다.
실패는 runId, failing stage, failure reason 또는 matched pattern, artifact/log path와 함께 드러나야 합니다.
Guest userspace가 `Illegal instruction`이나 `Segmentation fault`로 죽어 manifest가 `running`에 멈춘
경우도 timeout이 아니라 compile failure 증거로 분류해야 합니다.
실패 후에는 graceful stop과 bounded wait를 수행하고, launcher가 남으면 VM_HOME-scoped
`macos-runtime-force-stop`으로 정리해야 합니다. 정리 후 `macos-runtime-require-no-running`이
통과하지 않으면 다음 compile을 시작하면 안 됩니다.
Golden rootfs는 `/mnt/tirosh/run/rootfs-runtime-manifest.json` schema v2의 stage 결과가 모두 통과한
경우에만 `rootfs-base.raw.gz`로 압축할 수 있습니다. 필수 stage는 `runtime-data-mount`,
`runtime-data-configure`, `docker-service`, `runtime-version`, `docker-image-load`, `docker-smoke`,
`disk-space`, `compose-build`, `compose-up`, `edge-ready`이며, `cleanup.status=passed`도 함께
필요합니다.
Manifest와 `rootfs-ready` marker는 현재 golden rootfs run의 `runId`와 일치해야 합니다. Manifest의
`ubuntu.metadataStatus`는 `loaded`여야 하고, `ubuntu.baseUrl`, `ubuntu.cacheKey`,
`ubuntu.aptSnapshot`, `ubuntu.kernel`은 비어 있으면 안 됩니다. 입력 Ubuntu 이미지와 apt snapshot이
무엇인지 모르는 rootfs는 smoke가 통과해도 release artifact가 될 수 없습니다.
Manifest에는 Docker image bundle의 `bundleSha256`, target platform, guest architecture, runtime data
mount proof, filesystem free bytes/inodes proof가 있어야 합니다. `rootfs-ready` marker에는 identity
cleanup proof가 있어야 하며, 최종 `rootfs-base.raw.gz`는 `rootfs-base.raw.gz.manifest.json` sidecar와
checksum이 일치할 때만 cache artifact로 재사용할 수 있습니다.
receipt와 fingerprint가 모두 일치하지 않으면 cache miss는 이전 golden `vm-disk.img`를 이어 쓰는 재시도가
아니라 새 Ubuntu base disk에서의 clean compile이어야 합니다. fingerprint에는 effective build config와
rootfs size도 포함해야 합니다.
Golden rootfs input metadata에는 `guestClockUtc`도 포함되어야 합니다. Guest bootstrap은 NTP를
fallback으로 삼지 않고, apt snapshot source를 읽기 전에 Host가 제공한 UTC 시각을 적용해야 합니다.
`Release file ... is not valid yet`는 apt mirror 문제가 아니라 compile VM clock 계약이 깨진 신호로
분류합니다.
`docker --version`, `docker compose version`, package install success, `rootfs-ready` marker는 runtime
proof가 아닙니다. Rootfs 준비 VM은 Docker disposable container smoke 이후 실제 deploy bundle의
Compose stack을 올리고 `/ready`를 확인한 뒤 `docker compose down -v`로 state를 정리해야 합니다. 실패
시 `rootfs-smoke-diagnostics`에 compose ps/logs, Docker info, journal, dmesg tail, df, partial manifest를
남겨야 합니다. Fresh install bootstrap도 image bundle load 직후 disposable smoke container start를
수행하고, 실패하면 `guest-bootstrap-docker-runtime-failed`를 기록해야 합니다.
Ubuntu arm64 guest가 Docker image load 이후 첫 container start 또는 Docker netlink activity에서
`__bpf_prog_run_save_cb` / `Kernel panic - not syncing: Oops - Undefined instruction`로 죽으면
Docker image 문제가 아니라 Apple Virtualization 환경에서 Ubuntu generic kernel의 BPF JIT 실행 경로가
깨진 것으로 봅니다. 하지만 `net.core.bpf_jit_enable=0`은 kernel config에 따라 `Invalid argument`로
거부될 수 있고, `bpf_jit_enable=0` boot argument는 runtime guard로 증명되지 않습니다. Rootfs 준비와
fresh install bootstrap은 커널 sysctl fallback을 만들지 말고, 실제 Docker smoke container start가
통과했는지를 runtime proof로 사용해야 합니다. Smoke를 삭제하면 문제가 숨겨질 뿐이며, Ubuntu cloud
image/kernel 입력은 manifest의 `ubuntu.kernel`과 rootfs smoke stages로 검증된 버전으로 pin해야 합니다.
Ubuntu image download cache는 `base_url` identity를 포함해야 합니다. Release URL만 바꿨는데 같은
`ubuntu-24.04-server-cloudimg-arm64.img` cache 파일을 재사용하면 config pin이 실제 VM 입력으로
반영되지 않고, 검증했다고 믿은 kernel과 실제 packaged kernel이 달라집니다.
`rootfs-apt-plan.json`이 Python, util-linux, curl 같은 base runtime package upgrade를 막았다면,
guard 목록을 넓혀 통과시키지 않습니다. 이는 Ubuntu cloud image와 apt snapshot/package set이 하나의
reproducible input으로 고정되지 않았다는 신호입니다. apt plan의 `runId`와 `snapshot`은 manifest의
현재 run 및 `ubuntu.aptSnapshot`과 일치해야 합니다.
Golden rootfs compile은 VM start 전에 Host-owned preflight를 통과해야 합니다. `internal/vm/airgap-rootfs`
는 `rootfs-input.json`과 `golden-rootfs-run.json`이 같은 current `runId`를 가리키는지, 이전
`rootfs-ready`/manifest/failure/apt-plan proof가 남아 있지 않은지, VM launcher process가 없는지,
`ubuntu.aptSnapshot`의 `noble`, `noble-updates`, `noble-security` InRelease endpoint가 reachable한지
먼저 확인합니다. Missing metadata, decode failure, stale proof, running VM, and external unavailable은
서로 다른 blocker입니다. 이 값들을 empty/default success로 바꾸거나 Guest `apt-get install` 실패까지
미루면 안 됩니다.

### 4-2. 영역별로 봐야 하는 것

| 영역 | 확인할 것 | 깨지면 생기는 문제 |
|---|---|---|
| 계약 | API response, 상태 문서, enum case | UI와 Helper가 같은 상태를 다르게 해석함 |
| 상태 판단 | 정상, missing, failed, stale 전환 | 불완전한 입력인데도 정상 상태로 넘어감 |
| 실행 결정 | start, stop, update, repair에서 내려야 할 명령 | 실패했는데 다음 단계가 실행됨 |
| 긴 작업 흐름 | install, update, repair, uninstall 순서와 진행 상태 | 중간 실패나 rollback 실패가 사라짐 |
| 외부 연결 코드 | 파일, process, network, repository read/write | 권한 실패나 decode 실패가 빈 결과처럼 보임 |
| 앱 시작 연결 | 설정, 경로, 구현 연결 | 앱 시작 단계에 실제 실행 책임이 섞임 |
| Host 경계 | launchd, signal, filesystem, VM process | Host 상태 read/write 실패가 내부에서 숨겨짐 |

### 4-3. 변경 유형별 테스트

변경한 위치에 따라 먼저 볼 테스트가 달라집니다. 모든 변경에 같은 테스트를 억지로 붙이는 것이
목표는 아닙니다. 변경이 깨뜨릴 수 있는 의미를 먼저 고릅니다.

| 변경 | 먼저 확인할 것 |
|---|---|
| 화면 표시 변경 | 같은 상태가 PWA와 Helper app에서 같은 의미로 보이는가 |
| Runtime Control API 변경 | OpenAPI, Swift client, PWA contract가 함께 맞는가 |
| recorder/bed 관측 변경 | observed, missing, stale, read-failed가 분리되는가 |
| file/log/settings read 변경 | 파일 없음, 권한 실패, decode 실패, empty가 분리되는가 |
| update/repair 변경 | 진행 상태, 실패 event, rollback 결과가 남는가 |
| packaging 변경 | build 결과물과 현장 적용 경로가 문서와 맞는가 |

### 4-4. 구조 경계 테스트

구조 경계 테스트는 코드가 다시 섞이지 않게 막는 회귀 방지 장치입니다.

새 파일이나 새 target을 추가할 때는 먼저 책임을 정합니다. 이 코드는 상태를 말하는가, 상태를
판단하는가, 실제 실행을 하는가, 화면에 표시하는가를 구분합니다. 그다음 의존 방향, 상태 소유자,
실패를 성공으로 바꾸지 않는 규칙을 테스트로 고정합니다.

## 5. 어떻게 실행하나

검증 명령은 상황에 따라 다르게 고릅니다. 문구만 바꿨다면 전체 runtime 검증을 매번 돌릴 필요는
없습니다. 반대로 update, recovery, contract, packaging을 바꿨다면 단순 unit test만으로는
부족합니다.

### 5-1. 먼저 실행할 기본 검증

일반적인 개발 변경은 먼저 아래 명령으로 확인합니다.

```sh
make dev/check
```

이 명령은 빠르게 깨진 부분을 찾기 위한 기본 관문입니다. 다만 실제 설치, update bundle,
runtime chaos까지 모두 대신하지는 않습니다.

### 5-2. Runtime과 recorder 경로

recorder activity, Health Check, runtime 상태 표시를 바꿨다면 Product Lab 경로와 dev testkit 검증을 함께 봅니다.

```sh
make testkit/smoke
make testkit/load
```

권한, update, observability 실패를 다루는 변경이라면 chaos 검증을 따로 실행합니다.

```sh
make runtime/chaos
```

### 5-3. Package별 test

변경 범위가 특정 package에 닫혀 있으면 package별 test를 직접 실행합니다.

```sh
uv run pytest packages/vitalserver-testkit/tests
uv run pytest packages/vitalserver-devtools/tests
uv run pytest packages/vitalserver-guest-tools/tests
uv run pytest apps/vitaldb-observer/tests
```

### 5-4. PWA와 Recorder Ingress

PWA와 recorder ingress는 Node 기반 검증을 실행합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-recorder-ingress run check
npm --prefix apps/vitalserver-recorder-ingress test
```

### 5-5. Release 결과물 검증

release 결과물을 바꿨다면 build machine에서 결과물 검증까지 봅니다. 현장 Mac에서 실행하는
명령이 아니라, 전달 전에 release 담당자가 확인하는 명령입니다.

| 변경 | 확인 명령 |
|---|---|
| Product Update bundle | `make dist/update/release`와 `make dist/update/verify/release` |
| VM Image update bundle | `make dist/image-update/release`와 `make dist/image-update/verify/release` |
| 신규 설치 DMG | `make dist/dmg/release`; DMG 안의 `Troubleshooting Tools` command 포함 여부 확인 |
| Troubleshooting Tools commands | `make dist/troubleshooting/release` |

## 6. 변경 완료 기준

변경 완료는 “테스트를 돌렸다”가 아니라 “이 변경이 깨뜨릴 수 있는 의미를 확인했다”에 가깝습니다.

작은 문구 수정과 runtime update 변경의 완료 기준은 같을 수 없습니다. 아래 기준으로 변경의
무게를 나눠 봅니다.

### 6-1. 공통 완료 기준

모든 변경은 최소 아래를 확인합니다.

| 기준 | 확인할 것 |
|---|---|
| 목적 | 이 변경이 해결하려는 문제가 문서나 commit message에서 읽히는가 |
| 범위 | 관련 없는 package나 문서를 같이 바꾸지 않았는가 |
| 상태 의미 | missing, failed, stale, empty 같은 단어를 섞지 않았는가 |
| 검증 | 변경 범위에 맞는 command나 test를 실행했는가 |
| 문서 | 운영 절차나 contract 의미가 바뀌면 문서도 함께 바뀌었는가 |

### 6-2. Runtime 변경 완료 기준

runtime behavior, API contract, status/read, update, repair, recovery를 바꿨다면 아래를 추가로
확인합니다.

1. 대표 정상 흐름을 1개 이상 확인합니다.
2. missing state를 별도 case로 확인합니다.
3. invalid input 또는 decode failure를 별도 case로 확인합니다.
4. dependency/effect failure를 별도 case로 확인합니다.
5. stale 또는 partial state가 의미 있는 경우 별도 case로 확인합니다.
6. 실패를 성공으로 바꾸면 안 되는 영역에서는 대체 성공이 불가능함을 확인합니다.
7. 제한적으로 허용된 대체 동작은 degraded 또는 display-only 결과로 드러나는지 확인합니다.
8. 경계, import, file-absence test로 책임 위치가 되돌아가지 않게 고정합니다.

### 6-3. Test file 위치

테스트 파일도 source와 같은 책임 신호를 가져야 합니다. 편의를 위해 여러 source module을 함께
import하더라도, 관련 없는 테스트를 target root에 평평하게 쌓지 않습니다.

예를 들어 `MacControlPanelHostTests/OutboundClient/`는 Mac control panel test target 안에서
실행되지만, 실제로는 macOS runtime control outbound client를 검증하는 테스트를 모읍니다.

## 7. GitHub에서 어떻게 다루나

GitHub issue와 pull request는 재현 가능한 상태, contract, test 기준으로 다룹니다. “문제가
있다”만으로는 다음 사람이 같은 상황을 다시 확인하기 어렵습니다. 어떤 환경에서, 어떤 상태를
기대했고, 실제로 어떤 상태가 나왔는지를 남겨야 합니다.

병원별 설치, 보안, 개인정보 협의는 공개 GitHub issue로 다루지 않습니다.

GitHub Issues: <https://github.com/tirosh-chain/tirosh-vitalserver/issues>

### 7-1. Issue 기준

| 유형 | 기준 |
|---|---|
| Bug report | 재현 절차, 기대 결과, 실제 결과, 관련 상태 문서 또는 로그가 있음 |
| Documentation issue | 깨진 link, 틀린 command, 불명확한 설치/운영 설명 |
| Contract issue | API response, runtime document, Health Check 상태 의미가 깨짐 |
| Testkit issue | simulated recorder, `.vital` upload, smoke/load scenario 재현 가능 |
| Contribution proposal | 변경 목적, 영향 범위, 관련 test 계획이 있음 |

Public issue에는 환자 정보, 병원 내부 IP, 인증 정보, 비밀번호, token, 개인식별정보를 남기지
않습니다. 병원별 보안 정책 협의, 현장 설치 일정, 장비 반입, 네트워크 변경 승인, 의료 행위 또는
임상 판단도 공개 issue로 다루지 않습니다.

### 7-2. Issue 작성 형식

Issue는 아래 형식을 기본으로 씁니다. 모든 항목을 길게 채울 필요는 없지만, `Expected`,
`Actual`, `Explicit state`는 가능하면 분리합니다.

```text
Summary:
Environment:
Expected:
Actual:
Explicit state:
Reproduction:
Related logs or documents:
```

`missing`, `invalid`, `failed`, `stale`, `empty`는 서로 다른 의미입니다. read failure를
empty success로 쓰거나, stale state를 healthy state로 추정하지 않습니다.

### 7-3. Pull Request 기준

Pull request는 변경 목적과 검증 근거가 함께 보여야 합니다. 코드만 바뀌고 상태 의미나 운영
절차가 문서에 남지 않으면, 다음 release에서 같은 문제를 다시 판단해야 합니다.

- 한 가지 목적에 집중합니다.
- package 경계를 지킵니다.
- 상태 판단 code는 외부 상태를 직접 읽지 않습니다.
- contract 변경은 관련 문서와 test를 함께 갱신합니다.
- recovery, update, parsing, settings, Health Check 변경은 실패 case test를 포함합니다.
- Settings UI는 새 설정의 advertised service URL 초기값을 명시적으로 제공하되, 사용자가 비우거나
  provider가 invalid 값을 준 상태를 apply 시 fallback으로 복구하지 않습니다. 빈 값과 invalid 값은
  validation error 또는 read issue로 남겨야 합니다.
- Settings apply 실패 response를 받은 composition/presentation 계층은 local coordinator state를
  성공처럼 mutate하지 않습니다. 실패 case test는 response와 local state를 함께 검증합니다.
- Settings apply의 `restartAfterSave`는 저장 후 항상 restart가 아니라, Configure policy가 VM runtime
  restart 또는 container service reconcile requirement를 반환했을 때 저장 후 activation할지에 대한
  intent입니다. policy 없이 UI나 CLI가 activation 종류를 추정하면 안 됩니다.
- Settings UI의 restart 안내는 실행 정책이 아니라 표시 정책입니다. 실제 restart requirement의 source of
  truth는 Configure policy이고, UI는 현재 runtime 설정과 draft 설정의 차이를 사용자에게 설명하는 데
  그쳐야 합니다. Redis Relay 같은 guest compose service 변경은 VM restart가 아니라 container service
  reconcile로 표시해야 합니다.
- VM stop/restart/poweroff 변경은 단일 VM state control 경로를 통하게 합니다. Settings, update,
  repair, watchdog이 guest shutdown 준비 contract를 우회해 개별적으로 VM service를 멈추지 않습니다.
  Settings restart, update shutdown-stop, rollback/update service start-stop, VM restart가 필요한 watchdog recovery,
  service-control, repair/guest-operation VM start/restart는 VM state control owner entrypoint를 통해
  Host side effect를 실행합니다. Update/rollback workflow는 operation plan 의미를 보존하되, Host service
  start/stop sequencing을 직접 소유하지 않습니다.
- Watchdog recovery는 failure boundary에 맞는 가장 낮은 activation을 먼저 선택합니다. Guest HTTP
  unhealthy 또는 critical container service unhealthy처럼 VM process/IP boundary가 유지된 문제는
  Guest Control stack reconcile operation으로 복구합니다. VM IP missing, VM service not loaded,
  expired bootstrapping처럼 Host/VM boundary가 깨진 경우만 VM runtime restart로 승격합니다. HTTP probe
  read failure는 compose reconcile이나 VM restart로 추정하지 말고 typed blocker로 남깁니다.
- Guest filesystem 또는 disk I/O 장애는 proxy/HTTP failure보다 상위의 guest storage 상태로 남깁니다.
  root filesystem read-only, filesystem error, disk I/O error가 명시되면 `guest-filesystem-read-only`,
  `guest-filesystem-error`, `guest-disk-io-error` reason으로 기록하고, `unknown(vm-...)`이나 단순
  host proxy failure로 축약하지 않습니다. 이 reason은 데이터 보존이 필요한 상태이므로 watchdog 자동
  recovery는 억제하고 backup/recreate 판단으로 연결합니다. 억제 status/event message는 reason만
  남기지 말고 `action=backup-and-recreate-vm`을 함께 기록해 자동 restart가 아닌 데이터 보존형 조치임을
  UI와 로그에서 구분할 수 있어야 합니다.
- Guest runtime-state read issue는 current health/recovery reason으로 승격하지 않습니다. 과거
  `guest-runtime-state-load-failed-*`, `guest-runtime-state-metadata-read-failed-*`,
  `vm-runtime-state-*`, `guest-bootstrap-result-*` raw string은 older status/event evidence를
  decode할 때 `unknown(raw)` diagnostics로 보존할 수 있지만, live `RuntimeFailureReason` typed
  case나 watchdog recovery input으로 만들지 않습니다.
- VM/Host error raw string이 현재 explicit owner contract에서 온 domain error라면 typed case로
  유지합니다. VM disk attachment invalid, VM launch failure, VM configuration invalid, Host resource
  unavailable 같은 상태는 explicit owner read에서 온 경우에만 `RuntimeFailureReason` typed case가
  됩니다. File-state legacy raw string parsing은 이전 status/event 문서 보존용이며 live product
  state를 복구하지 않습니다.
- Watchdog VM restart 중 graceful stop이 typed VM stop failure 또는 launchd service graceful-stop failure로
  실패하면 Host가 VM process를 force-stop하고 launchd 상태를 unload한 뒤 VM runtime restart를 한 번
  재시도합니다. 이 fallback은 stop failure를 empty success로 숨기지 않고 로그와 command failure 경로에
  남겨야 하며, start/configuration failure까지 넓게 삼키면 안 됩니다.
- release 문서의 운영 주장과 dev 문서의 구현 근거가 어긋나지 않게 합니다.

## 8. Release 전에 확인할 것

release 전에는 “결과물을 만들었다”와 “현장에 전달해도 되는 상태다”를 분리해서 봅니다.
아래 항목은 최소 확인 기준입니다.

| 확인 항목 | 의미 |
|---|---|
| package build 성공 | 전달할 DMG, PKG, bundle을 만들 수 있음 |
| update bundle verify 성공 | update manifest, checksum, bundle 구성이 맞음 |
| installed health 성공 | 설치된 runtime이 host proxy, VM, guest HTTP를 확인할 수 있음 |
| testkit smoke 성공 | dev simulated recorder가 기본 수집 경로를 통과함 |
| 주요 실패 패턴 재발 없음 | 이전에 기록한 update, 권한, contract, observability 문제가 다시 나타나지 않음 |

### 8-1. 실패를 보고할 때

검증 실패를 보고할 때는 “실패했다”가 아니라 다시 실행할 수 있는 자료를 남깁니다.

GitHub issue나 pull request에서 검증 실패를 보고할 때는 command, 환경, 실패 로그, 기대 결과를
함께 적습니다.
