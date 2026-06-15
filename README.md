# tirosh-vitalserver

VitalDB VitalServer를 제품 운영 환경에서 사용할 수 있도록 감싸는 monorepo입니다.
upstream VitalServer application 자체는 원본 `vitaldb/vitalserver`의 `vendor/vitalserver`
submodule snapshot으로 관리하고, 이 저장소는 실행 wrapper, macOS runtime, Remote Console PWA,
관측 sidecar, 검증 도구, 배포 산출물, 문서를 관리합니다.

핵심 원칙은 단순하고 명시적인 상태 계약입니다. Host는 runtime/process/filesystem state를
소유하고 명시적인 계약으로 제공하며, Guest와 UI는 그 계약을 소비합니다. 실패, 누락,
invalid, stale, empty state는 서로 다른 의미로 보존합니다.

## 빠른 실행

빠른 실행은 upstream VitalServer와 sidecar를 Compose sandbox로 띄워 local 개발과 검증을
시작하는 경로입니다.

```sh
git clone --recurse-submodules https://github.com/tirosh-chain/tirosh-vitalserver.git
cd tirosh-vitalserver
make dev/doctor
make compose/up
```

> 빠른 실행은 Compose sandbox 전용입니다. macOS Helper, Runtime Control API, Remote Console
> PWA는 package 설치 후 Helper app에서 확인하거나 개발 중 `make runtime/*`, `make pwa/*`로
> 따로 실행합니다.

기본 endpoint:

| 서비스 | 주소 |
|---|---|
| VitalServer | `http://localhost` |
| Redis UI | `http://localhost:8081` |
| VitalDB observer | `http://127.0.0.1:18083/api/v1/observations` |
| Swagger UI | `http://localhost:8082` after `make swagger/up` |

기본 관리자 계정:

```text
UserId: admin
Password: admin
```

Swagger UI는 기본 stack을 먼저 실행한 뒤 별도로 시작합니다.

```sh
make compose/up
make swagger/up
```

## 요구사항

Docker Compose 기반 VitalServer stack만 실행할 때:

- Docker
- Docker Compose v2
- Git submodule 지원 Git 클라이언트
- nginx

macOS 기본 구성의 `make compose/up`은 Docker backend를 `127.0.0.1:18080`에 묶고
Homebrew nginx 기반 host proxy를 함께 실행합니다. VR 장비의 원 IP를 보존해야 하므로
운영 환경에서도 Docker port를 장비에 직접 노출하지 않고 host proxy를 앞단에 둡니다.

개발, 검증, packaging까지 다룰 때 추가로 필요합니다.

- uv
- Python 3.14 이상
- Node.js와 npm, Runtime Control PWA를 개발하거나 build할 때
- Xcode/Swift toolchain, macOS runtime package를 build/test할 때

환경을 준비하려면 아래 명령을 사용합니다.

```sh
make dev/bootstrap
```

`make dev/bootstrap`은 submodule, `.env`, 로컬 proxy config를 준비하고, uv가 설치되어 있으면
Python workspace를 동기화합니다. 마지막에는 `make dev/doctor`로 Docker, nginx, proxy port,
Compose 설정을 확인합니다. uv가 없어도 Docker stack 실행 경로는 사용할 수 있습니다.

uv 없이 release된 testkit wheel을 설치하려면 GitHub CLI 인증 후 아래 명령을 사용합니다.

```sh
gh auth login
make testkit/install-release TESTKIT_VERSION=0.1.1
```

## 자주 쓰는 명령

