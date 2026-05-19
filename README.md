# tirosh-vitalserver

VitalDB VitalServer를 실제 제품 환경에서 사용할 수 있는 수준으로 감싸고,
운영에 필요한 실행, 관측, 검증 도구를 쌓아가는 저장소입니다.

공식 upstream VitalServer는 연구/데모 성격이 강하다고 보고, 이 저장소에서는 그 코드를
직접 고치기보다 제품 운영에 필요한 외곽 레이어를 관리합니다.

`vendor/vitalserver`는 Tirosh fork를 가리키는 git submodule입니다. VitalServer
애플리케이션 자체 수정은 fork repository에서 처리하고, 이 저장소에서는 wrapper app,
Compose 설정, API 문서, Redis relay, 검증 도구를 관리합니다.

## 빠른 실행

```sh
git clone --recurse-submodules https://github.com/tirosh-chain/tirosh-vitalserver.git
cd tirosh-vitalserver
make doctor
make up
```

VitalServer:

```text
http://localhost
```

Redis UI:

```text
http://localhost:8081
```

기본 관리자 계정:

```text
UserId: admin
Password: admin
```

## 요구사항

VitalServer를 Docker Compose로 실행하기만 할 때는 아래 도구만 있으면 됩니다.

- Docker
- Docker Compose v2
- Git submodule 지원 Git 클라이언트

Python 기반 검증 도구와 개발용 검사까지 실행하려면 uv가 추가로 필요합니다.
uv가 없더라도 `make up`, `make down`, `make logs`, `make swagger`,
`make swagger-down`은 사용할 수 있습니다.
Release wheel을 설치하면 uv 없이도 `make testkit-smoke` 같은 testkit scenario를 실행할 수 있습니다.

- uv
- Python 3.14 이상

로컬 환경이 준비됐는지 확인하려면 아래 명령을 실행합니다.

```sh
make doctor
```

submodule을 초기화하고, uv가 설치되어 있으면 Python workspace까지 동기화하려면 아래 명령을
사용합니다.

```sh
make bootstrap
```

uv가 없는 환경에서는 Python 동기화를 건너뛰고 Docker 실행 환경만 준비합니다. uv 설치가
필요하면 공식 설치 문서를 따릅니다.

```text
https://docs.astral.sh/uv/getting-started/installation/
```

uv 없이 release된 testkit wheel을 설치하려면 GitHub CLI 인증 후 아래 명령을 사용합니다.

```sh
gh auth login
make install-testkit-release TESTKIT_VERSION=0.1.0
```

이후 `make testkit-smoke`, `make testkit-load` 같은 검증 target은 설치된 wheel을 사용합니다.
uv가 설치된 개발 환경에서는 기존처럼 workspace source를 우선 사용합니다.

## 자주 쓰는 명령

```sh
make help            # 사용 가능한 명령 확인
make doctor          # 로컬 도구와 submodule 상태 확인
make bootstrap       # submodule 초기화, uv가 있으면 Python workspace 동기화
make install-testkit-release  # uv 없이 release wheel 기반 testkit 설치
make up              # macOS host proxy와 VitalServer stack 실행
make down            # proxy와 Compose stack 중지, Docker volume 유지
make logs            # log 확인
make ps              # container 상태 확인
make clean-volumes   # proxy와 전체 Compose stack 중지, Docker volume 삭제
make open            # VitalServer 브라우저 열기
make swagger         # 기본 stack은 건드리지 않고 Swagger UI만 시작
make swagger-down    # 기본 stack은 유지하고 Swagger UI만 중지
make proxy-config    # macOS host nginx proxy config 출력
make proxy-start     # macOS host nginx proxy만 수동 시작
make proxy-stop      # macOS host nginx proxy만 수동 중지
make proxy-status    # macOS host nginx proxy 상태 확인
make testkit-smoke   # simulator 기반 smoke scenario
make check           # lint, typecheck, test 실행
```

Swagger UI는 아래 주소에서 볼 수 있습니다.

```text
http://localhost:8082
```

Swagger UI는 기본 stack을 먼저 실행한 뒤 별도로 시작합니다. `make swagger`는 `swagger-ui`
컨테이너만 시작하며, `redis`나 `app`을 함께 시작하지 않습니다.

```sh
make up
make swagger
```

포트를 바꾸려면 `.env` 또는 실행 환경에서 `SWAGGER_UI_PORT`를 지정합니다.
Swagger UI는 `/vitalserver` reverse proxy를 통해 같은 origin에서 VitalServer를 호출합니다.
브라우저가 직접 Docker backend인 `http://localhost:18080`을 호출하지 않기 때문에 CORS에
걸리지 않습니다.
Swagger UI만 정리하려면 전체 stack을 내리지 않고 `make swagger-down`을 실행합니다.

macOS 운영 서버에서 VR 장비의 원 IP를 보존해야 하면 Docker port를 장비에 직접 노출하지 않고
host nginx를 앞단에 둡니다. 예시는 `docs/vitalserver-productization.md`의
`VR Network Settings IP` 섹션과 `infra/macos-nginx/vitalserver.conf.template`을 봅니다.
설치형 배포에서는 Docker backend를 `127.0.0.1:18080`으로 묶고, macOS host nginx를
LaunchDaemon으로 실행해 외부 장비와 브라우저가 proxy port로만 접속하게 합니다.

