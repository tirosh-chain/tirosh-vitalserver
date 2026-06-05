# Vital Server Helper Release/Dev Documentation Plan

Vital Server Helper 공개와 배포를 위해 작성할 문서 체계입니다.
이 문서는 MkDocs nav에 반영할 release/dev 문서군의 독자, 목적, 작성 순서를
고정합니다.

현재 repository의 `mkdocs.yml`은 `site-docs/` 아래 release/dev 문서군을 GitHub Pages
site nav에 반영합니다. 기존 `docs/` 문서 지도에서는 이 문서를 공개 release/dev 문서
작성 기준의 source of truth로 둡니다.

## 독자 구분

| 문서군 | 주 독자 | 문서의 역할 |
|---|---|---|
| `site-docs/release/` | 연구 과제 관계자, 병원 IT 담당자, 병원 운영자, 도입 검토자 | 공개 배포 대상 서비스가 무엇을 제공하고 병원 현장에서 어떻게 설치/운영되는지 설명 |
| `site-docs/dev/` | 오픈소스 contributor, repository 개발자, packaging/release 담당자, runtime/API/testkit 유지보수자 | 서비스 경계, package 책임, Health Check 계약, build/release/test 절차 설명 |

release 문서는 내부 구현을 설명하지 않습니다. 사용자가 필요한 설치, 운영, 장애
확인, 지원 모드만 다룹니다.

dev 문서는 외부 홍보 문구를 반복하지 않습니다. 오픈소스 repository를 이해하고
기여하기 위한 구현 책임, 상태 계약, 실패 의미, 검증 방법, MkDocs/packaging 반영
기준을 다룹니다.

## 명명 기준

공개 문서의 최상위 서비스명은 `Vital Server Helper`입니다.

Health Check는 별도 제품명이 아니라 `Vital Server Helper`가 제공하는 서비스/기능으로
문서화합니다. 따라서 release 문서에서는 `Vital Server Helper Health Check` 또는
`Vital Server Helper의 Health Check 서비스`처럼 표기합니다.

repository 내부 문서와 코드에서 이미 쓰는 `VitalServer Helper` 표기는 package/app
이름이나 기존 내부 component를 가리킬 때 유지합니다.

## 요구사항 대응

| 요구사항 | 담당 문서 |
|---|---|
| K-MFDB 구축 관련 Vital Server Helper 공개/배포 취지 설명 | `release/background.md`, `release/index.md` |
| Mac 하드웨어 기반 appliance 선택 이유 | `release/mac-hardware-appliance.md`, `dev/architecture.md` |
| Vital Server Helper가 제공하는 VR 동작 유무 확인 | `release/health-check-service.md`, `dev/health-check-contract.md` |
| Vital Server Helper가 제공하는 저장 데이터 sanity check | `release/health-check-service.md`, `dev/health-check-contract.md` |
| 병원 내 사용 모드 기본 지원 | `release/deployment-modes.md`, `release/installation.md` |
| 병원 외 cloud 사용 모드 선택 지원 | `release/deployment-modes.md`, `dev/architecture.md` |
| repository package 안의 서비스 소개 | `dev/service-catalog.md`, `dev/package-map.md` |
| release와 dev 설명 분리 | `release/index.md`, `dev/index.md` |

저장 파일 확장자는 이 repository의 testkit domain policy와 기존 문서 기준
`.vital`로 문서화합니다. 요구 원문에 있는 `*.vatal` 표기는 release 문서에는
사용하지 않습니다.

## Release 문서군

release 문서군은 외부 공개와 현장 배포에 필요한 설명만 담습니다.

| 문서 | 독자 | 목적 |
|---|---|---|
| `release/index.md` | 전체 공개 독자 | Vital Server Helper 공개 문서의 첫 화면 |
| `release/background.md` | 연구 과제 관계자, 도입 검토자 | K-MFDB 구축 맥락과 Vital Server Helper 공개 취지 설명 |
| `release/mac-hardware-appliance.md` | 도입 검토자, 병원 IT 담당자 | Mac 하드웨어 기반 appliance 선택 이유 설명 |
| `release/health-check-service.md` | 병원 운영자, 병원 IT 담당자 | Vital Server Helper의 Health Check 서비스 설명 |
| `release/deployment-modes.md` | 병원 IT 담당자, 보안 담당자 | 병원 내/외 사용 모드 구분 |
| `release/installation.md` | 현장 설치 담당자 | 설치와 초기 확인 절차 안내 |
| `release/operation.md` | 병원 운영자 | 일상 운영 방법 안내 |
| `release/troubleshooting.md` | 병원 IT 담당자 | 현장 장애 대응 안내 |
| `release/release-notes.md` | 전체 공개 독자 | 배포 버전별 변경 사항 안내 |

