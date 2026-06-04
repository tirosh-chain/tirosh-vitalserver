# VitalServer 제품화 전략

이 문서는 VitalServer를 연구/데모용 서버가 아니라 제품 환경에서 사용할 수 있는 구성요소로
만들기 위한 기준 문서입니다. 상세 실행법은 다른 문서로 분리하고, 여기서는 제품화 목표,
현재 확인된 동작, 운영에 필요한 보강 지점, 다음 작업을 정리합니다.

관련 문서:

- [문서 지도](index.md): 문서별 역할과 읽는 순서
- [OpenAPI 문서](openapi.yaml): upstream route를 분석해 정리한 Swagger/OpenAPI 문서
- [Redis 데이터 구조](redis-data-model.md): 실시간 monitor data가 Redis에 저장되는 방식
- [Vital Recorder](vrecorder.md): VRecorder 접속 흐름과 Web Monitoring 상태 표시 기준
- [testkit 사용법](testkit-usage.md): 실시간 수집, upload, health 검증 도구 사용법

## 목표

이 저장소의 목표는 VitalServer fork를 제품 기준으로 고정하고, 외곽 레이어를 쌓아 운영
가능한 제품 구성요소로 만드는 것입니다. Compose, 문서, 검증 도구는 이 저장소에서 관리하고,
VitalServer 애플리케이션 자체 수정은 fork repository에서 관리합니다.

우리가 관리하는 영역:

- Docker Compose 기반 실행 환경
- fork된 VitalServer를 감싸는 wrapper app과 runtime shim
- API와 Socket.IO 동작 문서화
- Redis 데이터 구조 분석과 relay 설계
- 실시간 수집, `.vital` upload, 장시간 운영 검증 도구
- 제품 운영에 필요한 설정, 관측, 백업, 복구 지점

우리가 지금 단계에서 하지 않는 영역:

- 이 저장소에서 `vendor/vitalserver` 내부 application logic 직접 수정
- upstream UI 대규모 개편
- VitalDB public cloud API와의 완전 호환 보장
- 의료기기 수준의 인증/감사 요구사항 충족 선언

## 현재 구성

```text
.
├── compose.yaml                # VitalServer, Redis UI, Swagger UI 실행
├── apps/vitalserver/           # upstream vitalserver-old를 감싼 제품 실행 app
│   ├── docker/                 # Docker image 배포 target
│   └── runtime/                # 배포 방식과 무관한 실행 shim
├── infra/swagger-ui/           # Swagger UI reverse proxy 설정
├── make/                       # Makefile target group
├── docs/                       # 문서 지도, 제품화 문서, OpenAPI, Redis 구조
├── packages/vitalserver-testkit/
│   └── src/                    # 운영 검증용 Python CLI/package
└── vendor/vitalserver/         # tirosh-chain/vitalserver fork submodule
```

기본 로컬 endpoint:

- VitalServer: `http://localhost`
- Redis UI: `http://localhost:8081`
- Swagger UI: `http://localhost:8082`

Swagger UI는 같은 origin에서 VitalServer를 호출하도록 `/vitalserver` reverse proxy를 사용합니다.
OpenAPI 문서에는 이 proxy server만 노출해서, Swagger의 `Try it out`이 브라우저 CORS에
걸리지 않도록 합니다.

```sh
make app/up            # proxy와 기본 stack 실행
make open          # VitalServer 브라우저 열기
make app/restart       # proxy와 기본 stack 재시작
make app/down          # proxy와 전체 Compose stack 중지, Docker volume 유지
make app/clean/volumes # proxy와 전체 Compose stack 중지, Docker volume 삭제

make swagger/up       # 기본 stack은 건드리지 않고 Swagger UI만 시작
make swagger/down     # 기본 stack은 유지하고 Swagger UI만 중지
```

## 확인된 upstream 동작

upstream VitalServer `2.3.4` 코드를 분석하면서 public 문서와 다른 부분을 확인했습니다.

| 영역 | public 문서/초기 가정 | upstream 코드 기준 |
| --- | --- | --- |
| 실시간 수집 | `POST /api/send` | Socket.IO `send_data` event |
| 실시간 payload | JSON body | zlib 압축 JSON |
| upload | `POST /api/upload` | `POST /upload`, `POST /upload_vital.php` |
| API 문서 | 별도 Swagger 없음 | 이 repo에서 `docs/openapi.yaml`로 생성 |
| Redis 구조 | 문서화 부족 | `monitor.js`, `db.js` 기준으로 별도 정리 |

제품화 작업에서는 public 문서보다 현재 포함한 upstream code를 우선 기준으로 삼습니다.
public 문서와 다른 부분은 OpenAPI와 제품화 문서에 명시합니다.

### VR Network Settings IP

Web Monitoring의 `Network Settings`는 Socket.IO `join_vr` 처리 시 저장된 `ip_<vrcode>` 값을
받아 `http://<ip>`로 엽니다. 실제 VRecorder client source는 이 repo에 없으므로 제품 장비가
`join_vr`를 보내는지는 접속 로그와 Redis 값으로 검증합니다. macOS Docker Desktop의 port
forwarding을 직접 거치면 container 내부에서는 실제 VR IP 대신 Docker gateway IP가 보일 수
있습니다.

