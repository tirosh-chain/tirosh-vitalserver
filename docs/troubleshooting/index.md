# VitalServer Troubleshooting

VitalServer 운영 중 확인한 증상, 원인, 조치 방법의 진입점입니다. 긴 상세 조치는 케이스별 문서로 분리하고, 이 파일은 색인과 follow-up 규칙만 유지합니다.

## 문서 구조

- `docs/troubleshooting/index.md`: 증상 색인, 분류, follow-up 규칙
- `docs/troubleshooting/*.md`: 케이스별 상세 조치
- `docs/troubleshooting/_template.md`: 새 troubleshooting 케이스 작성 템플릿

## 빠른 증상표

| ID | 증상 | Category | Status | 먼저 볼 문서 |
|---|---|---|---|---|
| TS-001 | boot asset이 없다고 실패 | Local development | archived | [`make devtools/start`가 boot asset 없음으로 실패](001_boot-asset-missing.md) |
| TS-002 | VM IP가 `192.168.64.x` | Network | active | [VM IP가 `192.168.64.x`로 보임](002_vm-shared-nat-ip.md) |
| TS-003 | bridged mode가 `Killed: 9` | Network | archived | [bridged mode가 `Killed: 9`로 종료됨](003_bridged-mode-killed-9.md) |
| TS-004 | Docker 설치 중 disk full | Guest bootstrap | resolved | [`docker.io` 설치 중 `No space left on device`](004_docker-install-disk-full.md) |
| TS-005 | apt Release file 시간 오류 | Guest bootstrap | archived | [golden rootfs 준비 중 `apt-get update`가 Release file 시간 오류로 실패](005_apt-release-file-time-error.md) |
| TS-006 | cloud-init이 다시 안 돎 | Guest bootstrap | active | [cloud-init이 bootstrap을 다시 실행하지 않음](006_cloud-init-not-rerun.md) |
| TS-007 | nginx `502 Bad Gateway` | Runtime health | active | [nginx가 `502 Bad Gateway`를 반환](007_nginx-502-bad-gateway.md) |
| TS-008 | watchdog이 `host-proxy-http-502`를 표시 | Host proxy | active | [watchdog이 host proxy 502를 복구하지 못함](008_watchdog-host-proxy-502.md) |
| TS-009 | Redis가 `exec format error`로 재시작됨 | Guest containers | resolved | [Redis가 `exec format error`를 출력함](009_redis-exec-format-error.md) |
| TS-010 | Redis UI가 template fetch 오류를 표시 | Guest containers | resolved | [Redis UI가 `failed to fetch html template`을 표시](010_redis-ui-template-fetch-error.md) |
| TS-011 | Service health가 302를 Reachable로 표시 | Runtime health | resolved | [HTTP 302가 Reachable로 표시됨](011_http-302-reachable.md) |
| TS-012 | bundle update가 오래 멈춘 것처럼 보임 | Update | active | [bundle update가 health wait 또는 rollback에서 오래 멈춤](012_bundle-update-health-wait-rollback-stall.md) |
| TS-013 | update 후 VM disk/ext4 오류 | Update | resolved | [update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨](013_update-vm-disk-ext4-readonly.md) |
| TS-014 | update 후 Redis가 `exec format error` | Update | resolved | [update 후 Redis가 `exec format error`로 실패](014_update-redis-exec-format-error.md) |
| TS-015 | update 후 bootstrap이 `missing runtime package`로 실패 | Update | active | [update 후 bootstrap이 `missing runtime package`로 실패](015_update-missing-runtime-package.md) |
| TS-016 | Redis가 AOF 오류로 재시작 반복 | Data store | active | [Redis AOF 손상으로 runtime health가 회복되지 않음](016_redis-aof-corruption.md) |
| TS-017 | VM IP가 계속 `Waiting` | Runtime health | active | [VM은 부팅됐지만 VM IP가 계속 Waiting](017_vm-ip-waiting-bootstrap.md) |
| TS-018 | pkg 설치 후 Helper app이 안 보임 | Packaging | resolved | [pkg 설치 후 `/Applications`에 Helper app이 없음](018_pkg-helper-app-missing.md) |
| TS-019 | Helper app이 없어 GUI 삭제가 안 됨 | Uninstall | active | [Helper app 없이 설치물을 제거해야 함](019_uninstall-without-helper-app.md) |
| TS-020 | app container health가 오래 starting | Guest containers | active | [app container가 오래 `health: starting` 상태](020_app-container-health-starting.md) |
| TS-021 | Ubuntu arm64 `flash-kernel` 실패 | Guest bootstrap | resolved | [Ubuntu arm64 cloud image에서 `flash-kernel`이 실패](021_ubuntu-flash-kernel-failure.md) |
| TS-022 | 설치된 runtime binary에 virtualization entitlement가 없음 | Packaging | resolved | [설치된 runtime binary에 virtualization entitlement가 없음](022_missing-virtualization-entitlement.md) |
| TS-023 | stale pid file | Local development | archived | [`make runtime/status`가 stale pid file을 표시](023_stale-pid-file.md) |
| TS-024 | pkg 설치가 `Running package scripts...`에서 실패 | Packaging | active | [pkg 설치가 `Running package scripts...`에서 실패함](024_pkg-postinstall-timeout.md) |
| TS-025 | update 후 VM disk attachment invalid | Update | active | [update 후 VM disk attachment가 invalid로 실패](025_update-vm-disk-attachment-race.md) |
| TS-026 | PWA가 Runtime Control API unreachable 표시 | Runtime Control PWA | active | [PWA가 Runtime Control API unreachable을 표시](026_pwa-runtime-control-api-unreachable.md) |
| TS-027 | update 후 PWA가 이전 JS 사용 | Runtime Control PWA / Update | active | [Update 적용 후 PWA가 이전 JS를 계속 사용](027_update-stale-pwa-assets.md) |
| TS-028 | host proxy가 `/opt/homebrew/var/...`에 의존 | Host proxy / Packaging | resolved | [Host proxy가 Homebrew nginx runtime directory에 의존함](028_host-proxy-homebrew-runtime-directory.md) |
| TS-029 | update 중 Host가 Guest shutdown 상태를 추정 | Update | resolved | [Update 중 Host가 Guest shutdown 상태를 추정함](029_update-guest-shutdown-inference.md) |
| TS-030 | Runtime 상태를 Host/UI가 추정하거나 암묵 보정 | Runtime health / Update | resolved | [Runtime 상태를 Host/UI가 추정하거나 암묵 보정함](030_runtime-state-inference.md) |
| TS-031 | Recorder activity 그래프가 rolling window만 표시 | Runtime Control PWA / Observability | resolved | [Recorder activity 그래프가 rolling window만 표시함](031_recorder-activity-history-window.md) |
| TS-032 | macOS runtime 코드의 상태/관측 책임이 섞임 | Runtime health / Observability / Update | active | [macOS runtime 코드의 상태/관측 책임이 섞임](032_macos-runtime-explicit-responsibility-review.md) |
| TS-033 | Helper가 Settings/Export logs/event를 읽지 못함 | Runtime Control PWA / Observability | active | [Runtime Control Helper가 설정/로그/event를 읽지 못함](033_runtime-control-helper-read-permissions.md) |
| TS-034 | macOS runtime 권한 실패 검증이 부족함 | Update / Runtime Control PWA / Observability | active | [macOS runtime 권한 실패 검증이 부족함](034_macos-runtime-permission-failure-test-coverage.md) |
| TS-035 | Update가 Guest capability 계약 없이 request/result worker를 가정함 | Update | active | [Update가 Guest capability 계약 없이 request/result worker를 가정함](035_update-guest-capability-contract-missing.md) |
| TS-036 | macOS runtime 카오스 테스트 체계가 필요함 | Update / Runtime health / Observability / Packaging | resolved | [macOS runtime 카오스 테스트 체계가 필요함](036_macos-runtime-chaos-testing.md) |
| TS-037 | clean uninstall 이후 stale operation이 rollback/recovery를 유발함 | Uninstall / Update / Runtime health | active | [clean uninstall 이후 stale operation이 rollback/recovery를 유발함](037_clean-uninstall-stale-operation-recovery.md) |
| TS-038 | Guest kernel panic 이후 watchdog restart loop가 발생함 | Runtime health / VM disk / Watchdog recovery | implemented | [Guest kernel panic 이후 watchdog restart loop가 발생함](038_guest-kernel-panic-watchdog-restart-loop.md) |
| TS-039 | AGENTS.md 상태/실패 fallback 감사를 진행함 | Architecture / Runtime Control / Observability / TestKit | active | [AGENTS.md 상태/실패 fallback 감사를 진행함](039_agents-compliance-fallback-audit.md) |
| TS-040 | 건강한 boot 이후 VM lifecycle이 stale로 남음 | Runtime health / Observability | implemented | [VM lifecycle stale after healthy boot and log export gap](040_vm-lifecycle-stale-after-healthy-boot-log-export-gap.md) |
| TS-041 | proxy log history가 현재 VitalDB anomaly로 표시됨 | Runtime health | resolved | [Proxy log history shown as current VitalDB anomaly](041_proxy-log-history-current-vitaldb-anomaly.md) |
| TS-042 | Host install/uninstall state 계약 부족으로 cleanup/reinstall이 막힘 | Packaging / Uninstall / Runtime health | implemented | [Host install/uninstall state contract gap](042_host-install-uninstall-state-contract-gap.md) |
| TS-043 | Runtime workflow StateMachine과 계층 경계 정리가 필요함 | Architecture / Runtime workflow / macOS runtime | implemented | [Runtime workflow state machine and layer boundary cleanup](043_runtime-workflow-state-machine-layer-boundary.md) |
| TS-044 | Runtime uninstall workflow가 phase와 command 계약을 읽기 어렵게 섞음 | Runtime workflow / Readability / StateMachine | implemented | [Runtime uninstall workflow phase and command readability cleanup](044_runtime-uninstall-workflow-phase-command-readability.md) |
| TS-045 | Runtime install workflow가 uninstall 수준의 StateMachine 경계를 갖지 않음 | Runtime workflow / Install / StateMachine | implemented | [Runtime install workflow state machine parity](045_runtime-install-workflow-state-machine-parity.md) |
| TS-046 | pkg postinstall이 `Service is disabled`로 실패 | Packaging | active | [pkg postinstall fails when launchd service is disabled](046_pkg-postinstall-launchd-disabled.md) |
| TS-047 | Guest log sync service만 Stopped로 남음 | Runtime health | active | [Guest log sync service remains stopped after runtime restart](047_guest-log-sync-stopped-after-restart.md) |
| TS-048 | HostCLI runtime workflow 변경 영향이 과도하게 넓음 | Architecture / Runtime workflow / macOS runtime | active | [HostCLI runtime workflow boundary fragmentation](048_hostcli-runtime-workflow-boundary-fragmentation.md) |
| TS-049 | Update VM stop이 launchd 재시작 PID를 따라감 | Update / VM lifecycle | resolved | [Update VM stop follows launchd-restarted pid](049_update-vm-pid-restart-race.md) |
| TS-053 | Update와 watchdog이 runtime status를 두고 경합함 | Update / Runtime health | active | [Update와 watchdog이 runtime status를 두고 경합함](053_update-watchdog-operation-lease-race.md) |
| TS-054 | Fresh install 후 Helper message에 과거 update/uninstall 이력이 보임 | Runtime Control PWA / Packaging | active | [Helper message log shows stale session history after fresh install](054_helper-message-log-stale-session-history.md) |
| TS-055 | Helper app에서 Recorder activity `All` 선택 시 앱이 종료됨 | macOS Helper / Observability | resolved | [Recorder Activity All Window Materializes Full History](055_recorder-activity-all-window-materialization.md) |
| TS-056 | PWA Status가 `settings.bridgedinterface` contract mismatch를 표시 | Runtime Control PWA / Network | resolved | [PWA Runtime Overview Bridged Interface Contract Mismatch](056_pwa-runtime-overview-bridged-interface-contract.md) |
| TS-057 | watchdog이 stale guest runtime-state를 missing artifacts로 보고 복구하지 않음 | Runtime health / Watchdog recovery | resolved | [Watchdog Treats Stale Guest Runtime State As Unrecoverable](057_watchdog_stale_guest_runtime_state_unrecoverable.md) |
| TS-058 | Reset Installer 이후 VM launchd state가 남아 설치를 막음 | Uninstall / VM lifecycle | resolved | [Reset Installer Leaves VM Launchd State Behind](058_clean-uninstall-hung-vm-progress-marker.md) |
| TS-059 | Helper app에서 Recorder activity `All` 선택 시 Slider 생성 중 앱이 종료됨 | macOS Helper / Observability | active | [Recorder Activity All Single-Page Slider Crash](059_recorder-activity-all-single-page-slider-crash.md) |
| TS-060 | Helper update activation이 compose/testkit systemd 경합으로 실패 | Update | active | [Update Activation Compose/Systemd Race](060_update-activation-compose-systemd-race.md) |
| TS-061 | Update shutdown service failed without result | Update | resolved | [Update Shutdown Service Failed Without Result](061_update-shutdown-service-failed-without-result.md) |
| TS-062 | Helper clean uninstall이 `nohup` detach 실패로 시작되지 않음 | Uninstall | resolved | [Helper Clean Uninstall Nohup Detach Failure](062_helper-clean-uninstall-nohup-detach-failure.md) |
| TS-063 | Helper clean uninstall progress log permission denied | Uninstall | resolved | [Helper Clean Uninstall Progress Log Permission Failure](063_helper-clean-uninstall-progress-log-permission.md) |
| TS-064 | dev DMG rebuild가 unmounted stale attachment 때문에 실패함 | Packaging / Local development | resolved | [Dev DMG Rebuild Stale Unmounted Attachment](064_dev-dmg-rebuild-stale-unmounted-attachment.md) |
| TS-065 | Clean uninstall과 Reset Installer 경계가 혼동됨 | Uninstall / Packaging | active | [Clean Uninstall and Reset Installer Boundary](065_clean-uninstall-reset-installer-boundary.md) |
| TS-066 | Clean uninstall 성공 후 progress viewer만 실패를 표시함 | Uninstall | active | [Clean Uninstall Progress Viewer Shows Failed After Successful Uninstall](066_clean-uninstall-progress-viewer-stale-run.md) |
| TS-067 | 초기 설치 직후 VM bootstrap 중 Degraded가 표시됨 | Runtime health / Packaging | resolved | [Initial Install Shows Degraded During VM Bootstrap](067_initial-install-watchdog-degraded.md) |
| TS-068 | Settings Apply가 update처럼 VM shutdown을 표시함 | Runtime health / Runtime Control PWA | resolved | [Settings Apply Enters Update-Like Shutdown](068_settings-apply-update-shutdown-confusion.md) |
| TS-069 | Golden rootfs build가 stale marker/manifest를 proof로 믿을 수 있음 | Packaging / Local development / Guest bootstrap | implemented | [Golden Rootfs Build Trusts Stale Proof After Failed VM Preparation](069_golden-rootfs-stale-proof-negative-validation.md) |
| TS-070 | Golden disk가 실제 Runtime boot proof를 제공하지 않음 | Packaging / Local development / Runtime health / Guest bootstrap | active | [Golden Disk Runtime Boot Proof Gap](070_golden-disk-runtime-boot-proof-gap.md) |
| TS-071 | Golden rootfs apt snapshot unavailable을 VM start 후에야 감지함 | Packaging / Local development / Guest bootstrap | implemented | [Golden Rootfs Apt Snapshot Fast-Fail](071_golden-rootfs-apt-snapshot-fast-fail.md) |
| TS-072 | Release package build input failure를 비싼 build 후에야 감지함 | Packaging / Local development | implemented | [Release Package Build Late Failure Before Preflight](072_release-package-preflight-late-failure.md) |
| TS-073 | Installed bootstrap이 rootfs input metadata 누락으로 Critical이 됨 | Packaging / Install / Guest bootstrap | implemented | [Installed Bootstrap Missing Rootfs Input Metadata](073_installed-bootstrap-missing-rootfs-input-metadata.md) |
| TS-074 | Installed bootstrap이 빈 `lsblk PARTNUM` 출력으로 실패함 | Packaging / Install / Guest bootstrap | implemented | [Installed bootstrap fails when lsblk PARTNUM is empty](074_installed-bootstrap-lsblk-partnum-empty.md) |
| TS-075 | Service liveness uptime이 수백 일로 표시됨 | Runtime health / Runtime Control PWA | implemented | [Service liveness uptime shows hundreds of days](075_service-liveness-uptime-clock-skew.md) |
| TS-076 | Update shutdown 중 compose stop timeout 후 rollback됨 | Update / Guest containers | implemented | [Update shutdown compose stop timeout and guest time drift](076_update-shutdown-compose-stop-timeout-and-guest-time-drift.md) |
| TS-077 | VitalServer backup restore가 data layout 호환성을 확인해야 함 | Data store / Runtime health | active | [Runtime Data Backup Compatibility Gate](077_runtime-data-backup-compatibility.md) |
| TS-078 | Upstream Redis backup command가 Redis SAVE 응답을 무기한 기다림 | Packaging / Troubleshooting Tools / Redis migration | implemented | [Upstream Redis SAVE Timeout](078_upstream-redis-save-timeout.md) |
| TS-079 | VitalServer Helper backup restore 실패가 UI progress/message에 표시되지 않음 | Data store / Runtime health | implemented | [Runtime Data Restore Silent Failure](079_runtime-data-restore-silent-failure.md) |
| TS-080 | Update shutdown이 Compose service 목록 stdout 누락으로 실패함 | Update / Guest containers | implemented | [Update Shutdown Compose Services Stdout Missing](080_update-shutdown-compose-services-stdout-missing.md) |
| TS-081 | Upstream VitalServer contract verification이 release compile 전에 실패함 | Packaging / Upstream integration | active | [Upstream VitalServer Contract Verification Failure](081_upstream-vitalserver-contract-verification.md) |
| TS-082 | 배포 target이 phase별 검증 완료를 명확히 증명하지 못함 | Packaging / Release verification | active | [Distribution Verification Phase Gaps](082_distribution-verification-phase-gaps.md) |
| TS-083 | 자동 VitalServer Helper backup이 Recovery operations 목록에 표시되지 않음 | Runtime health / Data store / macOS Helper UI | implemented | [Automatic Backup Not Visible in Recovery Operations](083_automatic-backup-not-visible-in-recovery.md) |
| TS-084 | TestKit vital upload가 My Files에 표시되지 않음 | TestKit / Upstream integration | active | [TestKit vital upload가 My Files에 표시되지 않음](084_testkit-vital-upload-not-visible-in-my-files.md) |
| TS-085 | TestKit vital upload가 413 Request Entity Too Large로 실패함 | Host proxy / Guest containers / TestKit | active | [TestKit vital upload가 413 Request Entity Too Large로 실패함](085_vital-upload-413-request-entity-too-large.md) |
| TS-086 | TestKit bed suffix가 Web Monitoring에서 보이지 않음 | TestKit / Upstream integration | active | [TestKit bed suffix가 Web Monitoring에서 보이지 않음](086_testkit-bed-suffix-hidden-in-web-monitoring.md) |
| TS-087 | OOM recovery 이후 watchdog service가 빠져 status가 recovering에 머묾 | Runtime health / Launchd recovery | implemented | [Watchdog Not Loaded After OOM Recovery](087_watchdog-not-loaded-after-oom-recovery.md) |
| TS-088 | Fresh install 후 Redis Relay image/source 누락으로 bootstrap 실패 | Packaging / Guest bootstrap | implemented | [Redis Relay Missing From Package Bundle](088_redis-relay-missing-from-package-bundle.md) |
| TS-089 | macOS host watchdog timeout으로 재부팅됨 | Runtime health / Host resources / VM lifecycle | active | [Host macOS Watchdog Timeout Under VM Memory Pressure](089_host-macos-watchdog-timeout-under-vm-memory-pressure.md) |
| TS-090 | VitalServer app OOM을 app boundary와 명시 증거로 분리해야 함 | Runtime health / Recorder streaming | implemented | [VitalServer App OOM Boundary And Evidence](090_vitalserver-app-oom-boundary-and-evidence.md) |
| TS-091 | Golden rootfs smoke가 edge-ready 통과 후 cleanup wait 예산에 걸림 | Packaging / Local development / Guest bootstrap | implemented | [Golden Rootfs Cleanup Wait Timeout](091_golden-rootfs-cleanup-timeout.md) |
| TS-092 | Recorder ingress raw archive disk pressure를 realtime skip과 분리해야 함 | Runtime health / Recorder streaming | active | [Recorder Ingress Raw Archive Disk Pressure](092_recorder-ingress-raw-archive-disk-pressure.md) |
| TS-093 | Golden runtime smoke가 `runtime-settings.json` 누락으로 manifest를 만들지 못함 | Packaging / Guest bootstrap | active | [Golden Runtime Smoke Missing Runtime Settings](093_runtime-smoke-missing-runtime-settings.md) |
| TS-094 | Watchdog이 VitalDB observation 누락 때문에 Compose recovery를 막음 | Runtime health / Watchdog recovery / Guest containers | active | [Watchdog VitalDB Observation Blocks Compose Recovery](094_watchdog-vitaldb-observation-blocks-compose-recovery.md) |
| TS-095 | Guest Compose 실패의 inner stderr가 공유 진단에 남지 않음 | Guest bootstrap / Runtime health / Diagnostics | active | [Guest Compose Failure Missing Diagnostics](095_guest-compose-failure-missing-diagnostics.md) |
| TS-096 | Helper Settings가 invalid slider value/range로 SIGTRAP 종료됨 | Runtime health / macOS Helper UI | active | [Helper Settings Slider Crash](096_helper-settings-slider-crash.md) |
| TS-097 | Recorder ingress 재시작 후 VRecorder가 재접속하지 않는 것처럼 보임 | Runtime health / Recorder streaming / Proxy | implemented | [Recorder reconnect after ingress restart](097_recorder-reconnect-after-ingress-restart.md) |
| TS-098 | TestKit 전송은 되지만 Operation에 timeout이 남음 | TestKit / macOS Helper UI | active | [TestKit operation timeout after session start](098_testkit-operation-timeout-after-session-start.md) |
| TS-099 | Runtime v2 acceptance가 sandbox 환경 제약으로 완료되지 않음 | Runtime v2 acceptance / Local development | active | [Runtime v2 acceptance is blocked by local environment restrictions](099_runtime-acceptance-environment-blockers.md) |
| TS-100 | Guest는 healthy인데 Host가 `missing-vm-ip`로 critical 표시 | Runtime health / Guest bootstrap | active | [Missing `vm-ip` bootstrap file after runtime-state refactor](100_missing-vm-ip-bootstrap-file-after-runtime-state-refactor.md) |
| TS-101 | Docker image bundle build가 `context canceled`와 traceback으로 끝남 | Packaging / Local development / Docker image bundle | implemented | [Docker build context canceled after interrupt](101_docker-build-context-canceled-after-interrupt.md) |
| TS-102 | Helper 설치 후 guest는 healthy인데 status가 Critical로 남음 | Runtime health / macOS Helper UI | active | [Helper status stays Critical after guest is healthy](102_helper-status-critical-after-healthy-guest.md) |
| TS-103 | Guest service가 healthy인데 `SpecMissing`으로 표시됨 | Runtime health / Guest containers / macOS Helper UI | resolved | [Guest service spec missing while containers are healthy](103_guest-service-spec-missing-with-healthy-containers.md) |
| TS-104 | 새 설치 후 runtime은 healthy인데 Helper가 Installing으로 남음 | Runtime health / macOS Helper UI / Packaging | active | [Helper stays Installing after provisioned install](104_helper-stays-installing-after-provisioned.md) |
| TS-105 | Guest product services가 `/runtime/stack` timeout으로 Degraded 표시 | Runtime health / Guest containers / macOS Helper UI | active | [Guest stack status times out on docker stats](105_guest-stack-status-timeout-from-docker-stats.md) |
| TS-106 | Product Lab recorder start가 `/api/send` 404로 실패 | Product Lab / Recorder streaming / macOS Helper UI | active | [Product Lab recorder send 404](106_product-lab-recorder-send-404.md) |
| TS-107 | 새 Helper 설치본이 이미 수정된 guest-tools 동작을 포함하지 않음 | Packaging / Guest bootstrap / Clean install | active | [Stale guest-tools rootfs cache in clean install](107_stale-guest-tools-rootfs-cache-in-clean-install.md) |
| TS-108 | Product Lab 연결이 매 frame 끊기고 파형·packet history가 비정상 | Product Lab / Recorder streaming / Observability | resolved | [Product Lab send succeeds but VitalDB tracks are empty](108_product-lab-send-without-vitaldb-tracks.md) |
| TS-109 | VM 재시작 후 `/runtime/stack`가 stale service health 문서 때문에 503 | Runtime health / Guest containers / Data store | active | [Guest stack status fails on stale service health document](109_guest-stack-status-fails-on-stale-service-health.md) |
| TS-110 | UI를 실행하지 않으면 VM launcher가 Platform API 연결 실패로 boot 전에 중단 | Packaging / Local development | resolved | [VM launcher requires UI-hosted Platform API](110_vm-launcher-requires-ui-hosted-platform-api.md) |
| TS-111 | amd64 Linux bundle의 container image가 실제로는 arm64 | Packaging / Guest containers | resolved | [Linux Runtime image archive architecture mismatch](111_linux-runtime-image-archive-architecture-mismatch.md) |
| TS-112 | Linux 설치 중단이 성공처럼 보이거나 partial state를 남김 | Packaging / Update | resolved | [Linux installation interruption reports or leaves partial state](112_linux-install-interruption-partial-state.md) |
| TS-113 | Linux Native Provider와 installer의 Compose project가 다름 | Runtime health / Guest containers | resolved | [Linux Native Provider Compose project mismatch](113_linux-native-provider-compose-project-mismatch.md) |
| TS-114 | `/tmp`의 Linux update bundle을 Agent가 찾지 못함 | Packaging / Update | resolved | [Linux update bundle is invisible to the Platform Agent](114_linux_update_bundle_invisible_private_tmp.md) |
| TS-115 | config가 가리키는 Linux support export tool이 release에 없음 | Packaging / Update | resolved | [Linux Platform Agent restarts because support export tool is missing](115_linux_platform_agent_support_export_tool_missing.md) |
| TS-116 | Linux update acceptance가 support export를 중첩 실행해 409로 rollback | Packaging / Update | resolved | [Linux update rolls back when installed acceptance starts support export](116_linux_update_acceptance_nested_support_workflow.md) |
| TS-117 | Docker multi-platform export가 Guest platform blob을 누락함 | Packaging / Guest bootstrap / Docker image bundle | resolved | [Docker multi-platform export omitted Guest blobs](117_docker_multiplatform_export_missing_guest_blobs.md) |
| TS-118 | Guest bootstrap이 product image를 다시 build하려고 함 | Packaging / Guest bootstrap / Guest containers | resolved | [Guest bootstrap product image rebuild fallback](118_guest_bootstrap_product_image_rebuild_fallback.md) |
| TS-119 | Release sync가 Docker export 뒤 compile input을 rewrite함 | Packaging / Release contract / Rootfs compile | resolved | [Release sync mutated compile inputs after Docker export](119_release_sync_mutated_compile_inputs.md) |
| TS-120 | Guest wheel 생성물이 같은 delivery run의 rootfs fingerprint를 바꿈 | Packaging / Rootfs compile / Local development | resolved | [Generated Guest wheel changed rootfs fingerprint during the same delivery run](120_generated_guest_wheel_changes_rootfs_fingerprint.md) |
| TS-121 | pkg 설치가 runtime disk 공간 부족으로 실패함 | Packaging / Install | active | [pkg 설치가 runtime disk 공간 부족으로 실패함](121_pkg_install_insufficient_runtime_disk_space.md) |
| TS-122 | 새 설치 직후 VitalDB read model table이 없어 상태 조회가 실패함 | Runtime health / Data store | active | [VitalDB read model schema startup race](122_vitaldb_schema_reader_startup_race.md) |
| TS-123 | Golden rootfs Guest Tools 설치가 psycopg wheel 누락으로 실패함 | Packaging / Guest bootstrap | active | [Guest Tools air-gap dependency missing from wheelhouse](123_guest_tools_airgap_dependency_missing.md) |
| TS-124 | Runtime smoke bootstrap이 Postgres 시작 전 schema migration으로 실패함 | Guest bootstrap / Data store | active | [VitalDB schema migration runs before Postgres readiness](124_vitaldb_schema_migration_before_postgres_ready.md) |
| TS-125 | 생성한 Product Lab session이 목록에 없고 recorder를 개별 제어할 수 없음 | Product Lab / Runtime Control PWA / macOS Helper UI | resolved | [Product Lab session collection and recorder controls missing](125_product-lab-session-collection-recorder-control-missing.md) |
| TS-126 | Golden rootfs smoke가 Host에서 허용된 Python 3.14 문법 때문에 Guest Python 3.12에서 실패함 | Packaging / Guest bootstrap | resolved | [Guest wheel uses Python syntax newer than the Guest runtime](126_guest-wheel-python-syntax-newer-than-runtime.md) |
| TS-127 | 설치 직후 Runtime product services가 정상화 후에도 `missing-vm-ip`를 표시함 | Runtime health / macOS Helper UI | active | [Runtime product services keeps the initial `missing-vm-ip` failure](127_runtime-product-services-stale-missing-vm-ip.md) |
| TS-128 | 실제 Vital Recorder는 접속했지만 목록 또는 packet graph가 비어 있거나 갱신되지 않음 | Runtime health / Recorder streaming / Observability | package verification pending | [Vital Recorder is connected but the recorder list or packet graph does not update](128_vital-recorder-read-model-empty-and-activity-graph-missing.md) |
| TS-129 | VitalDB Recorder/Bed 삭제 후 Product Lab session과 정보가 남음 | Runtime Control PWA / Product Lab / Observability | resolved | [VitalDB delete leaves the Product Lab session running](129-vitaldb-delete-leaves-product-lab-session.md) |
| TS-130 | Vital Files upload가 단일 Guest path를 받고 replay가 선택 파일을 읽지 않음 | Runtime Control PWA / Product Lab | resolved | [Vital Files upload accepts one path and replay does not use the selected file](130_vital-files-upload-and-replay-semantics.md) |
| TS-131 | Settings 저장 후 VM 재시작이 invalid config, 잘못된 activation intent, 조기 applied 기록으로 실패 | Packaging / Runtime health / macOS Helper | package verification pending | [Settings VM restart fails after saving VM activation settings](131_settings-vm-restart-invalid-config-and-platform-agent-stop.md) |
| TS-132 | Golden rootfs가 Host settings SQLite 없이 launcher를 시작해 manifest 생성 전 timeout | Packaging / Guest bootstrap | resolved | [Golden rootfs times out before creating the runtime manifest](132_golden-rootfs-launcher-missing-host-settings-sqlite.md) |
| TS-133 | Golden rootfs proof 통과 후 lifecycle은 stopped지만 launcher PID가 남아 package 생성 중단 | Packaging / Local development / VM lifecycle | resolved | [Golden rootfs cleanup reports stopped while launcher still runs](133_golden-rootfs-stopped-lifecycle-launcher-process-race.md) |
| TS-134 | PKG fresh install이 Host settings materialization 전에 `vm-config.json`을 읽어 즉시 실패 | Packaging / Host state persistence | package install verification pending | [PKG fresh install fails before Host settings materialization](134_pkg-fresh-install-host-settings-before-materialization.md) |
| TS-135 | Helper가 root-owned Host SQLite를 직접 열어 runtime 상태와 설정이 unavailable | Runtime health / macOS Helper UI / Host state persistence | package verification pending | [Helper direct SQLite access after Host state cutover](135_helper-direct-sqlite-access-after-host-state-cutover.md) |
| TS-136 | Clean uninstall이 Platform Agent를 남겨 재설치가 fresh-install preflight에서 차단됨 | Uninstall / Packaging | package verification pending | [Clean uninstall leaves Platform Agent loaded](136_clean-uninstall-leaves-platform-agent-loaded.md) |
| TS-137 | Lab Finish 및 recorder ingress cold path가 `.vital`을 생성·업로드하지 않음 | Product Lab / Recorder streaming / Cold path | resolved | [Lab Finish and recorder ingress cold path do not upload Vital Files](137_lab_stop_and_ingress_cold_path_do_not_upload_vital.md) |
| TS-138 | Golden rootfs 준비는 통과하지만 압축 단계가 제거된 lifecycle JSON을 요구함 | Packaging / Host state persistence | resolved | [Golden rootfs preparation passes but compression requires lifecycle JSON](138_golden-rootfs-compression-requires-removed-lifecycle-json.md) |
| TS-139 | Direct Helper PKG repair/upgrade/downgrade가 effect 전에 차단되지 않음 | Packaging / Host state persistence | contained by 0.2.1 fresh-only contract | [Direct Helper PKG repair, upgrade, or downgrade is blocked before effects](139_pkg_reinstall_rejected_or_deletes_existing_runtime.md) |
| TS-140 | 설치 Guest의 Docker image load가 `unexpected EOF` 뒤 부분 기동됨 | Guest bootstrap / Guest containers / Packaging | active | [Installed Guest Docker load ends with unexpected EOF](140_installed_guest_docker_load_unexpected_eof.md) |
| TS-141 | Settings Apply 후 Helper의 Runtime Control 요청이 stale session으로 401 실패 | Runtime Control PWA / macOS Helper UI | package verification pending | [Settings Apply 후 Runtime Control 인증이 401로 실패함](141_settings_apply_stale_runtime_control_browser_session.md) |
| TS-142 | Settings restart 또는 Host reboot가 `stopping`에 남아 VM 시작을 반복 실패 | Runtime health / VM lifecycle / macOS Helper | package verification pending | [Settings restart or Host reboot leaves VM lifecycle in stopping](142_settings_restart_stuck_stopping.md) |
| TS-143 | PWA Runtime Control read가 nullable field 계약 검증에 실패하거나 Guest resource에서 501 반환 | Runtime Control PWA / Runtime health | package verification pending | [PWA Runtime Control reads fail contract validation or return 501](143_pwa_runtime_control_contract_fields_and_guest_reads.md) |
| TS-144 | `.vital` upload 성공 표시 후 Replay 목록이 계속 비어 있음 | Runtime Control PWA / Product Lab | package verification pending | [Vital Files upload reports success but Replay list stays empty](144_vital-upload-bypasses-vitalserver-index.md) |
| TS-145 | Host ext4 editor가 Ubuntu root에 파일을 쓰지 못함 | Guest artifact compilation | root-editor boundary removed; boot proof pending | [Host ext4 editor가 Ubuntu root에 파일을 쓰지 못함](145_guest-root-filesystem-editor-ext4-extents.md) |
| TS-146 | Apple Virtualization이 bootstrap ISO를 disk attachment로 열지 못함 | Guest artifact compilation / macOS virtualization | implementation verified; entitlement-signed Guest boot evidence pending | [Apple Virtualization bootstrap storage-image format boundary](146_vz_bootstrap_storage_image_format_boundary.md) |
| TS-147 | macOS VM supervisor가 Virtualization entitlement 없이 VZ configuration validation에 실패 | Packaging / macOS virtualization | staged-signing verification implemented; signed identity execution evidence pending | [macOS VM supervisor Virtualization entitlement signature](147_macos_virtual_machine_supervisor_virtualization_entitlement_signature.md) |
| TS-148 | macOS VM start가 VZErrorDomain/code=1로 Guest boot console 이전에 실패 | macOS virtualization / Guest boot diagnostics | diagnostic contract implemented; native start cause pending | [macOS VM start failure before Guest boot console](148_macos_virtual_machine_start_fails_before_guest_boot_console.md) |
| TS-155 | Host install transaction이 payload 실패 뒤 서비스를 멈춘 채 남음 | Packaging / Host state persistence | C50 implemented; Helper 0.2.1 fresh-only; clean-Host C24 evidence pending | [Host installation transaction strands services after payload failure](155_host_installation_transaction_strands_services_after_payload_failure.md) |
| TS-156 | macOS `launchctl`의 missing-service 응답이 clean Runtime Platform pkg install을 차단함 | Packaging / Host installation | active | [macOS launchctl missing service blocks clean pkg install](156_macos_launchctl_missing_service_blocks_clean_pkg_install.md) |
| TS-157 | Electron Builder DMG build가 temporary disk image attachment를 남김 | Packaging / Local development | active | [Electron Builder DMG build leaves a temporary disk image attached](157_electron_builder_dmg_stale_temporary_attachment.md) |
| TS-158 | DEB removal 뒤 completion verifier가 없어 C54 terminal receipt를 쓸 수 없음 | Packaging / Uninstall | resolved | [Linux DEB removal loses its completion verifier after package payload deletion](158_linux_deb_removal_completion_transport.md) |
| TS-161 | macOS Host Agent가 staged update bundle store 누락으로 종료됨 | Packaging / Host installation / Update | fixed; clean-install verification pending | [macOS Host Agent exits when the staged update bundle store is absent](161_macos_host_agent_staged_update_bundle_store_missing.md) |
| TS-162 | Finder metadata가 compiled Guest deploy에 들어가 rootfs receipt mismatch 발생 | Packaging / Rootfs compile / Guest deploy | fixed and verified | [Rootfs receipt mismatch after Finder metadata enters compiled deploy](162_rootfs_receipt_mismatch_from_finder_metadata.md) |
| TS-163 | Finder가 macOS artifact staging 정리 중 metadata를 다시 만들어 PKG/update build가 `Directory not empty`로 실패 | Packaging / Local development | fixed and verified | [macOS artifact staging cleanup fails when Finder recreates metadata](163_pkg-staging-cleanup-finder-metadata-race.md) |
| TS-164 | 기존 설치 위 PKG 재설치 후 Guest Docker stop timeout으로 VM이 `Starting`에 머묾 | Packaging / Guest bootstrap / Guest containers | resolved | [PKG reinstall leaves VM Starting after Guest Docker stop timeout](164_pkg-reinstall-guest-docker-stop-timeout.md) |
| TS-165 | 다일치 이력을 보존한 PKG 재설치 후 activity migration OOM으로 VM이 `Starting`에 머묾 | Packaging / Guest bootstrap / Data store / Observability | superseded by clean PostgreSQL schema line | [PKG reinstall leaves VM Starting after activity projection migration OOM](165_pkg-reinstall-activity-migration-oom.md) |
| TS-166 | PKG 재설치 시 교체 bootstrap보다 구버전 Guest consumer가 먼저 기동해 OOM/Compose stop race가 발생함 | Packaging / Guest bootstrap / Guest containers / Observability | active | [PKG reinstall boots old Guest consumers before replacement bootstrap](166_pkg-reinstall-pre-bootstrap-consumer-race.md) |
| TS-167 | 정상적인 VitalDB numeric `srate=0` 트랙이 Lab 재생 검증에서 거부됨 | Product Lab / Guest containers / Runtime Control PWA | active | [Lab replay rejects valid VitalDB numeric tracks with zero sample rate](167_lab-vital-numeric-zero-srate-replay-failure.md) |
| TS-168 | canonical Vital v3 artifact가 고정 offset parser에서 비어 있거나 손상된 파일로 처리됨 | Vital Files / Guest containers / TestKit | active | [Canonical Vital v3 artifact is misindexed by a fixed-offset parser](168_vital-v3-header-fixed-offset-parser.md) |
| TS-169 | 대용량 Vital Files upload가 경계별 전체 buffer 또는 동시 request로 메모리 압력/OOM을 유발함 | Runtime Control PWA / Guest containers / Vital Files | fixed, operational verification pending | [Vital Files upload memory pressure and request boundary](169_vital-upload-memory-pressure-and-request-boundary.md) |
| TS-170 | Golden rootfs가 올바른 Guest Tools local wheel hash를 unexpected로 거부함 | Packaging / Guest bootstrap | fixed, package verification pending | [Golden rootfs Guest Tools local wheel hash closure failure](170_golden-rootfs-guest-tools-local-wheel-hash-closure.md) |
| TS-171 | Golden rootfs APT 진행 후 manifest 생성 전에 600초 timeout으로 VM이 종료됨 | Packaging / Local development / Guest bootstrap | implemented | [Golden rootfs times out after APT progress but before manifest](171_golden-rootfs-apt-progress-timeout-before-manifest.md) |
| TS-172 | Golden rootfs compose build가 local Python package 누락으로 실패함 | Packaging / Local development / Guest bootstrap | implemented | [Golden rootfs compose build cannot find a local package](172_golden-rootfs-compose-build-missing-local-package.md) |
| TS-173 | Product Lab 세션의 archive finalization null 필드가 Host 응답에서 누락되어 PWA 계약 검증 실패 | Runtime Control PWA / macOS Runtime Control | resolved | [PWA rejects Product Lab sessions when archive finalization null fields disappear](173_pwa-lab-archive-finalization-null-contract.md) |
| TS-174 | Vital File replay는 전송되지만 모든 트랙의 monitor type이 없어 VitalServer graph가 비어 있음 | Product Lab / Runtime Control PWA / Upstream integration | active | [Lab replay succeeds but VitalServer graph stays empty](174_lab-vital-replay-no-graph-compatible-tracks.md) |
| TS-175 | Distribution review의 proxy readiness 테스트가 빈 stderr로 간헐 실패 | Packaging / Host proxy / Local development | resolved | [Distribution review proxy readiness test exits with empty stderr](175_distribution-review-proxy-run-readiness-test-timeout.md) |
| TS-176 | Swift Beds 탭 장시간 사용 후 관계 이력 증가로 탭 전환이 느려짐 | macOS Helper / VitalDB relationships / Performance | resolved | [Swift Beds tab becomes slow after remaining open](176_swift_beds_tab_relationship_history_growth.md) |
| TS-177 | 생성 완료된 Helper DMG를 orphan `diskimages-helper`가 점유해 검증이 `EAGAIN`으로 실패 | Packaging / Local development | resolved | [Release DMG verification fails while an orphaned helper holds the image](177_release_dmg_orphaned_diskimages_helper.md) |
| TS-178 | VitalServer upload는 성공했지만 native Recorder `.vital` 파일이 Recorder Details에 귀속되지 않음 | Recorder streaming / Runtime Control PWA | active | [Native Recorder Vital upload is not attributed to a Recorder](178_native-recorder-vital-upload-not-attributed.md) |
| TS-179 | 중앙 PostgreSQL 마이그레이션이 기존 비관리 relation 또는 revision/DDL 오류로 기동을 차단함 | Guest bootstrap / Data store | active | [PostgreSQL schema migration failed](179_postgres_schema_migration_failed.md) |
| TS-180 | PostgreSQL migration service 추가 후 distribution review의 Guest seccomp 선언 수 계약이 이전 값으로 남음 | Packaging / Guest containers | resolved | [Distribution review rejects the PostgreSQL migration service seccomp contract](180_distribution_review_compose_seccomp_count.md) |
| TS-181 | 신규 관측은 202이지만 1 MiB 초과 Recorder 초기 backlog가 nginx HTML 413으로 거절됨 | Recorder observability / Host proxy / Guest edge | active | [Recorder observability backlog is rejected by nginx 413](181_recorder-observability-backlog-nginx-413.md) |
| TS-182 | vNext C76 PostgreSQL backup/restore CLI가 설정 URL 대신 local socket과 OS role로 접속함 | Data store / Guest bootstrap | active | [vNext PostgreSQL backup or restore CLI connects to the local socket](182_vnext_postgresql_backup_cli_uses_local_socket.md) |
| TS-183 | 제품 소스 변경마다 golden rootfs APT를 다시 실행함 | Packaging / Local development / Guest bootstrap | implemented | [Golden rootfs가 소스 변경마다 APT를 다시 실행함](183_golden-rootfs-repeats-apt-after-source-change.md) |
| TS-184 | Clean uninstall이 configured external Vital files directory 전체를 삭제할 수 있음 | Uninstall / Packaging | implemented; package verification pending | [Clean uninstall must preserve the configured external Vital files directory](184_clean-uninstall-external-vital-files-directory-deletion.md) |
| TS-185 | 공식 VM Image Update가 updater bridge로 잘못 표시되어 normal apply에서 거부됨 | Update / Packaging | implemented; apply-smoke pending | [VM Image Update is incorrectly marked as requiring an Updater bridge](185_vm-image-update-inferred-two-phase-bridge.md) |
| TS-186 | Recorder send_data가 durable admission 전에 억제되어 waveform/activity가 누락될 수 있음 | Recorder ingress / Data delivery | active | [Recorder send_data가 durable admission 전에 억제됨](186_recorder-send-data-suppressed-before-durable-admission.md) |
| TS-187 | Standard uninstall 보존 자료가 product root를 다시 만들어 fresh install을 막음 | Uninstall / Packaging | implemented; package verification pending | [Standard uninstall retained data blocks fresh package install](187_standard-uninstall-retained-data-blocks-fresh-install.md) |
| TS-188 | integrity 확인 성공이 trusted publisher 인증으로 오해되어 0.2.1 unsigned bundle apply가 열릴 수 있음 | Update / Packaging | active | [Update bundle integrity is mistaken for publisher authenticity](188_update_bundle_integrity_mistaken_for_publisher_trust.md) |
| TS-189 | Linux portable gate가 mocked macOS command를 실제 system path로 검증하다 실패함 | Packaging / Local development | resolved | [Portable CI declares macOS system tools as test fixtures](189_portable_ci_declares_macos_system_tools.md) |
| TS-190 | macOS 기본 OpenSSL이 Ed25519 update signing을 지원하지 않음 | Packaging / Update / Local development | resolved | [macOS OpenSSL cannot create an Ed25519 update signing key](190_macos_openssl_ed25519_release_signing_unavailable.md) |
| TS-191 | PKG/DMG build에 stable updater 공개키 trust store가 없거나 invalid함 | Packaging / Update / Local development | active | [Release package bootstrap trust store is missing or invalid](191_release_package_bootstrap_trust_store_missing_or_invalid.md) |
| TS-192 | stable update가 중단된 뒤 journal 상태별 명시 복구가 필요함 | Update / Host runtime / Recovery | active | [Update bootstrap journal requires explicit recovery](192_update_bootstrap_journal_requires_explicit_recovery.md) |
| TS-193 | next updater handoff에 인증된 layer 순서가 누락됨 | Update / Bootstrap handoff / Next updater | resolved | [Update handoff invocation cannot prove the authenticated layer order](193_update_handoff_missing_authenticated_layer_order.md) |
| TS-194 | layer effect process가 typed receipt 없이 종료됨 | Update / Next updater / Layer effect | resolved | [Layer effect process exits without a typed receipt](194_layer_effect_exit_without_typed_receipt.md) |
| TS-195 | bootstrap bundle에서 specification 소유 payload가 누락됨 | Update / Release composition / Bundle closure | resolved | [Bootstrap bundle omits specification-owned payload](195_bootstrap_bundle_omits_specification_payload.md) |