### Release 작성 기준

`release/index.md`는 서비스 한 줄 설명, 제공 범위, 병원 내 기본 지원, cloud 선택
지원, 다음 문서 안내를 포함합니다.

`release/background.md`는 저출산 극복 기술개발 중점연구, K-MFDB 구축 맥락,
VitalDB 기반 병원 데이터 운영 필요성, 공개/배포 목적을 설명합니다.

`release/mac-hardware-appliance.md`는 Mac 하드웨어를 선택한 이유를 주 메시지로
둡니다. OS, Linux VM, PWA 세부 구조는 dev 문서로 보냅니다.

`release/health-check-service.md`는 VR/VRecorder 동작 유무, `.vital` 파일 sanity
check, 서비스 상태, 결과 상태의 의미, 향후 확장 가능성을 설명합니다.

`release/deployment-modes.md`는 병원 내 기본 모드와 병원 outbound 허용 시 cloud
연계 모드를 구분합니다. 네트워크와 보안 전제는 운영자가 판단할 수 있을 정도로
설명하고, 구현 상세는 dev 문서로 연결합니다.

`release/installation.md`는 DMG/PKG 설치, 초기 설정, Health Check 확인, 기본 URL,
offline 설치 전제를 다룹니다.

`release/operation.md`는 Helper app Status/Logs/Update 확인, health result 확인,
update bundle 적용을 다룹니다.

`release/troubleshooting.md`는 증상, 원인, 확인 방법, 조치 방향, 예방 원칙을
같이 적습니다.

## Mac 하드웨어 메시지 기준

`release/mac-hardware-appliance.md`의 핵심 주장은 아래처럼 둡니다.

> Vital Server Helper는 병원 내부망에서 장기간 켜져 있는 현장 appliance를
> 목표로 한다. Mac을 선택한 주된 이유는 macOS가 아니라 Mac mini/Mac Studio
> 하드웨어의 QA 일관성, 표준화, 장기 호환성이다. 일반 Linux/Windows PC는
> 제조사와 부품 조합이 다양해 현장별 검증 범위가 커지지만, Mac 기반 표준
> 장비는 설치, 검증, 교체, 장애 대응 절차를 좁힐 수 있다.

| 메시지 | 설명 방향 |
|---|---|
| 하드웨어 QA 일관성 | Apple이 설계, 제조, 펌웨어, 전원, 열, 부품 조합을 통합 관리하므로 현장 장비 편차와 하드웨어 품질 리스크를 줄일 수 있다는 점을 설명 |
| 표준화된 하드웨어 SKU | 일반 Linux/Windows PC가 나쁘다는 주장이 아니라, 제조사, 메인보드, BIOS/UEFI, 전원부, 네트워크 칩셋 조합이 다양해 검증 matrix가 커진다는 점을 설명 |
| 검증 범위 축소 | Mac mini/Mac Studio 계열로 배포 target을 제한하면 설치, runtime, networking, update, replacement 절차를 같은 하드웨어 기준으로 반복 검증할 수 있다는 점을 설명 |
| 24/7 소형 appliance 운용성 | 24시간 상시 운영이 가능한 일반 PC는 대개 rack/server class로 올라가지만, Mac mini/Mac Studio는 mini PC 크기로 병원 내부망 옆에 배치 가능한 appliance가 된다는 점을 설명 |
| 장기 제품 호환성 | 동일 계열 제품의 호환성과 지원 기간이 길어 현장 설치물, packaging, runtime 검증 결과를 오래 유지할 수 있다는 점을 설명. 단, 무기한 지원처럼 표현하지 않는다 |
| 낮은 운영 부담 | 서버랙, 별도 전산실, 복잡한 하드웨어 조달 없이 표준 장비 교체와 재설치 절차를 단순화할 수 있다는 점을 설명 |
| 저전력 장기 운영 | Apple Silicon 기반 Mac mini/Mac Studio의 전력 대비 성능을 병원 내 24시간 상시 운영 비용 절감 근거로 설명 |
| OS의 부수적 역할 | macOS 자체가 주된 선택 이유가 아니며, 하드웨어 appliance 위에서 host runtime을 제공하는 환경으로만 설명 |

