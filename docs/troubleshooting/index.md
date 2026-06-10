# VitalServer Troubleshooting

VitalServer 운영 중 확인한 증상, 원인, 조치 방법의 진입점입니다. 긴 상세 조치는 케이스별 문서로 분리하고, 이 파일은 색인과 follow-up 규칙만 유지합니다.

## 문서 구조

- `docs/troubleshooting/index.md`: 증상 색인, 분류, follow-up 규칙
- `docs/troubleshooting/*.md`: 케이스별 상세 조치
- `docs/troubleshooting/_template.md`: 새 troubleshooting 케이스 작성 템플릿

## 빠른 증상표

| ID | 증상 | Category | Status | 먼저 볼 문서 |
|---|---|---|---|---|
| TS-001 | boot asset이 없다고 실패 | Local development | archived | [`make vm-start`가 boot asset 없음으로 실패](001_boot-asset-missing.md) |
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
| TS-023 | stale pid file | Local development | archived | [`make vm-status`가 stale pid file을 표시](023_stale-pid-file.md) |
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

## Reference

- [Troubleshooting reference](reference.md)