## Follow-up 규칙

새 증상이나 재발 이슈를 문서화할 때는 아래 순서를 따릅니다.

1. `docs/troubleshooting/_template.md`를 복사해 `docs/troubleshooting/<short-case-name>.md`를 만듭니다.
2. 다음 `TS-XXX` 번호를 부여하고 `Category`, `Owner`, `Status`를 먼저 채웁니다. Owner는 문제를 최종적으로 수습할 책임 영역입니다.
3. 증상, 원인, 확인 명령, 조치, 운영 판단을 분리해서 작성합니다.
4. 관련 issue/PR, 수정 버전, 재현 로그는 케이스 문서의 `Follow-up` 섹션에 누적합니다.
5. 이 색인의 빠른 증상표에 새 케이스를 추가합니다.

## Status 기준

`Status`는 해당 troubleshooting 문서의 현재 유효성을 나타냅니다. 제품 상태를 의미하지 않습니다.

| Status | 의미 |
|---|---|
| `active` | 현재 버전이나 현장 설치본에서 여전히 참고해야 하는 증상/조치입니다. |
| `resolved` | 원인은 수정됐지만, 이전 설치본이나 과거 분석을 위해 보존하는 문서입니다. |
| `superseded` | 더 정확한 새 문서가 생겼고, 이 문서는 링크/맥락 보존용입니다. |
| `archived` | 더 이상 재현 가능성이 낮고 운영 판단에 거의 쓰지 않는 기록입니다. |

