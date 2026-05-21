# VitalServer Helper

`apps/vitalserver-vm-launcher`는 Mac mini/Mac Studio에 VitalServer 전용 runtime을 설치하고 운영하기 위한 macOS app, Swift runtime orchestrator, guest VM asset, packaging 도구를 담고 있습니다.

제품 사용자는 `/Applications/VitalServer Helper.app`을 통해 상태 확인, 설정 변경, offline update bundle 적용, 로그 조회, rollback, uninstall을 수행합니다. 개발자는 아래 Make target으로 설치물과 update bundle을 만듭니다.

```text
Browser / VRecorder
  -> target Mac LAN IP :80
      -> macOS host proxy
          -> Linux VM shared/NAT IP :80
              -> Docker Compose
                  - VitalServer
                  - Redis
                  - Redis UI
                  - Swagger UI
```

기본 네트워크 구조는 `shared/NAT VM + macOS host proxy`입니다. bridged mode는 Apple restricted entitlement 승인이 필요한 향후 옵션이며, 현재 사용자 UI에서는 선택하지 않습니다.

## Helper app 탭

| 탭 | 사용 목적 |
|---|---|
| Status | VitalServer URL, data directory, 전체 health와 주요 서비스 상태 확인 |
| Settings | CPU, memory, disk 증가, shared/NAT network, vital files directory, start-on-boot 같은 운영 설정 |
| Update | offline/online 공통 update bundle 검증과 적용 |
| Logs | Helper, install, command, VM/container log를 필터링해 확인 |
| About | Helper, VitalServer, container image, runtime version 확인 |
| Advanced | 네트워크 override, service diagnostics, admin password reset, recovery operation |
| Danger Zone | uninstall, clean uninstall, 향후 VM/rootfs 교체처럼 파괴적인 작업 |

## 먼저 볼 것

| 상황 | 실행/확인 |
|---|---|
| 제품 설치 파일을 만들고 싶다 | `make vm-dmg` |
| `.pkg`만 만들고 싶다 | `make vm-pkg` |
| air-gapped 현장 업데이트 bundle을 만들고 싶다 | `make vm-update-bundle` |
| 만든 update bundle을 검증하고 싶다 | `make vm-update-bundle-verify` |
| 개발용 package를 현재 Mac에 설치해 보고 싶다 | `make vm-pkg-install` |
| 설치된 runtime 상태를 확인하고 싶다 | `make vm-installed-health` |
| 개발용 설치물을 지우고 싶다 | `make vm-pkg-uninstall-dev` |
| VM을 직접 띄워 PoC를 확인하고 싶다 | `make vm-up` |

세부 문서는 [VM Launcher Overview](../../docs/vm-launcher/overview.md)를 진입점으로 봅니다.

## 사용자 시나리오

### 1. 신규 현장에 설치 파일 제공

완전한 air-gapped 설치물을 만들려면 DMG를 생성합니다.

```sh
make vm-dmg
```

생성물:

```text
dist/TiroshVitalServer-<version>.dmg
```

DMG 안에는 단일 installer package가 들어갑니다.

```text
Install Tirosh VitalServer.pkg
```

이 package는 Helper app, Swift runtime CLI, host proxy, Linux VM runtime asset, golden rootfs, Docker image bundle, LaunchDaemon을 설치합니다. target Mac은 설치 시점에 인터넷이 없어도 됩니다.

package에 들어가는 golden rootfs base는 설치 파일 효율을 위해 기본 4 GiB로 만듭니다. 실제 설치된 VM disk는 wizard 기본값 32 GiB로 확장되며, 설치 후에는 증가만 허용합니다.

반복 개발 중에는 cache를 재사용합니다. release 검증처럼 clean golden rootfs부터 다시 만들려면:

```sh
make vm-dmg-release
```

### 2. 이미 설치된 현장에 offline update bundle 제공

업데이트 입력 단위는 bundle directory입니다.

```sh
make vm-update-bundle
make vm-update-bundle-verify
```

생성 위치:

```text
dist/update-bundles/update-bundle-<version>/
```

USB나 폐쇄망 파일 서버로 전달하려면 directory를 압축해서 옮깁니다.

```sh
cd dist/update-bundles
tar -czf update-bundle-<version>.tar.gz update-bundle-<version>
```

