# Vital Server Helper Release/Dev Documentation Plan

Vital Server Helper 공개와 배포를 위해 작성할 문서 체계입니다.
이 문서는 MkDocs nav에 반영할 release/dev 문서군의 독자, 목적, 작성 순서를
고정합니다.

현재 repository에는 `mkdocs.yml`이 없으므로, 아래의 "MkDocs nav 초안"을
MkDocs 설정 생성 시 기준으로 사용합니다. 기존 문서 지도에서는 이 문서를
작성 계획의 source of truth로 둡니다.

## 독자 구분

| 문서군 | 주 독자 | 문서의 역할 |
|---|---|---|
| `release/` | 연구 과제 관계자, 병원 IT 담당자, 병원 운영자, 도입 검토자 | 공개 배포 대상 서비스가 무엇을 제공하고 병원 현장에서 어떻게 설치/운영되는지 설명 |
| `dev/` | repository 개발자, packaging/release 담당자, runtime/API/testkit 유지보수자 | 서비스 경계, package 책임, Health Check 계약, build/release/test 절차 설명 |

release 문서는 내부 구현을 설명하지 않습니다. 사용자가 필요한 설치, 운영, 장애
확인, 지원 모드만 다룹니다.

dev 문서는 외부 홍보 문구를 반복하지 않습니다. 구현 책임, 상태 계약, 실패 의미,
검증 방법, MkDocs/packaging 반영 기준을 다룹니다.

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
| Mac 기반 서비스 포팅 이유: 저전력, 안정성, 저렴함, 장기간 서비스 | `release/macos-porting.md`, `dev/architecture.md` |
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

| 문서 | 독자 | 목적 | 포함 범위 |
|---|---|---|---|
| `release/index.md` | 전체 공개 독자 | Vital Server Helper 공개 문서의 첫 화면 | 서비스 한 줄 설명, 제공 범위, 병원 내 기본 지원, cloud 선택 지원, 다음 문서 안내 |
| `release/background.md` | 연구 과제 관계자, 도입 검토자 | K-MFDB 구축 맥락과 Vital Server Helper 공개 취지 설명 | 저출산 극복 기술개발 중점연구 맥락, VitalDB 기반 병원 데이터 운영 필요성, 공개/배포 목적 |
| `release/macos-porting.md` | 도입 검토자, 병원 IT 담당자 | Mac 기반 포팅 이유 설명 | 저전력, 안정성, 낮은 도입/운영 비용, 장기간 상시 서비스, Mac mini/Mac Studio 운영 전제 |
| `release/health-check-service.md` | 병원 운영자, 병원 IT 담당자 | Vital Server Helper의 Health Check 서비스가 무엇을 확인하는지 설명 | VR/VRecorder 동작 유무, `.vital` 파일 sanity check, 서비스 상태, 결과 상태의 의미, 확장 가능성 |
| `release/deployment-modes.md` | 병원 IT 담당자, 보안 담당자 | 병원 내/외 사용 모드 구분 | 병원 내 기본 모드, outbound 허용 시 cloud 연계 모드, network/security 전제 |
| `release/installation.md` | 현장 설치 담당자 | 설치와 초기 확인 절차 안내 | DMG/PKG 설치, 초기 설정, Health Check 확인, 기본 URL, offline 설치 전제 |
| `release/operation.md` | 병원 운영자 | 일상 운영 방법 안내 | Helper app Status/Logs/Update 확인, health result 확인, update bundle 적용 |
| `release/troubleshooting.md` | 병원 IT 담당자 | 현장 장애 대응 안내 | 증상, 원인, 확인 방법, 조치 방향, 예방 원칙 |
| `release/release-notes.md` | 전체 공개 독자 | 배포 버전별 변경 사항 안내 | release version, 변경된 서비스 범위, 알려진 제한, 업그레이드 주의사항 |

## Dev 문서군

dev 문서군은 repository 유지보수자가 release 문서를 실제 구현과 연결할 수 있게
합니다.