새로 추가하는 문서는 기본적으로 `active`로 시작합니다. 수정이 release/update bundle/package에 포함되고, 이전 설치본에서만 참고하면 되는 상태가 되면 `resolved`로 바꿉니다. 새 문서가 더 정확한 원인과 조치를 설명하면 기존 문서는 `superseded`로 바꾸고 `Related Cases`에 새 ID를 남깁니다.

## Category 기준

| Category | 의미 |
|---|---|
| Update | update bundle 적용, guest activation, rollback, VM disk 보존 경계 |
| Runtime health | VM, VitalServer, host proxy, readiness 관측 문제 |
| Guest bootstrap | cloud-init, rootfs 준비, guest package/bootstrap 문제 |
| Guest containers | Docker image, Compose service, container health 문제 |
| Data store | Redis 데이터/AOF/backup/repair 문제 |
| Host proxy | macOS nginx proxy, port 점유, proxy recovery 문제 |
| Runtime Control PWA | Remote Console web UI, local Runtime Control API, browser cache/service worker 문제 |
| Network | shared/NAT, bridged mode, 노출 주소 문제 |
| Packaging | pkg/dmg, signing, entitlement, app bundle 설치 문제 |
| Uninstall | 제거/clean 정책과 잔여 파일 문제 |
| Local development | 개발용 make/VM 상태 파일 문제 |
| TestKit | testkit recorder/session/artifact 검증과 upstream VitalServer 연동 문제 |

## Reference

- [Troubleshooting reference](reference.md)