반대 입장이 타당한 지점도 문서 안에서 경계로 남깁니다. 중앙 인프라,
대규모 HA, redundant PSU, ECC memory, hot-swap storage, IPMI/iDRAC class 원격
관리, rack mounting, server vendor SLA가 핵심 요구라면 전통적인 server 또는
industrial PC가 더 적합할 수 있습니다. Vital Server Helper의 Mac 선택 논리는
그 요구를 부정하지 않고, 병원 내부망 가까이에 둘 표준 소형 현장 appliance라는
범위에서만 주장합니다.

본문 작성 시 참고할 공식 source 후보:

- Mac mini technical specifications: <https://support.apple.com/en-us/121555>
- Mac Studio product/spec overview: <https://www.apple.com/mac-studio/>
- Apple service and parts period after warranty: <https://support.apple.com/en-ca/102772>

## Dev 문서군

dev 문서군은 repository 유지보수자가 release 문서를 실제 구현과 연결할 수 있게
합니다.

| 문서 | 독자 | 목적 |
|---|---|---|
| `dev/index.md` | 개발자 전체 | 내부 문서군 진입점 |
| `dev/service-catalog.md` | 신규 개발자, reviewer | repository 안의 서비스 목록과 책임 설명 |
| `dev/package-map.md` | 개발자, release 담당자 | monorepo package 경계 설명 |
| `dev/architecture.md` | runtime/API 개발자 | release 모드와 실제 구조의 대응 설명 |
| `dev/health-check-contract.md` | Health Check 구현자 | Health Check 상태 계약 고정 |
| `dev/api-contracts.md` | API/PWA/testkit 개발자 | 공개/내부 API 문서 위치 안내 |
| `dev/build-and-release.md` | release 담당자 | 배포 artifact 생성 절차 설명 |
| `dev/testing.md` | 개발자, QA | 검증 절차 설명 |
| `dev/troubleshooting.md` | 개발자, 운영 지원자 | 내부 장애 조사 기준 |

### Dev 작성 기준

`dev/service-catalog.md`는 `apps/vitalserver`, `apps/vitalserver-macos-runtime`,
`apps/vitalserver-runtime-pwa`, `apps/vitaldb-observer`, `apps/vitalserver-audit-proxy`,
`packages/*`의 책임을 설명합니다.

`dev/package-map.md`는 app/package/infra/docs 경계, package별 owner, 외부 공개 여부를
설명합니다.

`dev/architecture.md`는 Mac hardware appliance, Host/Guest, macOS host proxy,
Linux VM, Runtime Control API, PWA, observer/testkit 관계를 설명합니다. OS보다
하드웨어 운영 특성이 Mac 선택의 주된 근거임을 명시하고, server-class 요구에는
전통적인 server/industrial PC가 더 타당할 수 있음을 경계로 둡니다.

`dev/health-check-contract.md`는 VR observed/missing/stale/read-failed, `.vital`
file found/invalid/decode-failed/permission-failed, empty와 missing 구분을
고정합니다.

`dev/api-contracts.md`는 Runtime Control API, VitalDB Observer API, Audit Proxy API,
OpenAPI source 위치를 설명합니다.

`dev/build-and-release.md`는 `make vm-dmg-release`, `make vm-update-bundle-release`,
`make install-testkit-release`, artifact 위치를 설명합니다.

`dev/testing.md`는 unit/integration test, testkit smoke/load, runtime chaos,
Health Check 시나리오를 설명합니다.

`dev/troubleshooting.md`는 기존 `docs/troubleshooting/index.md`와 case 문서를 연결하고,
failure pattern 기록 규칙을 설명합니다.

## Dev Architecture Details

`dev/architecture.md`에는 Linux VM, host platform, PWA 선택 이유를 기술 문서로
정리합니다. 이 내용은 release 문서의 주 메시지가 아니므로 `release/`에서는
간단한 운영 모드 설명으로만 남깁니다.

Linux VM의 핵심 문장:

> Linux VM은 host OS를 Linux로 한정하기 위한 선택이 아니라, macOS/Linux/Windows
> 어디서든 동일한 Vital Server Helper service appliance를 실행하기 위한 guest
> 표준화 계층이다. upstream VitalServer의 Windows 중심 전제는 wrapper와 guest
> service stack에서 흡수하고, host별 차이는 VM provider adapter가 처리한다.

### Upstream Compatibility Evidence

