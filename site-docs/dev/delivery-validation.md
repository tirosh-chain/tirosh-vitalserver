# Delivery & Validation

이 문서는 Vital Server Helper를 만들고, 검증하고, release 전에 확인하는 기준을 정리합니다.

목표는 단순히 build가 성공했는지 보는 것이 아닙니다. 설치 파일, update bundle, guest service,
testkit이 같은 기준으로 검증되고, 실패했을 때 원인을 다시 찾을 수 있어야 합니다.

## 1. 무엇을 확인하나

Delivery는 사용자가 받는 결과물을 준비하는 일입니다. Validation은 그 결과물이 실제로 동작하는지
확인하는 일입니다.

Vital Server Helper는 Mac app 하나만 배포하지 않습니다. macOS Helper package, Linux guest service,
Docker image bundle, update bundle, Reset Installer package까지 함께 다룹니다. 병원이나 연구실처럼
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
| Reset Installer PKG | 재설치가 막힌 Mac에서 관련 데이터와 기능을 강제로 정리할 때 |
| Product Update bundle | Helper UI, runtime tools, proxy, service stack을 update할 때 |
| VM Image update bundle | guest rootfs/base image class를 바꿀 때 |
| Docker image bundle | 네트워크가 제한된 guest에서 service stack을 실행할 때 |
| guest deploy bundle | guest 내부 service activation에 필요한 입력 |

### 2-2. 릴리스 작업용 명령어

아래 명령어는 릴리스 담당자가 build machine에서 결과물을 만들고 검증할 때 사용합니다.
현장 Mac에서는 이 `make` 명령어를 실행하지 않습니다. 현장에는 생성된 DMG, PKG, update bundle,
Reset Installer PKG를 전달하고, installer 또는 Helper app UI에서 적용합니다.

| 목적 | command |
|---|---|
| release DMG 생성 | `make dist/dmg/release` |
| release Reset Installer 생성 | `make dist/reset-installer/release` |
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
| dev DMG를 VM compile 포함해 생성 | `make dist/dmg/dev/compile` |
| dev PKG를 VM compile 포함해 생성 | `make dist/pkg/dev/compile` |
| golden rootfs만 compile | `make devtools/golden-rootfs/compile` |
| testkit release wheel 설치 | `make testkit/install-release TESTKIT_VERSION=<version>` |

build 세부 구현은 `packages/vitalserver-devtools`와
`docs/runtime/macos/packaging.md`를 기준으로 봅니다.

Golden rootfs compile은 VM을 띄우는 단순 준비 단계가 아니라 제품 compile 단계입니다.
`guest.ubuntu.base_url`과 `guest.ubuntu.apt_snapshot`은 함께 rootfs compile input입니다.
`prepare-airgap-rootfs.sh`는 실제 package install 전에 direct Ubuntu snapshot source를 적용하고 apt plan을
기록합니다. Host가 제공한 `guestClockUtc`와 snapshot package index가 맞지 않거나, Python/util-linux,
Docker/container runtime처럼 base runtime을 바꾸는 upgrade가
감지되면 rootfs smoke까지 가지 않고 compile failure로 올립니다. `macos-runtime-wait-rootfs-ready`는 현재 run의
`rootfs-failure.json`, manifest stage, launcher log의 kernel panic/Oops/SIGILL을 모두
확인해야 하며, `rootfs-base` 압축은 apt plan proof와 smoke proof가 모두 통과한 경우에만 허용됩니다.

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
| integration test | observer, testkit, API client, package plan |
| testkit smoke | simulated recorder와 Vital Server 연결 |
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
| recovery 구분 | clean uninstall recovery처럼 망가진 상태 정리는 일반 graceful stop이 아니라 명시적 force-clean contract를 쓰는가 |
| progress 분리 | progress viewer marker, UI 메시지, shared log line을 runtime cleanup 성공/실패의 source of truth로 쓰지 않는가 |

특히 아래 변경은 직접 VM 제어 호출을 추가하지 말고 owner entrypoint를 먼저 찾아야 합니다.

| 변경 위치 | 사용해야 하는 방향 |
|---|---|
| Settings apply 후 restart | Configure restart policy가 VM runtime restart requirement를 판단한 뒤, 필요할 때만 Guest shutdown 준비 후 poweroff 관측을 거쳐 restart |
| Product update stop plan | update shutdown-stop port를 통해 VM owner가 stop 순서를 실행 |
| rollback/service-control | service start/stop wrapper가 VM owner를 통과 |
| watchdog recovery | watchdog 전용 restart intent로 VM owner를 통과 |
| repair/VM disk replacement | repair intent 또는 best-effort result를 통해 실패 의미를 보존 |
| Helper UI clean uninstall | `--force-clean-uninstaller`로 force-clean recovery contract 사용 |

