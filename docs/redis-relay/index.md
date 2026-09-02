# Redis Relay

Redis Relay는 VitalServer가 사용하는 Source Redis를 외부에 직접 공개하지 않고,
허용된 실시간 데이터를 운영자가 지정한 Target Redis로 전달하는 독립 애플리케이션입니다.
numeric, trend, waveform처럼 HTTP polling에 적합하지 않은 데이터를 Redis 원본 형식으로
전달하며, Target 측 시스템이 이를 소비하고 가공할 수 있게 합니다.

이 문서군은 Redis Relay 자체의 설정, 전송 계약, 설치와 운영 방법의 기준입니다.
Runtime Control, macOS VM, Linux Container 문서는 각 실행 환경과 Relay의 연결만 설명하고,
Relay 내부 계약은 이 문서군을 참조합니다.

## 1. 목적과 비목적

### 1-1. 해결하는 문제

VitalServer의 실시간 데이터는 크고 빠르게 변합니다. Source Redis port를 외부에 열면
필요한 생체신호 데이터뿐 아니라 session, credential, 운영 내부 상태까지 같은 경계로
노출될 수 있습니다. Relay는 Source Redis를 read-only로 읽고, 코드에 정의된 policy로
허용한 key만 별도 Target Redis에 publish하여 이 경계를 분리합니다.

### 1-2. Relay가 아닌 것

- VitalServer 공식 HTTP 또는 HL7 API가 아닙니다.
- Source Redis port를 외부 network에 공개하는 proxy가 아닙니다.
- source payload를 임상 표준 모델로 decode하는 서비스가 아닙니다.
- Target consumer의 queue, DLQ, pending recovery를 대신 관리하지 않습니다.
- Source에서 사라진 key를 복구하는 durable queue가 아닙니다.

## 2. 아키텍처

### 2-1. Native Host 기본 구조

Native Host 배포가 기본 방향입니다. VitalServer와 Source Redis는 Host에서 동작하고,
Relay는 같은 Host의 전용 사용자로 실행됩니다.

```text
VRecorder / device
        |
        v
VitalServer ----> Source Redis (local)
                         |
                         | SCAN / TYPE / PTTL / DUMP
                         v
                   Redis Relay
                         |
                         | RESTORE + metadata event
                         v
                   Target Redis ----> external consumer
```

Target Redis나 consumer는 Source Redis에 역으로 접속하지 않습니다. Source는 read-only,
Target은 publish-only라는 방향을 유지합니다.

### 2-2. VM과 Container 호환

Relay runtime은 OS나 VM 여부를 감지하지 않습니다. 실행 환경은 config와 status publisher
입력을 명시적으로 조립합니다. 기존 VM과 Linux Container는 같은 Python module과 Protocol
v1을 계속 사용하며, Native Host는 별도의 구현이 아닙니다.

| 환경 | 프로세스 owner | 실행 방식 | 상태 출력 |
|---|---|---|---|
| macOS Native | launchd | console script, foreground | JSON file |
| Linux Native | systemd | console script, foreground | JSON file |
| VM Guest | Guest service/Compose | `python -m vitalserver_redis_relay` | file + HTTP owner |
| Linux Container | Container supervisor | `python -m vitalserver_redis_relay` | file + Unix socket owner |

Windows native service는 현재 범위 밖입니다. Windows에서 Guest/Container로 실행하는 기존
경로와 Native Windows Service 지원은 같은 의미가 아닙니다.

## 3. 책임과 경계

### 3-1. 책임 지도

| 책임 | Owner |
|---|---|
| Source Redis 데이터와 key 수명 | VitalServer / Source Redis |
| Relay 설정과 credential file 제공 | Native operator 또는 Runtime Control |
| 허용 key policy | Redis Relay domain policy |
| Snapshot 읽기와 Protocol v1 publish | Redis Relay |
| 프로세스 start/stop/restart | launchd, systemd 또는 Guest/Container supervisor |
| Target payload decode와 downstream write | Target consumer |
| Consumer pending recovery와 DLQ | Target consumer |

Relay는 다른 owner의 상태를 추측하지 않습니다. 설정 파일 부재, `enabled = false`, 설정
decode 실패, credential 접근 실패는 서로 다른 상태로 보고됩니다.

### 3-2. 보안 경계

- Source Redis는 외부에 직접 공개하지 않습니다.
- session, authentication, credential 계열 key는 항상 차단합니다.
- TOML, CLI, 환경변수에는 credential 값이 아니라 file path만 둡니다.
- username과 password 값은 status, fingerprint, repr, API read-back에 포함하지 않습니다.
- 운영 환경의 Target Redis에는 TLS와 ACL credential 사용을 권장합니다.

## 4. 주요 기능

- `SCAN`, `TYPE`, `PTTL`, `DUMP`를 사용한 Source snapshot 읽기
- `waveform_trend_only`, `vital_reconstruction` scope policy
- Source 자료형, binary payload, TTL을 보존한 Target `RESTORE`
- payload fingerprint를 사용한 unchanged 판단
- dedupe state와 `key_published` Redis Stream event의 원자적 기록
- bounded reconnect/backoff와 batch 단위 재시도
- 설정, 진행량, 최근 오류를 구분하는 status schema v1
- File, HTTP, Unix socket status publisher adapter

## 5. 빠른 시작

### 5-1. 개발 환경

저장소 root에서 wheel을 만들고 repository-local venv에 설치합니다.

```sh
uv build --package tirosh-vitalserver-redis-relay --wheel
uv venv .venv-redis-relay
uv pip install --python .venv-redis-relay/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
.venv-redis-relay/bin/vitalserver-redis-relay --help
```

`.venv-redis-relay`는 개발 확인용입니다. launchd와 systemd는
[운영 가이드](operations.md)에 정의한 system venv를 사용합니다.

### 5-2. 읽는 순서

1. Source, Target, scope와 secret file은 [설정과 보안](configuration.md)을 봅니다.
2. Target Redis의 key와 event 의미는 [Protocol v1](protocol-v1.md)을 봅니다.
3. 설치, supervisor, 상태 확인과 장애 대응은 [운영 가이드](operations.md)를 봅니다.

## 6. 관련 문서

| 문서 | 책임 |
|---|---|
| [설정과 보안](configuration.md) | TOML, scope, credential, 설정 오류 계약 |
| [Protocol v1](protocol-v1.md) | Source snapshot과 Target Redis publish 계약 |
| [운영 가이드](operations.md) | Native 설치, process lifecycle, status와 장애 대응 |
| [Recorder Redis key model](../recorder/redis-key-model.md) | VitalServer Redis key의 의미와 근거 |
| [Runtime Control API](../runtime/macos/runtime-control-api.md) | Guest/Runtime settings와 status API |
| [Runtime observability](../runtime/macos/observability.md) | 제품 전체 관측 owner와 Relay 연결 |
| [Troubleshooting](../troubleshooting/index.md) | 실제 장애 사례와 조치 기록 |
