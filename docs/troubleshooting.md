# VitalServer Troubleshooting

VitalServer 운영 중 확인한 증상, 원인, 조치 방법의 진입점입니다. 긴 상세 조치는 케이스별 문서로 분리하고, 이 파일은 색인과 follow-up 규칙만 유지합니다.

## 문서 구조

- `docs/troubleshooting.md`: 증상 색인, 분류, follow-up 규칙
- `docs/troubleshooting/*.md`: 케이스별 상세 조치
- `docs/troubleshooting/_template.md`: 새 troubleshooting 케이스 작성 템플릿

## 빠른 증상표

| ID | 증상 | Category | Status | 먼저 볼 문서 |
|---|---|---|---|---|
| TS-001 | boot asset이 없다고 실패 | Local development | archived | [`make vm-start`가 boot asset 없음으로 실패](troubleshooting/001_boot-asset-missing.md) |
| TS-002 | VM IP가 `192.168.64.x` | Network | active | [VM IP가 `192.168.64.x`로 보임](troubleshooting/002_vm-shared-nat-ip.md) |
| TS-003 | bridged mode가 `Killed: 9` | Network | archived | [bridged mode가 `Killed: 9`로 종료됨](troubleshooting/003_bridged-mode-killed-9.md) |
| TS-004 | Docker 설치 중 disk full | Guest bootstrap | resolved | [`docker.io` 설치 중 `No space left on device`](troubleshooting/004_docker-install-disk-full.md) |
| TS-005 | apt Release file 시간 오류 | Guest bootstrap | archived | [golden rootfs 준비 중 `apt-get update`가 Release file 시간 오류로 실패](troubleshooting/005_apt-release-file-time-error.md) |
| TS-006 | cloud-init이 다시 안 돎 | Guest bootstrap | active | [cloud-init이 bootstrap을 다시 실행하지 않음](troubleshooting/006_cloud-init-not-rerun.md) |
| TS-007 | nginx `502 Bad Gateway` | Runtime health | active | [nginx가 `502 Bad Gateway`를 반환](troubleshooting/007_nginx-502-bad-gateway.md) |
| TS-008 | watchdog이 `host-proxy-http-502`를 표시 | Host proxy | active | [watchdog이 host proxy 502를 복구하지 못함](troubleshooting/008_watchdog-host-proxy-502.md) |
| TS-009 | Redis가 `exec format error`로 재시작됨 | Guest containers | resolved | [Redis가 `exec format error`를 출력함](troubleshooting/009_redis-exec-format-error.md) |
| TS-010 | Redis UI가 template fetch 오류를 표시 | Guest containers | resolved | [Redis UI가 `failed to fetch html template`을 표시](troubleshooting/010_redis-ui-template-fetch-error.md) |
| TS-011 | Service health가 302를 Reachable로 표시 | Runtime health | resolved | [HTTP 302가 Reachable로 표시됨](troubleshooting/011_http-302-reachable.md) |
| TS-012 | bundle update가 오래 멈춘 것처럼 보임 | Update | active | [bundle update가 health wait 또는 rollback에서 오래 멈춤](troubleshooting/012_bundle-update-health-wait-rollback-stall.md) |
| TS-013 | update 후 VM disk/ext4 오류 | Update | resolved | [update 후 VM disk가 ext4 오류 또는 read-only 상태가 됨](troubleshooting/013_update-vm-disk-ext4-readonly.md) |
| TS-014 | update 후 Redis가 `exec format error` | Update | resolved | [update 후 Redis가 `exec format error`로 실패](troubleshooting/014_update-redis-exec-format-error.md) |
| TS-015 | update 후 bootstrap이 `missing runtime package`로 실패 | Update | active | [update 후 bootstrap이 `missing runtime package`로 실패](troubleshooting/015_update-missing-runtime-package.md) |
| TS-016 | Redis가 AOF 오류로 재시작 반복 | Data store | active | [Redis AOF 손상으로 runtime health가 회복되지 않음](troubleshooting/016_redis-aof-corruption.md) |
| TS-017 | VM IP가 계속 `Waiting` | Runtime health | active | [VM은 부팅됐지만 VM IP가 계속 Waiting](troubleshooting/017_vm-ip-waiting-bootstrap.md) |
| TS-018 | pkg 설치 후 Helper app이 안 보임 | Packaging | resolved | [pkg 설치 후 `/Applications`에 Helper app이 없음](troubleshooting/018_pkg-helper-app-missing.md) |
| TS-019 | Helper app이 없어 GUI 삭제가 안 됨 | Uninstall | active | [Helper app 없이 설치물을 제거해야 함](troubleshooting/019_uninstall-without-helper-app.md) |
| TS-020 | app container health가 오래 starting | Guest containers | active | [app container가 오래 `health: starting` 상태](troubleshooting/020_app-container-health-starting.md) |
| TS-021 | Ubuntu arm64 `flash-kernel` 실패 | Guest bootstrap | resolved | [Ubuntu arm64 cloud image에서 `flash-kernel`이 실패](troubleshooting/021_ubuntu-flash-kernel-failure.md) |
| TS-022 | 설치된 runtime binary에 virtualization entitlement가 없음 | Packaging | resolved | [설치된 runtime binary에 virtualization entitlement가 없음](troubleshooting/022_missing-virtualization-entitlement.md) |
| TS-023 | stale pid file | Local development | archived | [`make vm-status`가 stale pid file을 표시](troubleshooting/023_stale-pid-file.md) |
| TS-024 | pkg 설치가 `Running package scripts...`에서 실패 | Packaging | active | [pkg 설치가 `Running package scripts...`에서 실패함](troubleshooting/024_pkg-postinstall-timeout.md) |
| TS-025 | update 후 VM disk attachment invalid | Update | active | [update 후 VM disk attachment가 invalid로 실패](troubleshooting/025_update-vm-disk-attachment-race.md) |
| TS-026 | PWA가 Runtime Control API unreachable 표시 | Runtime Control PWA | active | [PWA가 Runtime Control API unreachable을 표시](troubleshooting/026_pwa-runtime-control-api-unreachable.md) |
| TS-027 | update 후 PWA가 이전 JS 사용 | Runtime Control PWA / Update | active | [Update 적용 후 PWA가 이전 JS를 계속 사용](troubleshooting/027_update-stale-pwa-assets.md) |
| TS-028 | host proxy가 `/opt/homebrew/var/...`에 의존 | Host proxy / Packaging | resolved | [Host proxy가 Homebrew nginx runtime directory에 의존함](troubleshooting/028_host-proxy-homebrew-runtime-directory.md) |
| TS-029 | update 중 Host가 Guest shutdown 상태를 추정 | Update | resolved | [Update 중 Host가 Guest shutdown 상태를 추정함](troubleshooting/029_update-guest-shutdown-inference.md) |
| TS-030 | Runtime 상태를 Host/UI가 추정하거나 암묵 보정 | Runtime health / Update | resolved | [Runtime 상태를 Host/UI가 추정하거나 암묵 보정함](troubleshooting/030_runtime-state-inference.md) |

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

- [Troubleshooting reference](troubleshooting/reference.md)