| 근거 | 의미 |
|---|---|
| `vendor/vitalserver/vitalserver-old/server_start.bat` | upstream 실행 스크립트가 Windows batch 기준 |
| `vendor/vitalserver/vitalserver-old/install/*.msi` | Node와 Redis 설치물이 Windows MSI 기준 |
| `vendor/vitalserver/vitalserver-old/service/include/config.js` | 기본 저장 경로가 `Z:/` drive 기준 |
| `apps/vitalserver/docker/Dockerfile` | wrapper가 Linux container 안에 `Z:` symlink를 만들어 upstream path 전제를 흡수 |
| `apps/vitalserver/runtime/node-preload.js` | preload가 Redis host/port, CPU-count assumption, admin password 같은 runtime 전제를 보정 |

### Linux Guest Strengths

| 강점 | 설명 방향 |
|---|---|
| backend service appliance 운영체제 | Linux를 desktop OS가 아니라 VitalServer backend stack을 고정하는 guest runtime으로 설명 |
| container/service 생태계 | Docker/Compose, nginx, Redis, Node service, sidecar, observer, testkit을 같은 guest 기준으로 묶기 쉽다는 점을 설명 |
| headless service 운영 | systemd, journald, timer, log collection, file permission, mount, network namespace 같은 service 운영 모델이 명확하다는 점을 설명 |
| image/update 재현성 | golden rootfs, cloud-init, Docker image bundle, offline update bundle 같은 appliance 배포 모델과 잘 맞는다는 점을 설명 |
| upstream 보정 단일화 | upstream의 Windows path, Windows installer, Redis host, CPU-count assumption 같은 전제를 각 host별로 고치지 않고 Linux guest wrapper/preload에서 흡수한다는 점을 설명 |

### Host Platform Strengths

| Host | 강점 | Runtime 책임 |
|---|---|---|
| macOS | Mac hardware appliance 운영, DMG/PKG, launchd, Apple Virtualization, local Helper app, code signing/notarization | VM lifecycle, host proxy, permission, file picker, update/recovery entrypoint |
| Linux | KVM/QEMU/libvirt, server-friendly networking, systemd, container runtime 접근성 | VM lifecycle, network bridge/NAT, service manager integration, filesystem sharing |
| Windows | 병원/기업 IT의 AD/GPO/Intune/SCCM 친화성, Windows Service, Hyper-V, firewall/endpoint security 정책 연동 | VM lifecycle, Windows Service, firewall/NAT, enterprise management integration |

### PWA Rationale

| 이유 | 설명 방향 |
|---|---|
| cross-platform 운영 UI | macOS/Linux/Windows host마다 native UI를 중복 구현하지 않고 같은 Runtime Control UI를 제공 |
| local/remote control 통합 | local runtime control과 병원 outbound 허용 시 remote/cloud control을 같은 API contract 뒤에 둠 |
| 현장 접근성 | Mac 앞이 아니라 병원 내부 PC, tablet, phone browser에서도 상태와 로그를 확인할 수 있게 함 |
| native shell 책임 축소 | native shell은 설치, 권한, tray/menu, file picker, recovery 같은 host-specific 기능만 맡고 제품 UI는 PWA가 소유 |

## Service Catalog 초안

`dev/service-catalog.md`에는 아래 서비스를 기준으로 정리합니다.

| 서비스/패키지 | 공개 문서 노출 | 책임 |
|---|---|---|
| `apps/vitalserver` | release에서는 "VitalServer service"로 노출 | upstream VitalServer wrapper와 runtime shim |
| `apps/vitalserver-macos-runtime` | release 핵심 노출 | macOS Helper app, host runtime, VM orchestration, packaging |
| `apps/vitalserver-runtime-pwa` | release에서는 "Runtime Control UI"로 제한 노출 | browser/PWA 기반 runtime control surface |
| `apps/vitaldb-observer` | release에서는 Health Check 내부 collector로 간접 노출 | Redis/proxy 기반 VitalDB observation snapshot 생성 |
| `apps/vitalserver-audit-proxy` | release에서는 command audit 기능으로 제한 노출 | VRecorder command/audit event sidecar |
| `packages/vitalserver-testkit` | release에서는 검증 도구로 제한 노출 | simulated recorder, `.vital` upload, smoke/load validation |
| `packages/vitalserver-devtools` | dev 전용 | build machine packaging, VM/update bundle tooling |
| `packages/vitalserver-guest-tools` | dev 전용 | Linux guest-side runtime state, update, logs, repair commands |
| `infra/macos-nginx` | dev 중심, release installation에서 간접 설명 | Mac host proxy config and launchd template |