검증할 때는 성공 case만 보지 않습니다. `guest-runtime-state-stale`, VM stop timeout, pid file
missing, launchd loaded/running mismatch, progress `missing-marker`처럼 서로 다른 상태가 서로
섞이지 않는지 확인합니다.

Product update shutdown에서 `prepare-update-shutdown.request`가 남아 있고
`prepare-update-shutdown-result.json`이 없는 상태는 정상 pending으로 보지 않습니다. Guest command
poller가 unit `failed` 또는 dispatch failure를 명시 result로 기록해야 하며, Host는 이 typed
failure를 받아 update를 실패로 전환해야 합니다. VM kernel panic이 뒤따라 보이더라도 먼저
guest shutdown service가 explicit result를 남겼는지 확인합니다.

`prepare-update-shutdown-result.json`이 `running` 상태에서 "Redis backup completed. Stopping guest
services." 메시지로 오래 머무르면 Guest worker가 Redis 백업 이후 runtime compose stop 단계에서
멈춘 것입니다. Docker Compose stop의 container grace timeout은 subprocess 자체의 완료를 보장하지
않으므로 Guest command는 별도 command timeout을 가져야 합니다. Timeout은 Host가 추측해서 넘기지
말고 Guest dependency failure result로 기록되어야 rollback/force-stop 경로가 명시적으로 실행됩니다.
Host가 update activation/shutdown 결과를 기다리는 전체 타임아웃은 Guest 측 종료·활성화 단계 최대
실행 시간보다 작아서는 안 됩니다. 현재는 Host와 Guest 경계의 명시적 실패를 보존하기 위해
activation/shutdown 대기 상한을 900초로 맞추었고, 타임아웃이 터지기 전에 Guest는 반드시
`failed` 또는 `failed` 단계 reason code를 남겨야 합니다.
Guest는 final sync와 `systemctl --no-block poweroff` 요청이 성공한 뒤에만
`ready`/`poweroff-requested` result를 기록해야 합니다. Poweroff 요청 전에 ready를 먼저 쓰면 Host가
실제 요청 실패나 sync hang을 성공 상태로 오해할 수 있습니다.
Guest가 poweroff target에 도달했더라도 VM process가 종료되지 않을 수 있습니다. `Failed to execute
shutdown binary`, VM lifecycle `stopping`, `guest-runtime-state-stale`이 함께 보이면 Host는 guest
shutdown success를 추정하지 말고 bounded wait 실패로 처리한 뒤 VM runtime services force-stop 경로로
빠져나와야 합니다. Settings restart도 update shutdown과 같은 VM stop 위험을 가지므로, guest shutdown
wait 또는 poweroff wait 실패 시 force-stop 후 runtime start/health wait로 이어지는 escape hatch가
필요합니다.
Guest shutdown request는 single-shot trigger입니다. Worker는 request를 로드하고 `running/starting`
result를 기록한 직후 request file을 소비해야 합니다. 성공 끝까지 request를 남겨두면 poweroff 또는
process termination 중 worker가 사라졌을 때 같은 request가 다음 VM boot에서 다시 dispatch되고,
Settings restart나 watchdog recovery가 update shutdown 경로로 오염될 수 있습니다.
이 규칙은 `prepare-update-shutdown`에만 한정하지 않습니다. `activate-update`, datastore repair,
Redis backup, Redis restore처럼 Guest command request file로 dispatch되는 작업은 모두 worker가
`running` result를 쓴 직후 request를 소비해야 합니다. Invalid request도 failed result를 남긴 뒤
소비해서 같은 invalid trigger가 반복 실행되지 않게 합니다.

Host의 mutating runtime operation은 `runtime-operation-lease.json`을 source of truth로 사용합니다.
Lease acquire, heartbeat, release는 파일 lock으로 보호되어야 하며, `missing`을 읽은 뒤 atomic write만
수행하는 방식은 충분하지 않습니다. 두 Host process가 동시에 들어오면 둘 다 `missing`을 보고 서로의
lease를 덮을 수 있기 때문입니다. Lock 실패는 busy/failed state로 드러나야 하며, operation이 없다고
추정하고 다음 단계로 진행하면 안 됩니다.

Lock은 state를 대신하지 않습니다. Lock은 같은 owner 영역의 동시 write를 막는 장치이고, operation
상태는 lease document, request/result document, workflow state document로 명시되어야 합니다. UI나
watchdog은 lock 파일, pid file, progress marker를 source of truth로 사용하지 말고 typed document를
읽어야 합니다.
JSONL event append처럼 read-modify-write로 보이는 기록도 lock 대상입니다. Event 유실은 operation
상태를 직접 바꾸지는 않지만, 장애 원인 분석에 필요한 관측 기록을 사라지게 만들 수 있습니다.

