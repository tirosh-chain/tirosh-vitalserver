# tirosh-vitalserver

VitalDB upstream VitalServer를 실제 제품 환경에서 사용할 수 있는 수준으로 감싸고,
운영에 필요한 실행, 관측, 검증 도구를 쌓아가는 저장소입니다.

upstream VitalServer는 연구/데모 성격이 강하다고 보고, 이 저장소에서는 그 코드를 직접
고치기보다 제품 운영에 필요한 외곽 레이어를 관리합니다.

이 저장소는 VitalServer 애플리케이션 코드를 직접 수정하지 않습니다. VitalDB upstream
코드는 `vendor/vitalserver` git submodule로 고정하고, 이 저장소에서는 wrapper app,
Compose 설정, API 문서, Redis relay, 검증 도구를 관리합니다.

## 빠른 실행

```sh
git clone --recurse-submodules https://github.com/tirosh-chain/tirosh-vitalserver.git
cd tirosh-vitalserver
make up
```

VitalServer:

```text
http://localhost:8080
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

- Docker
- Docker Compose v2
- Git submodule 지원 Git 클라이언트
- uv

Python 검증 도구는 Python 3.14 이상을 사용합니다.

## 자주 쓰는 명령

```sh
make help            # 사용 가능한 명령 확인
make up              # VitalServer stack 실행
make down            # stack 중지, Docker volume 유지
make logs            # log 확인
make ps              # container 상태 확인
make swagger         # Swagger UI 실행
make testkit-smoke   # simulator 기반 smoke scenario
make check           # lint, typecheck, test 실행
```

Swagger UI는 아래 주소에서 볼 수 있습니다.

```text
http://localhost:8082
```

포트를 바꾸려면 `.env` 또는 실행 환경에서 `SWAGGER_UI_PORT`를 지정합니다.
Swagger UI는 `/vitalserver` reverse proxy를 통해 같은 origin에서 VitalServer를 호출합니다.
브라우저가 직접 `http://localhost:8080`을 호출하지 않기 때문에 CORS에 걸리지 않습니다.

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
    └── vitalserver/           # git submodule: vitaldb/vitalserver
```

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

PR과 `main` push에서는 testkit 관련 파일이 바뀐 경우에만 testkit CI가 실행됩니다.
Release workflow도 이전 `testkit-v*` tag 이후 testkit 관련 변경이 있을 때만 package를
build하고 release asset을 업로드합니다.

관련 문서는 `docs/` 아래에 둡니다. 전체 문서 구조는 `docs/index.md`를 기준으로 봅니다.

- `docs/index.md`: 문서 지도와 작성 기준
- `docs/vitalserver-productization.md`: VitalServer 제품화 맥락과 API/payload 배경
- `docs/testkit-usage.md`: testkit 실행 방법과 결과 해석
- `docs/redis-data-model.md`: Redis key 구조와 relay 설계 메모
- `docs/openapi.yaml`: upstream VitalServer route에서 추출한 OpenAPI 문서

## Submodule 관리

이미 clone한 저장소에서 submodule이 비어 있다면 아래 명령으로 초기화합니다.

```sh
make init
```

upstream 변경분을 반영하려면 submodule을 업데이트한 뒤 변경된 submodule commit을 이
저장소에 commit합니다.

```sh
make update-submodule
git status
git add vendor/vitalserver
git commit -m "Update vitalserver submodule"
```

일반적인 작업에서는 `vendor/vitalserver` 내부 코드를 수정하지 않습니다.