## MkDocs nav 기준

```yaml
site_name: Vital Server Helper
site_url: https://tirosh-chain.github.io/vitalserver-helper/
docs_dir: site-docs

nav:
  - Home: index.md
  - Release:
      - Overview: release/index.md
      - Research Background: release/background.md
      - Why Mac Hardware: release/mac-hardware-appliance.md
      - Vital Server Helper Health Check: release/health-check-service.md
      - Deployment Modes: release/deployment-modes.md
      - Installation: release/installation.md
      - Operation: release/operation.md
      - Troubleshooting: release/troubleshooting.md
      - Release Notes: release/release-notes.md
  - Dev:
      - Overview: dev/index.md
      - Service Catalog: dev/service-catalog.md
      - Package Map: dev/package-map.md
      - Architecture: dev/architecture.md
      - Health Check Contract: dev/health-check-contract.md
      - API Contracts: dev/api-contracts.md
      - Build and Release: dev/build-and-release.md
      - Testing: dev/testing.md
      - Troubleshooting: dev/troubleshooting.md
```

## 작성 우선순위

1. `release/index.md`
2. `release/health-check-service.md`
3. `release/deployment-modes.md`
4. `release/mac-hardware-appliance.md`
5. `dev/service-catalog.md`
6. `dev/architecture.md`
7. `dev/health-check-contract.md`
8. `dev/build-and-release.md`
9. `release/installation.md`
10. `release/operation.md`
11. `dev/testing.md`

이 순서는 공개 배포 요구사항을 먼저 닫고, 그 다음 release 문서를 구현 계약과
빌드/검증 절차에 연결하기 위한 순서입니다.

## 읽는 순서

Release 독자는 아래 순서로 읽습니다.

1. `release/index.md`
2. `release/background.md`
3. `release/mac-hardware-appliance.md`
4. `release/health-check-service.md`
5. `release/deployment-modes.md`
6. `release/installation.md`
7. `release/operation.md`
8. `release/troubleshooting.md`

Dev 독자는 아래 순서로 읽습니다.

1. `dev/index.md`
2. `dev/service-catalog.md`
3. `dev/package-map.md`
4. `dev/architecture.md`
5. `dev/health-check-contract.md`
6. `dev/api-contracts.md`
7. `dev/build-and-release.md`
8. `dev/testing.md`
9. `dev/troubleshooting.md`

## 작성 완료 기준

release 문서군은 아래 기준을 만족해야 합니다.

- 공개 독자가 내부 package 이름을 몰라도 Vital Server Helper의 목적과 사용 모드를
  이해할 수 있다.
- 병원 내 기본 모드와 cloud 선택 지원 모드가 명확히 구분된다.
- Vital Server Helper Health Check 결과에서 missing, invalid, failed, stale,
  empty가 같은 의미로 섞이지 않는다.
- Mac 기반 선택 이유가 OS 중심이 아니라 Apple 하드웨어의 QA 일관성, 표준화,
  검증 범위 축소, 24/7 소형 appliance 운용성, 장기 제품 호환성 중심으로
  설명된다.
- 전통적인 server/industrial PC가 더 타당한 요구 조건을 인정하고, Mac 선택
  논리를 병원 내부망 표준 소형 appliance 범위로 제한한다.
- Linux VM, host별 VM provider, PWA 선택 이유 같은 구현 구조는 release 문서의
  주 메시지로 올리지 않고 dev 문서로 연결한다.

dev 문서군은 아래 기준을 만족해야 합니다.

- 각 app/package가 어떤 state를 소유하거나 소비하는지 구분된다.
- Linux VM이 upstream Linux compatibility 때문이 아니라 Windows-oriented upstream을
  제품용 Linux guest service stack으로 정규화하기 위한 계층임을 설명한다.
- Linux guest의 service runtime 강점과 macOS/Linux/Windows host platform별 software
  강점과 책임을 구분한다.
- PWA가 host별 native UI 중복을 피하고 local/remote Runtime Control UI를 통합하기
  위한 primary UI임을 설명한다.
- Health Check 계약이 Host/Guest/runtime/observer/testkit 책임 경계를 넘지 않는다.
- `.vital` sanity check 실패가 empty success로 변환되지 않는다는 원칙을 문서화한다.
- build, release, test 명령이 현재 repository의 Make target과 package 경계에 맞는다.