현장에서는 Helper app의 Update 탭에서 bundle directory를 선택하거나, CLI로 검증/적용합니다.

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle /path/to/update-bundle-<version>
sudo /usr/local/bin/vitalserver-vm runtime apply-bundle /path/to/update-bundle-<version>
```

`apply-bundle`은 mutable `vm-disk.img`를 보존하고 replaceable artifact만 교체합니다. 적용 전 backup을 만들고 health check 실패 시 rollback합니다.

update bundle 생성 시에도 artifact 압축은 필요합니다. 기본 bundle은 Helper app, runtime tools, host nginx bundle, guest deploy bundle을 각각 `.tar.gz`로 묶습니다. 이 압축은 rootfs 전체를 매번 다시 만드는 것보다 훨씬 가볍습니다.

`rootfs-base.raw.gz`는 신규 설치나 큰 runtime 변경용 artifact입니다. 기본 update bundle target은 호환성을 위해 이 파일을 만들 수 있지만, 이미 설치된 현장의 mutable `vm-disk.img`를 자동 교체하지 않습니다. 실제 현장 업데이트의 핵심은 `app-bundle`, `runtime-tools`, `nginx-bundle`, `guest-deploy`, 기본 migration입니다.

`guest-deploy`에 들어간 `bootstrap.sh`, compose, guest systemd, Docker image bundle 수정은 update bundle에 포함됩니다. 적용 시 기본 migration이 cloud-init seed를 갱신하고, 새 runtime은 guest activation request를 통해 VM 내부에서 Docker image load와 compose recreate를 수행합니다.

### 3. 개발 Mac에 package 설치 테스트

```sh
make vm-pkg
make vm-pkg-install
make vm-installed-health
```

설치 후 `/Applications/VitalServer Helper.app`을 열어 상태를 확인합니다. VitalServer 접속 URL은 Helper app Status 탭의 `VitalServer URL`을 사용합니다.

개발용 설치물을 지울 때:

```sh
make vm-pkg-uninstall-dev
```

Helper app이 열리지 않는 깨진 설치 상태에서는 아래 fallback을 사용합니다.

```sh
sudo /usr/local/bin/tirosh-vitalserver-uninstall
```

### 4. VM과 proxy를 빠르게 PoC로 확인

package 설치 없이 개발 VM을 직접 띄웁니다.

```sh
make vm-up
make vm-health
make vm-down
```

`make vm-up`은 Linux boot asset 준비, cloud-init 생성, guest deploy bundle staging, VM background start, VM IP 대기, host proxy 연결까지 수행합니다.

VM 콘솔을 직접 보고 싶으면:

```sh
make vm-prepare
make vm-start
```

### 5. 패키징 시간이 너무 오래 걸릴 때

rootfs gzip 압축은 시간이 오래 걸릴 수 있습니다. build machine에 `pigz`가 있으면 병렬 gzip을 사용합니다.

```sh
command -v pigz
brew install pigz
VM_COMPRESSION_THREADS=8 make vm-pkg
```

`pigz`는 build machine 전용 optional accelerator입니다. 최종 `.pkg`, `.dmg`, air-gapped target Mac에는 필요하지 않습니다. `pigz`가 없으면 Python gzip fallback을 사용합니다.

## 버전 관리

VM launcher/package/update bundle 버전은 아래 파일을 기준으로 관리합니다.

```text
apps/vitalserver-vm-launcher/VERSION
```

`make vm-build`, `make vm-pkg`, `make vm-update-bundle`은 이 값을 읽어 Swift runtime version, app bundle version, package version, update bundle version에 반영합니다. 버전을 올릴 때는 이 파일만 수정합니다.

## 주요 명령

| 명령 | 용도 |
|---|---|
| `make vm-app` | Helper app bundle 생성 |
| `make vm-pkg` | 개발 검증용 `.pkg` 생성 |
| `make vm-dmg` | 전달용 `.dmg` 생성 |
| `make vm-pkg-release` | clean golden rootfs로 `.pkg` 재생성 |
| `make vm-dmg-release` | clean golden rootfs로 `.dmg` 재생성 |
| `make vm-update-bundle` | offline/online 공통 update bundle 생성 |
| `make vm-update-bundle-verify` | update bundle checksum/manifest 검증 |
| `make vm-pkg-install` | 현재 Mac에 개발용 package 설치 |
| `make vm-installed-health` | 설치된 launchd VM/proxy 상태 확인 |
| `make vm-pkg-uninstall-dev` | 개발용 설치물 제거 |
| `make vm-up` | 개발 VM start + host proxy 연결 |
| `make vm-health` | 개발 VM health 확인 |
| `make vm-down` | 개발 VM 종료 |

## 설치되는 항목

| 항목 | 위치 |
|---|---|
| Helper app | `/Applications/VitalServer Helper.app` |
| runtime CLI | `/usr/local/bin/vitalserver-vm` |
| host proxy runner | `/usr/local/bin/vitalserver-proxy-run` |
| uninstaller | `/usr/local/bin/tirosh-vitalserver-uninstall` |
| runtime home | `/Library/Application Support/TiroshVitalServer/` |
| status file | `/Library/Application Support/TiroshVitalServer/status/runtime-status.json` |
| logs | `/Library/Application Support/TiroshVitalServer/logs/` |
| LaunchDaemons | `/Library/LaunchDaemons/com.tirosh.vitalserver-*.plist` |

## 책임 경계

| 영역 | 책임 |
|---|---|
| Make | target orchestration, artifact path, developer wrapper |
| Python `packages/vm-build` | Ubuntu asset, golden rootfs, nginx bundle, Docker image bundle, update bundle 생성/검증 |
| Swift `RuntimeOrchestrator` | VM lifecycle, runtime install/configure/health/watchdog/update/rollback |
| Swift `ManagerApp` | Helper app UI |
| Packaging shell | `postinstall`, `proxy-run`, uninstall entrypoint |
| Guest support | cloud-init 이후 Docker Compose bootstrap, guest state 기록, diagnostics |

## 문서

| 문서 | 볼 때 |
|---|---|
| [VM Launcher Overview](../../docs/vm-launcher/overview.md) | 문서군 전체 지도와 시나리오 |
| [Architecture](../../docs/vm-launcher/architecture.md) | 구조와 책임 경계 |
| [Packaging and Update](../../docs/vm-launcher/packaging.md) | PKG/DMG/update bundle 계약 |
| [Runtime](../../docs/vm-launcher/runtime.md) | VM boot, cloud-init, guest bootstrap, network/identity |
| [Troubleshooting](../../docs/vm-launcher/troubleshooting.md) | 502, stale pid, disk full, install cleanup 등 |
| [macOS host proxy ADR](../../docs/adr/0001-macos-host-proxy-for-vrecorder-ip.md) | host proxy가 필요한 이유 |