Settings apply는 update가 아닙니다. CPU, memory, disk increase, network mode, bridged interface,
Vital files directory처럼 VM runtime 구성 자체가 바뀐 경우만 VM runtime restart requirement를 만듭니다.
URL, admin password, start on boot, auto recovery, sleep prevention, Redis backup retention 변경은
restart requirement를 만들면 안 됩니다. Settings UI가 모든 configure field를 보내더라도 policy는
제출된 field 이름이 아니라 Host가 제공한 명시적 현재 상태와 planned state의 차이를 비교해야 합니다.
Settings UI는 draft 설정과 Host가 읽은 runtime 설정을 분리해서 표시해야 합니다. Status/Info 탭은
draft 값을 현재 적용 상태처럼 보여주면 안 되며, Settings 탭은 VM runtime restart가 필요한 변경과
restart 없이 저장할 때의 pending 상태를 Apply 전에 사용자에게 명시적으로 알려야 합니다.
Host는 VM runtime start가 성공했을 때 실제 start에 사용한 VM config를 applied VM config snapshot으로
기록하고, Settings read contract는 saved config와 applied config를 함께 제공해야 합니다. Vital files
directory처럼 VM restart 전에는 적용되지 않는 값은 Status/Info에서 applied snapshot을 기준으로
표시하고, saved config를 현재 runtime state로 승격하면 안 됩니다.

Fresh install에서 `vm-lifecycle.json`이 `bootstrapping`에 머물고 guest `bootstrap-result.json`이
`running`인 채 오래 유지되면 `bootstrap.log`를 먼저 확인합니다. Redis 또는 첫 container start 단계에서
`runc`/Docker가 실패했는데 bootstrap result가 `failed`로 바뀌지 않으면 Host는 실제 bootstrap 실패를
보지 못하고 stale runtime state, host proxy failure, audit proxy failure만 표시합니다. Guest bootstrap
script는 시작 시 `running` result를 쓰더라도 실패 trap에서 최종 `completed`가 아닌 상태를 반드시
`failed`로 덮어써야 합니다. `running`은 한 번 썼다는 marker가 아니라 아직 완료되지 않은 operation
state입니다.
Watchdog의 guest bootstrap guard는 Host가 소유한 `vm-lifecycle.json`의 waiting deadline을 넘어서는
`running` bootstrap result를 active operation으로 취급하면 안 됩니다. VM이 kernel panic이나 early
termination으로 guest trap을 실행하지 못하면 bootstrap result가 `running`에 머물 수 있으므로,
deadline 이후에는 Host lifecycle stale/failure 관측이 recovery 또는 critical 상태로 드러나야 합니다.
VM build는 제품 compile로 취급합니다. `make dist/dmg/dev/compile`, `make dist/pkg/dev/compile`,
`make devtools/golden-rootfs/compile`은 golden rootfs와 runtime smoke proof를 새로 요구하며,
kernel panic, guest boot failure, rootfs proof failure, runtime smoke failure를 우회하지 않습니다.
실패는 runId, failing stage, failure reason 또는 matched pattern, artifact/log path와 함께 드러나야 합니다.
Guest userspace가 `Illegal instruction`이나 `Segmentation fault`로 죽어 manifest가 `running`에 멈춘
경우도 timeout이 아니라 compile failure 증거로 분류해야 합니다.
실패 후에는 graceful stop과 bounded wait를 수행하고, launcher가 남으면 VM_HOME-scoped
`macos-runtime-force-stop`으로 정리해야 합니다. 정리 후 `macos-runtime-require-no-running`이
통과하지 않으면 다음 compile을 시작하면 안 됩니다.
Golden rootfs는 `/mnt/tirosh/run/rootfs-runtime-manifest.json` schema v2의 stage 결과가 모두 통과한
경우에만 `rootfs-base.raw.gz`로 압축할 수 있습니다. 필수 stage는 `docker-smoke`, `disk-space`,
`compose-build`, `compose-up`, `edge-ready`이며, `cleanup.status=passed`도 함께 필요합니다.
Manifest와 `rootfs-ready` marker는 현재 golden rootfs run의 `runId`와 일치해야 합니다. Manifest의
`ubuntu.metadataStatus`는 `loaded`여야 하고, `ubuntu.baseUrl`, `ubuntu.cacheKey`,
`ubuntu.aptSnapshot`, `ubuntu.kernel`은 비어 있으면 안 됩니다. 입력 Ubuntu 이미지와 apt snapshot이
무엇인지 모르는 rootfs는 smoke가 통과해도 release artifact가 될 수 없습니다.
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