```sh
make help               # 시작 메뉴
make help/dev           # repository setup, Python 개발 검사
make help/compose       # Compose sandbox, Swagger, testkit
make help/runtime       # local macOS VM runtime lifecycle
make help/pwa           # Runtime Control PWA
make help/dist          # package, install, update bundle
make help/devtools      # 저수준 build/debug/troubleshooting

make dev/doctor         # 로컬 개발 도구와 repository setup 확인
make dev/bootstrap      # .env, submodule, proxy config, 선택적 Python workspace 준비

make compose/up             # macOS host proxy와 Compose sandbox 실행
make compose/open           # VitalServer 브라우저 열기
make testkit/smoke          # bounded productization smoke scenario
make compose/down           # proxy와 Compose stack 중지, Docker volume 유지
make compose/logs           # container log 확인
make compose/ps             # container 상태 확인
make compose/rebuild        # app image rebuild 후 app container만 재생성
make compose/clean/volumes  # proxy와 Compose stack 중지, Docker volume 삭제
make compose/clean          # proxy runtime, container, volume, orphan, local image 정리

make swagger/up         # Swagger UI만 시작
make swagger/down       # Swagger UI만 중지

make testkit/verify     # sample data 전송 후 UI-visible state 검증
make testkit/health     # VitalServer health 확인
make testkit/load       # finite load scenario
make testkit/stream     # Ctrl+C 전까지 sample data stream

make pwa/install        # Runtime Control PWA npm dependency 설치
make pwa/verify-contract # OpenAPI 생성 type commit 상태 검증
make pwa/check          # PWA typecheck
make pwa/test           # PWA test
make pwa/build          # PWA static asset build

make runtime/up         # local macOS VM runtime과 host proxy 실행
make runtime/status     # local runtime process status 확인
make runtime/health     # local runtime health 확인
make runtime/down       # local runtime 중지
make runtime/chaos      # deterministic runtime chaos scenario

make dist/pkg/dev       # development pkg build
make dist/dmg/dev       # development installer dmg build
make dist/reset-installer/dev  # Reset Installer pkg build
make dist/update/dev    # development product update bundle build
make dist/install/dev/verified  # dev pkg verify, install, installed health check
make dist/installed/health      # repo-driven dev install runtime health check
```

Make는 `.env`를 자동으로 읽습니다. 포트를 바꾸려면 `.env`를 수정하거나 일회성으로
`VITALSERVER_PROXY_PORT=8080 make compose/up`처럼 Make 변수로 넘깁니다.
Swagger UI 포트는 `SWAGGER_UI_PORT`로 조정합니다.

## 구조

```text
.
├── compose.yaml
├── Makefile
├── apps/
│   ├── vitalserver/               # upstream VitalServer를 감싼 제품 실행 app
│   ├── vitalserver-audit-proxy/   # VRecorder command audit sidecar
│   ├── vitaldb-observer/          # Redis/proxy 기반 VitalDB 관측 sidecar
│   ├── vitalserver-guest-observability/
│   ├── vitalserver-macos-runtime/ # macOS Helper, HostCLI, Runtime Control API
│   ├── vitalserver-runtime-pwa/   # Remote Console PWA
│   └── vitalserver-vm-launcher/
├── config/
│   ├── testkit.toml
│   └── vm-build.toml
├── docs/                          # 개발/운영 결정, API, runtime, troubleshooting 문서
├── site-docs/                     # 공개 release/dev 문서
├── infra/
│   ├── macos-nginx/               # macOS host proxy 설정과 launchd template
│   └── swagger-ui/                # Swagger UI reverse proxy 설정
├── make/                          # Make target group
├── packages/
│   ├── vitalserver-devtools/      # local build/proxy/runtime/package Python 도구
│   ├── vitalserver-guest-tools/   # guest observability/diagnostics 도구
│   └── vitalserver-testkit/       # 운영 검증과 데이터 전송 검증용 Python 도구
├── scripts/
└── vendor/
    └── vitalserver/               # git submodule: tirosh-chain/vitalserver
```

release manifest의 source of truth는 아래 파일입니다.

- `apps/vitalserver-macos-runtime/release.json`: stable channel
- `apps/vitalserver-macos-runtime/release-dev.json`: dev channel

## 제품화 방향

이 저장소의 목적은 upstream VitalServer를 바로 운영에 올리기 어려운 연구용 서버에서,
제품 환경에 투입 가능한 구성요소로 끌어올리는 것입니다.

우선순위:

- Compose로 재현 가능한 실행 환경 만들기
- upstream route와 Socket.IO 동작을 문서화하기
- Redis에 쌓이는 실시간 데이터 구조를 파악하고 relay 가능하게 만들기
- simulated Vital Recorder data와 실제 payload를 흘려보내며 운영 검증하기
- VitalDB recorder/bed/proxy/anomaly 관측을 upstream 수정 없이 sidecar로 수집하기
- macOS Helper, Runtime Control API, Remote Console PWA를 명시적 계약으로 연결하기
- 제품에서 필요한 설정, backup, recovery, update, monitoring 지점을 Host runtime에서 보강하기

관측 정보는 owner별 source를 보존한 뒤 watchdog/runtime이 제품 status, event, SQLite read
model로 정규화합니다. `vitaldb-observer`는 Redis와 proxy/access log를 읽어 snapshot을
생산하는 stateless collector입니다. 자세한 책임 경계는
[Runtime observability model](docs/runtime/macos/observability.md)을 봅니다.

## 검증 도구