fork된 VitalServer는 `VITALSERVER_TRUST_PROXY=1`일 때만 `X-Forwarded-For`,
`Forwarded: for=...`, `X-Real-IP`, `X-Client-IP` header를 우선 사용합니다. 기본값은 기존처럼
socket remote address를 사용합니다. 따라서 macOS 운영 환경에서는 VR 접속이 host-level
proxy나 ingress를 지나면서 실제 client IP header를 전달하도록 구성하고,
`VITALSERVER_TRUST_PROXY=1`을 명시적으로 켭니다. Docker container 내부에서만 network 정보를
읽어서는 NAT 이전의 VR IP를 복원할 수 없습니다.

macOS 운영 서버에서는 Docker published port를 외부에 직접 노출하지 않고, host nginx가
외부 접속을 받은 뒤 Docker backend로 proxy합니다.

```text
VR 장비 / 브라우저
  -> macOS host nginx :80
  -> Docker published backend 127.0.0.1:18080
  -> VitalServer container :80
```

설치형 VM에서는 아래 값을 deploy `runtime-config.json`으로 관리합니다.

```json
{
  "vitalserverHttpPort": 18080,
  "redisHost": "redis",
  "redisPort": 6379,
  "trustProxy": true,
  "publicHost": "",
  "publicPort": 80
}
```

이 구성에서 Docker backend는 macOS host loopback에만 열고, 외부 장비와 브라우저는 host
nginx port로만 접속합니다. Docker published port를 LAN에 직접 노출하면 Docker Desktop NAT
이후의 gateway IP가 `ip_<vrcode>`에 저장될 수 있습니다.
Redis는 host에 publish하지 않고 Compose 내부 network의 `redis:6379`로만 접근합니다.

Web Monitoring의 Socket.IO 접속 주소는 기본적으로 same-origin path(`/`)를 사용합니다. 즉 브라우저가
`http://<macOS host LAN IP 또는 DNS>`로 접속하면 Socket.IO도 같은 host와 port로
붙습니다. 여러 접속 주소를 동시에 지원해야 하는 환경에서는 `VITALSERVER_PUBLIC_HOST`를
비워두는 것이 안전합니다. 단일 public 주소로 강제해야 하는 환경에서만
`VITALSERVER_PUBLIC_HOST`, `VITALSERVER_PUBLIC_PORT`를 명시합니다.

host nginx config는 아래 명령으로 렌더링합니다.

```sh
make proxy/config
```

렌더링된 config는 macOS host의 nginx 설정에 포함합니다. 이 config는 client가 보낸
forwarding header를 신뢰하지 않고 host nginx의 `$remote_addr`로 덮어써서 VitalServer에
전달합니다.

로컬 PoC에서는 Homebrew nginx를 설치한 뒤 `make app/up`으로 proxy와 Docker backend를 함께 실행합니다.
기본 proxy port는 80이므로 nginx 실행 시 관리자 권한이 필요할 수 있습니다.

```sh
make app/up
make proxy/status
make app/down
```

`make app/up`은 Docker backend를 loopback으로 올리고, `.tmp/macos-nginx/vitalserver.conf`를 생성한 뒤
해당 config로 nginx를 실행합니다. Homebrew service를 등록하거나 launchd를 수정하지 않습니다.

설치형 배포에서는 nginx binary와 config를 macOS host에 설치하고 launchd로 관리합니다.
LaunchDaemon plist는 아래 명령으로 렌더링합니다.

```sh
make proxy/plist
```

설치 패키지는 nginx config, launchd plist, deploy `runtime-config.json`을 함께 생성해 container
backend와 native proxy가 같은 port 계약을 사용하도록 유지합니다.

## 데이터 흐름

실시간 수집 흐름:

1. Vital Recorder 또는 testkit이 Socket.IO `send_data` event를 보냅니다.
2. payload는 `{vrcode, ver, rooms}` 형태의 JSON을 zlib으로 압축한 값입니다.
3. VitalServer는 payload를 해제하고 room을 bed로 등록합니다.
4. Redis에 bed 상태, device metadata, timestamp index, 압축 frame을 저장합니다.
5. Web Monitoring client에는 `recv_data` event를 emit합니다.

testkit은 기본적으로 simulated room map payload를 생성하고, 필요하면 실제 장비에서 캡처한
JSON payload를 upstream이 기대하는 형태로 감싼 뒤 전송합니다.

제품화 검증의 첫 기준은 단순 전송 성공이 아니라, 전송 후 VitalServer의 UI용 endpoint에서
bed metadata가 조회되는 것입니다.

여러 recorder machine이 동시에 붙는 상황, 반복 전송량, 장시간 streaming 검증은 testkit
scenario로 재현합니다. 실제 실행 명령과 config 예시는 [testkit 사용법](testkit-usage.md)에
모읍니다.

