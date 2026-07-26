# tirosh-vitalserver

VitalServer Helper monorepo입니다. VitalDB VitalServer를 공식 upstream
`vitaldb/vitalserver` submodule로 고정하고, macOS Helper app, Runtime Control API,
Remote Console PWA, 관측 sidecar, packaging/update 도구, 검증 도구를 함께 관리합니다.

자세한 설치, 사용, 운영, 장애 대응 문서는 공개 문서 site를 기준으로 봅니다.

<https://tirosh-chain.github.io/vitalserver-helper/>

## 1. Repository

이 README는 GitHub에서 repository에 접근한 사람이 빠르게 방향을 잡기 위한 진입점입니다.
세부 사용법과 운영 절차는 README에 반복하지 않고 문서 site에서 관리합니다.

### 1-1. Documentation

| 찾는 내용 | 위치 |
|---|---|
| 설치, 사용, 현장 검증 | [Release docs](https://tirosh-chain.github.io/vitalserver-helper/release/) |
| 버전별 기능과 호환성 | [`CHANGELOG.md`](CHANGELOG.md) |
| 구조, contract, package, 검증 기준 | [Dev docs](https://tirosh-chain.github.io/vitalserver-helper/dev/) |
| repository 내부 책임 지도 | [Repository Map](https://tirosh-chain.github.io/vitalserver-helper/dev/repository-map/) |
| 문서 source | [`site-docs/`](site-docs/) |
| 상세 설계, ADR, troubleshooting source | [`docs/`](docs/) |

### 1-2. Boundaries

- 제품 사용의 중심 표면은 macOS Swift Helper app입니다.
- Host runtime은 VM lifecycle, host proxy, native shell, install/update, recovery orchestration을 소유합니다.
- Guest/Container runtime은 product service control, operation state, Lab API, Postgres-backed read model을 소유합니다.
- Swift Helper app과 Remote Console PWA는 Runtime Control API와 Guest/Product API 기반 상태 계약을 소비합니다.
- VitalServer core 변경은 최소화하고, 운영 보강은 sidecar, observer, Host runtime 계층에서 다룹니다.
- repository root Compose는 개발/검증 sandbox입니다. 설치 runtime의 product service stack은 Linux Guest 안에서 Guest Control API가 제어합니다.
- missing, invalid, failed, stale, empty state는 서로 다른 의미로 유지합니다.

## 2. Development

### 2-1. Start

빠른 실행은 upstream VitalServer와 sidecar를 Compose sandbox로 띄워 local 개발과 검증을
시작하는 경로입니다.

```sh
git clone --recurse-submodules https://github.com/tirosh-chain/tirosh-vitalserver.git
cd tirosh-vitalserver
make dev/bootstrap
make dev/doctor
make help
```

필요한 도구는 작업 범위에 따라 달라집니다. 전체 개발과 packaging을 다룰 때는 Git,
submodule, uv, Python, Node.js/npm, Xcode/Swift toolchain, Docker Compose, nginx가 필요합니다.

### 2-2. Commands

```sh
make help                 # command index
make dev/bootstrap        # submodule, .env, local proxy config 준비
make dev/doctor           # local 개발 환경 점검

make dist/pkg/dev         # development pkg build
make dist/dmg/dev         # standard field-delivery DMG gate
make dist/dmg/dev/cached  # source-contract/receipt-matched local DMG packaging only
make dist/dmg/dev/compile # clean dev DMG compile; verified APT seed may be reused
make dist/dmg/dev/verify  # verify an existing DMG and golden rootfs; never compile
make dist/update/dev      # development product update bundle build

make runtime/up           # local macOS VM runtime과 host proxy 실행
make runtime/health       # local runtime health 확인

make pwa/check            # Runtime Control PWA typecheck
make testkit/smoke        # bounded dev verification smoke scenario

make docs/serve           # MkDocs site local preview
make docs/build           # MkDocs site build
```

더 자세한 target은 `make help/{dev,dist,runtime,pwa,docs,compose,devtools}`로 확인합니다.

#### DMG 명령 구분

| 명령 | 언제 사용 | rootfs 동작 | 보장 범위 |
|---|---|---|---|
| `make dist/dmg/dev` | 개발 DMG를 현장 전달하기 전 | mutable disk를 새로 만들고 clean compile. 유효한 APT-prepared seed는 재사용 | review, compile, artifact verify, golden runtime smoke를 모두 수행하는 dev 현장 전달 gate |
| `make dist/dmg/dev/cached` | 코드 수정 후 로컬 DMG를 가장 빨리 다시 만들 때 | 현재 전체 source fingerprint와 receipt가 일치하면 완성된 golden rootfs를 그대로 재사용 | packaging만 수행. review와 artifact verify, runtime smoke를 대신하지 않음 |
| `make dist/dmg/dev/compile` | compile 단계만 다시 실행하거나 실패를 분리할 때 | mutable disk는 항상 새로 생성. APT 계약과 checksum이 맞으면 `apt-prepared-rootfs.raw.gz`에서 시작 | DMG artifact 생성까지만 보장. 현장 전달 proof가 아님 |
| `make dist/dmg/dev/verify` | 이미 만든 DMG와 golden rootfs를 다시 검사할 때 | compile하지 않으며 현재 golden cache가 없거나 stale이면 즉시 실패 | artifact readback과 golden runtime smoke 진단 |
| `make dist/dmg/release` | release DMG를 현장 전달할 때 | dev 표준 gate와 같은 clean compile 정책 | release branch guard를 포함한 release 현장 전달 gate |

`clean compile`은 이전 mutable `vm-disk.img`를 이어서 사용하지 않는다는 뜻입니다.
유효한 APT-prepared cache가 있으면 새 disk를 해당 immutable seed에서 복원하므로
Ubuntu snapshot probe와 `apt-get update/install`은 실행하지 않습니다. APT cache가
없거나 contract/checksum/Guest package proof가 맞지 않을 때만 Ubuntu base에서 APT를
한 번 실행하고 새 cache를 발행합니다.

캐시는 두 층입니다.

```text
apt-prepared-rootfs.raw.gz
  Ubuntu + APT package state
  -> APT/build 계약이 같으면 제품 소스 변경과 무관하게 재사용

rootfs-base.raw.gz
  APT base + 현재 Guest deploy + Docker images + rootfs smoke proof
  -> 전체 source fingerprint와 receipt가 같을 때만 /cached에서 재사용
```

## 3. Layout

```text
apps/
  vitalserver/                VitalServer core runtime wrapper
  vitalserver-recorder-ingress/    VRecorder command/IP/activity audit sidecar
  vitaldb-observer/           recorder/bed/proxy/anomaly observation collector
  vitalserver-lab/            Product Lab scenarios, virtual recorder, .vital replay
  vitalserver-macos-runtime/  macOS Helper app, HostCLI, Runtime Control API, packaging
  vitalserver-runtime-pwa/    Remote Console PWA
packages/
  vitalserver-devtools/       local build/proxy/runtime/package tools
  vitalserver-guest-tools/    Guest Control API, service operations, diagnostics tools
  vitalserver-testkit/        dev/load-test smoke and data-flow validation tools
docs/                         detailed design, ADR, API, troubleshooting source
site-docs/                    public documentation source
vendor/vitalserver/           git submodule: vitaldb/vitalserver
```

Build output와 local cache인 `dist/`, `site/`, `.tmp/`, `.artifacts/`, `tmp/`, `.venv/`는
source tree 설명에서 제외합니다.

## 4. Branch and Submodule

- `main`: 안정 브랜치, release/tag 기준
- `develop`: main으로 보내기 전 통합 브랜치
- `feature/*`: 이슈 단위 구현, `develop`에서 따고 `develop`으로 PR
- `hotfix/*`: main 기준 긴급 수정

`vendor/vitalserver`는 공식 upstream `vitaldb/vitalserver` submodule입니다. 일반 작업에서는
submodule 내부 코드를 직접 수정하지 않고, 필요한 경우 submodule commit만 이 저장소에서
갱신합니다.

```sh
make repo/init
make repo/update-submodule
git add vendor/vitalserver
```

자세한 branch 기준은 [`docs/repository/branching.md`](docs/repository/branching.md)를 봅니다.