recorder activity, Health Check, runtime 상태 표시를 바꿨다면 testkit을 함께 봅니다.

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

### 5-4. PWA와 Audit Proxy

PWA와 audit proxy는 Node 기반 검증을 실행합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-audit-proxy run check
npm --prefix apps/vitalserver-audit-proxy test
```

### 5-5. Release 결과물 검증

release 결과물을 바꿨다면 build machine에서 결과물 검증까지 봅니다. 현장 Mac에서 실행하는
명령이 아니라, 전달 전에 release 담당자가 확인하는 명령입니다.

| 변경 | 확인 명령 |
|---|---|
| Product Update bundle | `make dist/update/release`와 `make dist/update/verify/release` |
| VM Image update bundle | `make dist/image-update/release`와 `make dist/image-update/verify/release` |
| 신규 설치 DMG | `make dist/dmg/release` |
| Reset Installer PKG | `make dist/reset-installer/release` |

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
- Settings apply의 `restartAfterSave`는 저장 후 항상 restart가 아니라, Configure policy가 VM runtime
  restart requirement를 반환했을 때 즉시 restart할지에 대한 intent입니다. policy 없이 UI나 CLI가
  restart 여부를 추정하면 안 됩니다.
- Settings UI의 restart 안내는 실행 정책이 아니라 표시 정책입니다. 실제 restart requirement의 source of
  truth는 Configure policy이고, UI는 현재 runtime 설정과 draft 설정의 차이를 사용자에게 설명하는 데
  그쳐야 합니다.
- VM stop/restart/poweroff 변경은 단일 VM state control 경로를 통하게 합니다. Settings, update,
  repair, watchdog이 guest shutdown 준비 contract를 우회해 개별적으로 VM service를 멈추지 않습니다.
  Settings restart, update shutdown-stop, rollback/update service start-stop, watchdog VM recovery,
  service-control, repair/guest-operation VM start/restart는 VM state control owner entrypoint를 통해
  Host side effect를 실행합니다. Update/rollback workflow는 operation plan 의미를 보존하되, Host service
  start/stop sequencing을 직접 소유하지 않습니다.
- Guest filesystem 또는 disk I/O 장애는 proxy/HTTP failure보다 상위의 guest storage 상태로 남깁니다.
  root filesystem read-only, filesystem error, disk I/O error가 명시되면 `guest-filesystem-read-only`,
  `guest-filesystem-error`, `guest-disk-io-error` reason으로 기록하고, `unknown(vm-...)`이나 단순
  host proxy failure로 축약하지 않습니다. 이 reason은 데이터 보존이 필요한 상태이므로 watchdog 자동
  recovery는 억제하고 backup/recreate 판단으로 연결합니다. 억제 status/event message는 reason만
  남기지 말고 `action=backup-and-recreate-vm`을 함께 기록해 자동 restart가 아닌 데이터 보존형 조치임을
  UI와 로그에서 구분할 수 있어야 합니다.
- Guest runtime-state read issue는 단순 `guest-runtime-state-invalid`로 축약하지 않습니다. load failure와
  metadata read failure는 각각 `guest-runtime-state-load-failed-*`,
  `guest-runtime-state-metadata-read-failed-*` reason으로 유지하고, runtime state input만 invalid로
  평가합니다. Watchdog은 stale runtime-state에서 파생된 container observation read issue와 실제
  observation source failure를 typed helper로 구분해야 합니다.
- VM/Host error raw string이 이미 category와 recovery action을 가진다면 `unknown(...)`으로 보관하지
  않습니다. Guest runtime state missing, VM disk attachment invalid, VM launch failure, VM configuration
  invalid, Host resource unavailable 같은 상태는 `RuntimeFailureReason` typed case로 승격하고, raw string
  parsing은 이전 status/event 문서를 읽기 위한 contract 호환 경로로만 둡니다.
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
| testkit smoke 성공 | simulated recorder가 기본 수집 경로를 통과함 |
| 주요 실패 패턴 재발 없음 | 이전에 기록한 update, 권한, contract, observability 문제가 다시 나타나지 않음 |

### 8-1. 실패를 보고할 때

검증 실패를 보고할 때는 “실패했다”가 아니라 다시 실행할 수 있는 자료를 남깁니다.

GitHub issue나 pull request에서 검증 실패를 보고할 때는 command, 환경, 실패 로그, 기대 결과를
함께 적습니다.