| 문서 | 독자 | 목적 | 포함 범위 |
|---|---|---|---|
| `dev/index.md` | 개발자 전체 | 내부 문서군 진입점 | service catalog, architecture, build/release/test 문서 안내 |
| `dev/service-catalog.md` | 신규 개발자, reviewer | repository 안의 서비스 목록과 책임 설명 | `apps/vitalserver`, `apps/vitalserver-macos-runtime`, `apps/vitalserver-runtime-pwa`, `apps/vitaldb-observer`, `apps/vitalserver-audit-proxy`, `packages/*` |
| `dev/package-map.md` | 개발자, release 담당자 | monorepo package 경계 설명 | app/package/infra/docs 경계, package별 owner, 외부 공개 여부 |
| `dev/architecture.md` | runtime/API 개발자 | release 모드가 실제 구조에 어떻게 대응되는지 설명 | Host/Guest, macOS host proxy, Linux VM, Runtime Control API, observer/testkit 관계 |
| `dev/health-check-contract.md` | Health Check 구현자 | Health Check 상태 계약 고정 | VR observed/missing/stale/read-failed, `.vital` file found/invalid/decode-failed/permission-failed, empty vs missing 구분 |
| `dev/api-contracts.md` | API/PWA/testkit 개발자 | 공개/내부 API 문서 위치 안내 | Runtime Control API, VitalDB Observer API, Audit Proxy API, OpenAPI source |
| `dev/build-and-release.md` | release 담당자 | 배포 artifact 생성 절차 설명 | `make vm-dmg-release`, `make vm-update-bundle-release`, `make install-testkit-release`, artifact 위치 |
| `dev/testing.md` | 개발자, QA | 검증 절차 설명 | unit/integration test, testkit smoke/load, runtime chaos, Health Check 시나리오 |
| `dev/troubleshooting.md` | 개발자, 운영 지원자 | 내부 장애 조사 기준 | 기존 `docs/troubleshooting.md`와 케이스 문서 연결, failure pattern 기록 규칙 |

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

## MkDocs nav 초안

```yaml
site_name: Tirosh VitalServer

nav:
  - Home: index.md
  - Release:
      - Overview: release/index.md
      - Research Background: release/background.md
      - Why macOS Runtime: release/macos-porting.md
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
  - Existing Docs:
      - Current Documentation Map: index.md
      - Productization Strategy: vitalserver-productization.md
      - Vital Recorder: vrecorder.md
      - Testkit Usage: testkit-usage.md
      - Runtime:
          - macOS Runtime: vitalserver-macos-runtime.md
          - Runtime Overview: macos-runtime/overview.md
          - Runtime Architecture: macos-runtime/architecture.md
          - Runtime Control API: macos-runtime/runtime-control-api.md
```

## 작성 우선순위

1. `release/index.md`
2. `release/health-check-service.md`
3. `release/deployment-modes.md`
4. `release/macos-porting.md`
5. `dev/service-catalog.md`
6. `dev/health-check-contract.md`
7. `dev/build-and-release.md`
8. `release/installation.md`
9. `release/operation.md`
10. `dev/testing.md`

이 순서는 공개 배포 요구사항을 먼저 닫고, 그 다음 release 문서를 구현 계약과
빌드/검증 절차에 연결하기 위한 순서입니다.

## 작성 완료 기준

release 문서군은 아래 기준을 만족해야 합니다.

- 공개 독자가 내부 package 이름을 몰라도 Vital Server Helper의 목적과 사용 모드를
  이해할 수 있다.
- 병원 내 기본 모드와 cloud 선택 지원 모드가 명확히 구분된다.
- Vital Server Helper Health Check 결과에서 missing, invalid, failed, stale,
  empty가 같은 의미로 섞이지 않는다.
- Mac 기반 포팅 이유가 저전력, 안정성, 비용, 장기간 서비스 관점으로 설명된다.

dev 문서군은 아래 기준을 만족해야 합니다.

- 각 app/package가 어떤 state를 소유하거나 소비하는지 구분된다.
- Health Check 계약이 Host/Guest/runtime/observer/testkit 책임 경계를 넘지 않는다.
- `.vital` sanity check 실패가 empty success로 변환되지 않는다는 원칙을 문서화한다.
- build, release, test 명령이 현재 repository의 Make target과 package 경계에 맞는다.