`packages/vitalserver-testkit`은 제품화 작업을 검증하기 위한 도구입니다. testkit 자체가
제품의 목적은 아니고, 실시간 수집, upload, relay, UI-visible state가 운영 요구를 만족하는지
확인하는 수단입니다.

```sh
make testkit/smoke
make testkit/verify
make testkit/load
make testkit/stream
```

기본 설정은 `config/testkit.toml`에 둡니다. 더 강한 부하나 별도 시나리오가 필요하면 다른
config를 지정합니다.

```sh
cp config/testkit.toml config/load-test.toml
TESTKIT_CONFIG=config/load-test.toml make testkit/load
```

`vitalserver-testkit`은 package별 tag로 release합니다. `packages/vitalserver-testkit/pyproject.toml`의
`version`을 올리고 `testkit-v{version}` tag를 push하면 GitHub Actions가 wheel과 sdist를
build한 뒤 GitHub Release asset에 업로드합니다.

```sh
make dev/check
make dev/build-testkit
git tag testkit-v0.1.1
git push origin testkit-v0.1.1
```

## 문서

전체 문서 구조와 읽는 순서는 [문서 지도](docs/index.md)를 기준으로 봅니다.

자주 보는 진입점:

- [VitalServer 제품화 전략](docs/product/productization.md): 제품화 맥락과 API/payload 배경
- [Release Overview](site-docs/release/index.md): 공개 배포 독자용 설치/운영 문서
- [Dev Overview](site-docs/dev/index.md): contributor와 유지보수자용 개발 문서
- [Vital Recorder](docs/recorder/vrecorder.md): VRecorder 접속 흐름과 Web Monitoring 상태 표시 기준
- [Redis 데이터 구조](docs/recorder/redis-data-model.md): Redis key 구조와 relay 설계 메모
- [Testkit 사용법](docs/testkit/usage.md): testkit 실행 방법과 결과 해석
- [OpenAPI 문서](docs/api/vitalserver.openapi.yaml): upstream VitalServer route spec
- [Runtime Control PWA](docs/pwa/index.md): Remote Console PWA 구현 기준
- [VitalServer macOS Runtime](docs/runtime/macos/index.md): Mac mini VM runtime 문서군
- [Runtime Control API](docs/runtime/macos/runtime-control-api.md): PWA/native shell 공통 API와 SSE 계약
- [Runtime observability model](docs/runtime/macos/observability.md): status/event/VitalDB observation 책임 경계
- [Troubleshooting](docs/troubleshooting/index.md): 반복 장애 패턴, 원인, 조치, 예방 원칙
- [Branch 운영 기준](docs/repository/branching.md): branch와 package tag 운영 기준

## Branch 운영

이 저장소는 monorepo이고 package별 tag를 사용합니다. branch는 release version을 표현하기보다
작업의 위험도와 통합 위치를 구분합니다.

- `main`: 보호된 안정 브랜치, release/tag 기준
- `develop`: main으로 보내기 전 작업을 모으는 통합 브랜치
- `feature/*`: 이슈 단위 구현, `develop`에서 따고 `develop`으로 PR
- `experiment/*`: 성공 여부가 불확실한 실험
- `hotfix/*`: main 기준 긴급 수정

작은 문서 정리나 낮은 위험도의 운영 메모는 `develop`에 직접 commit할 수 있습니다. 기능
구현이나 위험한 변경은 별도 branch에서 작업한 뒤 `develop`으로 합칩니다. release는
`develop`에서 검증한 내용을 `main`으로 PR merge한 뒤 package tag를 붙입니다.

자세한 기준은 [Branch 운영 기준](docs/repository/branching.md)을 봅니다.

## Submodule 관리

이미 clone한 저장소에서 submodule이 비어 있다면 아래 명령으로 초기화합니다.

```sh
make repo/init
```

fork repository의 변경분을 반영하려면 submodule을 업데이트한 뒤 변경된 submodule commit을
이 저장소에 commit합니다.

```sh
make repo/update-submodule
git status
git add vendor/vitalserver
git commit -m "Update vitalserver submodule"
```

일반적인 작업에서는 `vendor/vitalserver` 내부 코드를 수정하지 않습니다.
VitalServer 애플리케이션 로직을 바꿔야 하면 `tirosh-chain/vitalserver` fork에서 작업한 뒤
이 저장소의 submodule commit만 갱신합니다. 공식 upstream 변경을 가져올 때는 fork
repository에서 `upstream` remote를 기준으로 merge/rebase한 뒤 반영합니다.