## 구조

```text
.
├── compose.yaml
├── Makefile
├── pyproject.toml
├── apps/
│   └── vitalserver/           # upstream VitalServer를 감싼 제품 실행 app
│       ├── docker/            # Docker 배포 target
│       └── runtime/           # 공통 실행 shim
├── config/
│   └── testkit.toml
├── docs/
├── infra/
│   └── swagger-ui/           # Swagger UI reverse proxy 설정
├── make/                     # Makefile target group
├── packages/
│   └── vitalserver-testkit/   # 운영 검증과 데이터 전송 검증용 Python 도구
├── scripts/
└── vendor/
    └── vitalserver/           # git submodule: tirosh-chain/vitalserver
```

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

자세한 기준은 `docs/branching.md`를 봅니다.

## 제품화 방향

이 저장소의 목적은 upstream VitalServer를 바로 운영에 올리기 어려운 연구용 서버에서,
제품 환경에 투입 가능한 구성요소로 끌어올리는 것입니다.

우선순위는 아래에 둡니다.

- Compose로 재현 가능한 실행 환경 만들기
- upstream route와 Socket.IO 동작을 문서화하기
- Redis에 쌓이는 실시간 데이터 구조를 파악하고 relay 가능하게 만들기
- simulated Vital Recorder data와 실제 payload를 흘려보내며 운영 검증하기
- 장시간 실행 중 서버, Redis, container 상태를 관측하기
- 제품에서 필요한 설정, 백업, 복구, 모니터링 지점을 외곽에서 보강하기

`packages/vitalserver-testkit`은 이 제품화 작업을 검증하기 위한 도구입니다. testkit 자체가
저장소의 목적은 아니고, 실시간 수집/업로드/relay가 운영 요구를 만족하는지 확인하는
수단입니다.

제품화 검증 시나리오는 `scripts/test_vitalserver.py`와 Makefile target으로 실행합니다.

```sh
make testkit-smoke
make testkit-verify
make testkit-load
make testkit-stream
```

기본 설정은 `config/testkit.toml`에 둡니다. 기본값은 recorder 5대를 흉내내고,
`make testkit-load`에서 총 500개 `send_data` event를 보내도록 잡아 둡니다.
`make testkit-stream`은 Ctrl+C 전까지 계속 보냅니다.
더 강한 부하나 별도 시나리오가 필요하면 다른 config를 지정합니다.

```sh
cp config/testkit.toml config/load-test.toml
TESTKIT_CONFIG=config/load-test.toml make testkit-load
```

### testkit release

`vitalserver-testkit`은 당분간 수동 versioning으로 관리합니다.
`packages/vitalserver-testkit/pyproject.toml`의 `version`을 올리고 `testkit-v{version}`
형태의 tag를 push하면 GitHub Actions가 wheel과 sdist를 build한 뒤 GitHub Release asset에
업로드합니다.

```sh
make check
make build-testkit
git tag testkit-v0.1.0
git push origin testkit-v0.1.0
```

`make build-testkit`은 wheel과 sdist를 `packages/vitalserver-testkit/dist/` 아래에 생성합니다.
Release wheel은 `make install-testkit-release TESTKIT_VERSION=0.1.0`으로 설치할 수 있습니다.

PR과 `main` push에서는 testkit 관련 파일이 바뀐 경우에만 testkit CI가 실행됩니다.
Release workflow도 이전 `testkit-v*` tag 이후 testkit 관련 변경이 있을 때만 package를
build하고 release asset을 업로드합니다. Release note는 monorepo 전체 changelog가 아니라
`vitalserver-testkit` package 기준의 간단한 설치 안내만 남깁니다.

관련 문서는 `docs/` 아래에 둡니다. 전체 문서 구조는 `docs/index.md`를 기준으로 봅니다.

- `docs/index.md`: 문서 지도와 작성 기준
- `docs/branching.md`: branch와 package tag 운영 기준
- `docs/vitalserver-productization.md`: VitalServer 제품화 맥락과 API/payload 배경
- `docs/vrecorder.md`: VRecorder 접속 흐름과 Web Monitoring 상태 표시 기준
- `docs/testkit-usage.md`: testkit 실행 방법과 결과 해석
- `docs/redis-data-model.md`: Redis key 구조와 relay 설계 메모
- `docs/openapi.yaml`: upstream VitalServer route에서 추출한 OpenAPI 문서

## Submodule 관리

이미 clone한 저장소에서 submodule이 비어 있다면 아래 명령으로 초기화합니다.

```sh
make init
```

fork repository의 변경분을 반영하려면 submodule을 업데이트한 뒤 변경된 submodule commit을
이 저장소에 commit합니다.

```sh
make update-submodule
git status
git add vendor/vitalserver
git commit -m "Update vitalserver submodule"
```

일반적인 작업에서는 `vendor/vitalserver` 내부 코드를 수정하지 않습니다.
VitalServer 애플리케이션 로직을 바꿔야 하면 `tirosh-chain/vitalserver` fork에서 작업한 뒤
이 저장소의 submodule commit만 갱신합니다. 공식 upstream 변경을 가져올 때는 fork
repository에서 `upstream` remote를 기준으로 merge/rebase한 뒤 반영합니다.