Redis에 저장되는 핵심 key는 아래입니다.

- `beds`, `beds:<bedid>`
- `vrs`, `vrs:<vrcode>`
- `utimes`, `utime_<bedid>`, `utime_<vrcode>`
- `devs_<bedid>`, `dtapp_<bedid>`, `ptcon_<bedid>`
- `dts_<bedid>`, `<bedid><timestamp>`

자세한 key type, TTL, relay 방식은 [Redis 데이터 구조](redis-data-model.md)를 기준으로 봅니다.

## 제품화 기준

제품으로 쓰기 위해 최소한 아래 조건을 만족해야 합니다.

### 실행

- `make app/up`으로 깨끗한 환경에서 재현 가능하게 실행됩니다.
- 제품 VM의 포트, 관리자 비밀번호, Swagger 포트는 deploy `runtime-config.json`으로 조정합니다.
- 일회성 override는 `VITALSERVER_PROXY_PORT=8080 make app/up`처럼 Make 변수로 넘깁니다.
- VitalServer fork submodule은 명시적으로 고정하고, 변경 시 submodule commit을 리뷰합니다.

### API

- OpenAPI 문서가 현재 upstream route와 맞습니다.
- Swagger UI에서 주요 API를 실제로 호출할 수 있습니다.
- public 문서와 다른 route는 문서에 명시합니다.
- session 기반 UI API와 token 기반 API를 구분합니다.

### 실시간 수집

- Socket.IO `send_data` 경로로 Vital Recorder payload를 수신할 수 있습니다.
- Redis에 bed/device/frame key가 생성됩니다.
- `/vr_devs` 같은 UI용 endpoint에서 device metadata가 조회됩니다.
- simulated payload 또는 실제 payload를 timestamp shift하면서 반복 검증할 수 있습니다.
- 여러 recorder와 여러 bed를 동시에 보내는 상황을 재현할 수 있어야 합니다.
- recorder가 계속 연결된 상태에서 data를 streaming하는 상황을 재현할 수 있어야 합니다.

### Redis relay

- source Redis의 실시간 key를 target Redis로 전송할 수 있어야 합니다.
- 초기 구현은 `utimes`와 `dts_<bedid>`를 polling하는 방식으로 둡니다.
- `<bedid><timestamp>` frame은 binary 그대로 복제합니다.
- TTL, sorted set score, metadata key를 보존합니다.
- relay 중단 후에도 최근 4시간 window 안에서는 catch-up할 수 있어야 합니다.

### 운영 관측

- container health와 log를 확인할 수 있어야 합니다.
- Redis key 증가, TTL, active bed 수를 관측할 수 있어야 합니다.
- 장시간 실행 중 memory, Redis size, frame 처리량을 기록할 수 있어야 합니다.
- 실패율과 처리량은 testkit summary로 남깁니다.

## 현재 비어 있는 부분

다른 문서를 기준으로 보면 아직 아래가 비어 있습니다.

- Redis relay CLI/package 구현
- target Redis를 Compose로 함께 띄우는 선택적 profile
- relay 검증 시나리오와 테스트 데이터 세트
- Redis memory 사용량과 retention 정책
- 운영용 backup/restore 절차
- 관리자 비밀번호 rotation과 초기 계정 재설정 절차
- 실시간 수집 장시간 soak test 기준
- `.vital` upload 후 file metadata 생성 검증 절차
- 장애 재시작 후 catch-up 검증

## 다음 작업

우선순위는 Redis relay입니다. 제품 구성에서 source VitalServer의 Redis 데이터를 다른 Redis로
실시간 전송해야 하기 때문입니다.

1. `vitalserver-testkit redis-relay` subcommand 추가
2. source/target Redis URL, polling interval, lookback window 설정
3. `utimes`에서 active `bedid` 조회
4. `dts_<bedid>`에서 새 timestamp 조회
5. `<bedid><timestamp>` binary frame과 상태 key 복제
6. target Redis에서 key/TTL/sorted set score 검증
7. relay 중단 후 재시작 catch-up 검증

그 다음에는 제품 운영성을 높이는 작업으로 넘어갑니다.

- Compose profile로 target Redis와 relay worker 추가
- Redis 상태 exporter 또는 간단한 metrics command 추가
- `.vital` upload 검증을 실제 파일 기반으로 보강
- Swagger/OpenAPI를 upstream code 변경에 맞춰 갱신하는 절차 정리

## 참고 문서

- VitalDB 문서 목록: <https://vitaldb.net/docs/>
- VitalServer on-premise 사용자 매뉴얼: <https://vitaldb.net/docs/?documentId=1yE95k9nfTm2qyWooCFgGB3Rz76EVgi_c-rsWFr3Rxsk>
- IntraNet VitalDB API: <https://vitaldb.net/docs/?documentId=1bWaC2aylECIvBYPgTmLING3lgaUYDZ5LYymE17hgBdo>
- VitalDB Web API: <https://vitaldb.net/docs/?documentId=1jLTcF4JYbRTuSM2mZeTMmvzxMmrqUjEEp6p02cFEs_Q>
