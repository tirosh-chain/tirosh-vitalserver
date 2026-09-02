# VitalDB Observer

VitalDB Observer는 Host에서 VitalServer Source Redis를 read-only로 읽어, 최신 관측
snapshot을 local HTTP로 제공하는 최소 foreground daemon입니다. 사용자와 운영자는 이
문서를 기준으로 설치하고 장애를 판단합니다. 개발 진입점은
[앱 README](../../apps/vitaldb-observer/README.md)입니다.

## 1. 목적과 책임

### 1-1. Observer가 하는 일

Observer는 VitalServer가 Source Redis에 남긴 recorder, bed, device, filter, activity
상태를 읽습니다. 선택적으로 Host proxy access log를 읽어 최근 연결 흔적을 붙입니다.
결과는 요청 시점에 계산한 snapshot이며, 프로세스는 그 snapshot을 파일로 저장하지
않습니다.

프로세스 생명주기는 launchd가 소유합니다. Observer는 daemonize, pidfile, 자체 restart
manager 없이 foreground로 동작합니다. 상태 파일도 만들지 않습니다. 살아 있는지는
`/health`, Redis를 읽을 수 있는지는 `/ready`, 현재 관측값은
`/api/v1/observations`가 제공합니다.

```text
VRecorder / device
        |
        v
VitalServer ----> Source Redis (local, read-only)
                         |
                         v
                 VitalDB Observer ----> local HTTP consumer
                         ^
                         |
              Host proxy access log (optional diagnostic)
```

### 1-2. Observer가 아닌 것

| 역할 | Owner |
|---|---|
| Source Redis 데이터와 key 수명 | VitalServer / Source Redis |
| 프로세스 start/stop/restart | launchd |
| 관측 역사 저장소 | Observer는 소유하지 않음. 별도 history/read-model consumer가 구성되면 그 consumer가 저장을 소유 |
| Runtime Control / PWA | 해당 Host/Guest 서비스 |
| recorder-ingress, recovery | 해당 앱 |
| Redis를 외부에 공개하는 proxy | 하지 않음 |
| access log를 현재 서비스 가용성으로 승격 | 하지 않음. 현재 가용성은 runtime HTTP probe와 상태 계약 |

Observer는 Redis 값을 수정하지 않습니다. stdout JSONL은 운영 진단이지 관측 역사의
SoT가 아닙니다.

## 2. 실행 및 API 계약

### 2-1. 실행 방식과 bind

같은 runtime source를 console, module, Docker가 공유합니다.

| 방식 | 명령 | bind |
|---|---|---|
| Native console | `vitaldb-observer` | plist가 `127.0.0.1:18084`를 명시 |
| Module | `python -m vitaldb_observer.server` | env 없으면 `127.0.0.1:8080` |
| Docker/Compose | `python -m vitaldb_observer.server` | 이미지가 `0.0.0.0:8080`을 env로 명시 |

Native 운영 엔드포인트는 launchd example의 `http://127.0.0.1:18084`입니다. Docker
내부 프로세스는 8080을 듣고, Compose가 Host 포트를 따로 매핑합니다.

### 2-2. HTTP API

| Method | Path | 의미 | 성공 | 실패 |
|---|---|---|---|---|
| `GET` | `/health` | 프로세스 liveness. Redis 무관 | 200 `status=ok` | 프로세스가 응답하지 않으면 실패 |
| `GET` | `/ready` | Redis `AUTH` → `SELECT` → `PING` | 200 `ready=true` | 503 `ready=false` |
| `GET` | `/api/v1/observations` | 최신 계산 snapshot | 200, `ready=true` | Redis 실패 시 503 |
| 그 외 |  |  |  | 404 `error=not_found` |

OpenAPI는 [docs/api/vitaldb-observer.openapi.yaml](../api/vitaldb-observer.openapi.yaml)입니다.
이 파일은 Observer 내부 API 계약이며, Runtime Control API와 같지 않습니다.

### 2-3. 실패와 empty의 의미

| 상황 | HTTP | 문서 의미 |
|---|---|---|
| Redis 연결/AUTH/protocol 실패 | `/ready` 503, observations 503 | Redis를 읽지 못함. observations는 빈 배열과 `observer-unhealthy` |
| access log 미설정, 없음, 권한, UTF-8, 읽기 실패 | observations 200, `ready=true` | Redis snapshot은 유지. `proxyConnections=[]`와 `readIssues`가 원인을 구분 |
| access log JSON 한 줄 손상 | 200, `ready=true` | 해당 줄만 skip하고 readIssue. 나머지 줄은 유지 |
| 관련 readIssue 없이 빈 `recorders`/`beds` | 200 | 관측값이 비어 있음 |
| 관련 readIssue가 있는 빈 목록 | 200 | 관측 0이 아니라 읽기/파싱 실패 |

access log는 Redis readiness의 owner가 아닙니다. 로그의 과거 502/504를 현재
backend-unavailable로 바꾸지 않습니다.

## 3. 설정과 보안

### 3-1. CLI와 환경변수

우선순위는 CLI 명시값, 존재하는 환경변수, 문서화된 기본값입니다. 키가 없을 때만
기본값을 씁니다. 값이 `""`이거나 공백만이면 invalid이며 기본값으로 바꾸지 않습니다.

| 설정 | CLI | 환경변수 | 기본값 | 비고 |
|---|---|---|---|---|
| HTTP host | `--host` | `VITALDB_OBSERVER_HOST` | `127.0.0.1` | 비어 있으면 invalid |
| HTTP port | `--port` | `VITALDB_OBSERVER_PORT` | `8080` | 1..65535 |
| Redis host | `--redis-host` | `VITALDB_OBSERVER_REDIS_HOST` | `redis` | Docker DNS 기본값 |
| Redis port | `--redis-port` | `VITALDB_OBSERVER_REDIS_PORT` | `6379` | 1..65535 |
| Redis database | `--redis-database` | `VITALDB_OBSERVER_REDIS_DATABASE` | `0` | 0 이상 정수. 0은 유효 |
| Redis password file | `--redis-password-file` | `VITALDB_OBSERVER_REDIS_PASSWORD_FILE` | 없음 | 경로만. 값 옵션 없음 |
| access log path | `--access-log-path` | `VITALDB_OBSERVER_ACCESS_LOG_PATH` | 키 부재 시 미설정 | 명시 empty는 invalid |
| Redis timeout | 없음 | `VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS` | `2.0` | env-only, 유한 양수 |
| recorder online threshold | 없음 | `VITALDB_OBSERVER_RECORDER_ONLINE_THRESHOLD_SECONDS` | `120` | env-only, 0 이상 |
| activity window | 없음 | `VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS` | `300` | env-only, 1 이상 |
| audit Redis list | 없음 | `VITALDB_OBSERVER_AUDIT_REDIS_LIST` | `vitalserver:audit_events` | env-only |
| audit event limit | 없음 | `VITALDB_OBSERVER_AUDIT_EVENT_LIMIT` | `10000` | env-only, 1 이상 |
| access log limit | 없음 | `VITALDB_OBSERVER_ACCESS_LOG_LIMIT` | `200` | env-only, 1 이상 |

비밀번호 값 자체는 CLI, 환경변수, plist, 로그, API, 예외에 두지 않습니다.
`--redis-password`는 거절되며 인자 값을 출력하지 않습니다.

### 3-2. 값 검증

| 상태 | 결과 |
|---|---|
| env 키 부재 | 문서화된 기본값. access log는 not configured |
| 명시 empty/공백 | 기동 실패. 필드가 식별되는 설정 오류 |
| port 0 또는 65536 초과 | invalid |
| Redis database 0 | 유효. 연결마다 `SELECT 0` |
| timeout 0, inf, NaN | invalid |
| access-log-limit 0 | invalid. 전체 파일을 읽지 않음 |
| password-file 생략 | 개발 foreground no-auth. production plist는 경로를 요구 |

### 3-3. Redis credential과 AUTH

이번 범위는 Redis 3.2 password-only AUTH입니다. username/ACL과 TLS는 지원하지 않습니다.

| 규칙 | 의미 |
|---|---|
| 전달 방식 | file path만 |
| 읽기 | 프로세스 시작 시 1회. 요청마다 다시 읽지 않음 |
| 파일 형식 | strict UTF-8. 마지막 LF 또는 CRLF 한 개만 제거 |
| missing / 읽기 실패 / invalid path / invalid UTF-8 / empty | 서로 다른 기동 실패 |
| 연결 순서 | `AUTH` → `SELECT` → 실제 command. database 0도 SELECT |
| AUTH 거절 | `Redis authentication failed`. 서버 원문과 비밀번호를 반사하지 않음 |
| 변경 적용 | secret rotate 후 daemon restart |

production launchd example은 password file을 요구하는 보안 기본선입니다. no-auth는
개발에서 `--redis-password-file`을 명시적으로 생략한 경우에만 가능합니다. Source Redis는
Host loopback에서만 접근하고 외부에 공개하지 않습니다.

## 4. macOS Native 설치

### 4-1. 경로와 권한

아래 표는 launchd example 기준입니다. plist는 검토용 example이며 설치 스크립트가
아닙니다.

| Path | 생성자 | Owner | Mode | 역할 |
|---|---|---|---|---|
| `/usr/local/libexec/vitaldb-observer` | operator | `root:wheel` | `0755` | venv parent |
| `/usr/local/libexec/vitaldb-observer/venv` | `uv venv` | root | venv default | system venv |
| `/usr/local/etc/vitaldb-observer` | operator | `root:wheel` | `0755` | config parent |
| `/usr/local/etc/vitaldb-observer/secrets` | operator | `_vitaldb-observer:wheel` | `0700` | secret parent |
| `/usr/local/etc/vitaldb-observer/secrets/redis-password` | operator | `_vitaldb-observer:wheel` | `0600` | Redis password file |
| `/Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist` | operator | `root:wheel` | `0644` | launchd definition |
| `/usr/local/var/log/vitalserver` | operator | `root:wheel` | `0755` | shared log parent |
| `/usr/local/var/log/vitalserver/vitaldb-observer.out.log` | operator | `_vitaldb-observer:wheel` | `0640` | stdout |
| `/usr/local/var/log/vitalserver/vitaldb-observer.err.log` | operator | `_vitaldb-observer:wheel` | `0640` | stderr |
| Host proxy access log | proxy/nginx | proxy owner | 환경에 따름 | Observer 소유 아님. 읽기만 |

로그 parent를 한 서비스 사용자 `0755`로 두면 다른 daemon이 파일을 만들지 못합니다.
shared parent는 `root:wheel 0755`로 두고, Observer 로그 파일은 미리 만들어 서비스
사용자가 parent에 쓸 필요가 없게 합니다.

### 4-2. 서비스 계정

`_vitaldb-observer`는 설치 전에 존재해야 합니다. 이 저장소는 installer나 계정
provisioning을 제공하지 않습니다.

```sh
id _vitaldb-observer
```

계정이 없으면 조직의 provisioning, MDM, installer가 생성합니다. 요구 속성은 로컬
hidden/non-login 계정, shell `/usr/bin/false`, home `/var/empty`, 미사용 UniqueID입니다.
primary group은 조직 정책에 따릅니다. 전용 `_vitaldb-observer` group은 요구하지 않으며,
secret과 로그 파일의 group은 `wheel`입니다. 고정 UID/GID `dscl` recipe는 환경마다
충돌하므로 이 문서에 넣지 않습니다.

### 4-3. 설치 절차

아래 명령은 `_vitaldb-observer`가 이미 있다는 전제입니다. secret 값은 command line,
`echo`, heredoc에 쓰지 않습니다. 디렉터리 `install -d`는 기존 파일을 건드리지 않습니다.
secret과 로그 파일은 `touch`로만 만들고, 이미 있으면 내용을 보존합니다. 이 절차를
다시 실행해도 기존 credential과 로그를 지우지 않습니다.

```sh
uv build --package tirosh-vitaldb-observer --wheel

sudo install -d -m 0755 /usr/local/libexec/vitaldb-observer
sudo install -d -m 0755 /usr/local/etc/vitaldb-observer
sudo install -d -o _vitaldb-observer -g wheel -m 0700 \
  /usr/local/etc/vitaldb-observer/secrets
sudo install -d -o root -g wheel -m 0755 /usr/local/var/log/vitalserver

sudo touch /usr/local/etc/vitaldb-observer/secrets/redis-password
sudo chown _vitaldb-observer:wheel \
  /usr/local/etc/vitaldb-observer/secrets/redis-password
sudo chmod 0600 /usr/local/etc/vitaldb-observer/secrets/redis-password

sudo touch /usr/local/var/log/vitalserver/vitaldb-observer.out.log
sudo chown _vitaldb-observer:wheel \
  /usr/local/var/log/vitalserver/vitaldb-observer.out.log
sudo chmod 0640 /usr/local/var/log/vitalserver/vitaldb-observer.out.log

sudo touch /usr/local/var/log/vitalserver/vitaldb-observer.err.log
sudo chown _vitaldb-observer:wheel \
  /usr/local/var/log/vitalserver/vitaldb-observer.err.log
sudo chmod 0640 /usr/local/var/log/vitalserver/vitaldb-observer.err.log

sudo uv venv /usr/local/libexec/vitaldb-observer/venv
sudo uv pip install --python /usr/local/libexec/vitaldb-observer/venv/bin/python --no-deps \
  dist/tirosh_vitaldb_observer-0.2.0-py3-none-any.whl
```

이어서 조직의 secret provisioning tool로
`/usr/local/etc/vitaldb-observer/secrets/redis-password`에 실제 값을 기록합니다.
값 자체는 이 문서의 명령에 포함하지 않습니다.

credential preflight가 성공하기 전에는 foreground smoke와 launchd bootstrap을 하지
않습니다. KeepAlive 상태에서 빈 파일은 명시적 empty credential 오류로 재시작 루프가
됩니다. 아래 확인은 성공/실패만 보고, 파일 내용이나 크기를 출력하지 않습니다.

```sh
sudo -u _vitaldb-observer test -r \
  /usr/local/etc/vitaldb-observer/secrets/redis-password
sudo -u _vitaldb-observer test -s \
  /usr/local/etc/vitaldb-observer/secrets/redis-password
```

preflight가 성공한 뒤에 plist를 등록합니다.

```sh
sudo cp apps/vitaldb-observer/packaging/macos/ai.tirosh.vitaldb-observer.plist \
  /Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist
sudo chown root:wheel /Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist
sudo chmod 0644 /Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist
sudo plutil -lint /Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist
```

### 4-4. Access log와 Redis 전제

```sh
sudo -u _vitaldb-observer test -r \
  "/Library/Application Support/VitalServerHelper/logs/runtime/proxy-nginx.access.log"
```

읽기 권한이 없으면 Observer 프로세스 전체가 죽지 않습니다. observations는 200,
`ready=true`를 유지하고 `proxyConnections=[]`와 readIssue로 원인을 남깁니다. 권한
부여 방법은 proxy owner와 설치 환경에 따르므로 world-readable chmod를 기본 처방으로
쓰지 않습니다.

Native Observer의 Redis는 Host Source Redis `127.0.0.1:6379`입니다. Redis가
container 내부에만 expose되어 Host loopback에 없으면 `/ready`는 503입니다. Source
Redis를 외부에 publish하지 마십시오.

### 4-5. Foreground smoke

credential preflight가 성공한 뒤에만, launchd 등록 전 같은 사용자와 plist와 같은
인자로 한 번 실행합니다. 18084에 기존 listener가 있으면 bind가 실패합니다. listener가
없을 때는 출력이 없는 것이 기대 상태입니다.

```sh
sudo -u _vitaldb-observer \
  /usr/local/libexec/vitaldb-observer/venv/bin/vitaldb-observer \
  --host 127.0.0.1 \
  --port 18084 \
  --redis-host 127.0.0.1 \
  --redis-port 6379 \
  --redis-database 0 \
  --redis-password-file /usr/local/etc/vitaldb-observer/secrets/redis-password \
  --access-log-path \
  "/Library/Application Support/VitalServerHelper/logs/runtime/proxy-nginx.access.log"
```

다른 터미널에서 HTTP status와 body를 함께 확인합니다. 본문만 보고 503을 성공으로
보지 않습니다.

```sh
curl -sS -i http://127.0.0.1:18084/health
curl -sS -i http://127.0.0.1:18084/ready
curl -sS -i http://127.0.0.1:18084/api/v1/observations
```

Ctrl-C 또는 SIGTERM으로 종료되면 foreground 계약입니다. 명령에는 비밀번호 값이 아니라
file path만 넣습니다. access log를 읽지 못하면 observations는 200과 readIssue로
남고, 그것이 Redis 실패는 아닙니다.

## 5. 운영과 장애 대응

### 5-1. 생명주기

```sh
sudo launchctl print system/ai.tirosh.vitaldb-observer
sudo launchctl kickstart -k system/ai.tirosh.vitaldb-observer
sudo launchctl bootout system/ai.tirosh.vitaldb-observer
```

plist를 바꾼 뒤에는 bootout 후 같은 파일을 bootstrap합니다. Redis password file을
바꾼 뒤에도 kickstart/restart가 필요합니다. 시작 시 1회만 읽기 때문입니다.

제거는 launchd 등록 해제와 설치 파일 삭제를 나눕니다. secret과 로그 삭제는 운영자가
명시적으로 선택합니다. 광범위한 `rm -rf` 예시는 제공하지 않습니다.

```sh
sudo launchctl bootout system/ai.tirosh.vitaldb-observer
sudo rm /Library/LaunchDaemons/ai.tirosh.vitaldb-observer.plist
```

venv와 secret 경로는 별도 판단 후 삭제합니다.

### 5-2. 상태와 로그

```sh
curl -sS -i http://127.0.0.1:18084/health
curl -sS -i http://127.0.0.1:18084/ready
curl -sS -i http://127.0.0.1:18084/api/v1/observations
tail -n 100 /usr/local/var/log/vitalserver/vitaldb-observer.out.log
tail -n 100 /usr/local/var/log/vitalserver/vitaldb-observer.err.log
```

| Event | 의미 |
|---|---|
| `server_started` | HTTP server가 기동함 |
| `readiness_failed` | `/ready`가 Redis 예외로 503 |
| `observation_collected` | `/api/v1/observations`가 snapshot을 반환 |
| `observation_failed` | observations가 unhealthy snapshot을 반환 |

이 이벤트는 diagnostics입니다. 관측 역사 SoT로 쓰지 않습니다.

### 5-3. 장애 판단

| 증상 | 의미/원인 | 확인 | 조치 방향 | 예방 |
|---|---|---|---|---|
| launchd가 즉시 재시작을 반복 | 설정/credential/bind 실패로 프로세스가 바로 종료. 빈 password file이면 empty credential 오류 | `launchctl print`, stderr | 설정 오류와 Redis/port를 구분한 뒤 고치고 kickstart | bootstrap 전 `test -r`/`test -s`와 foreground smoke |
| 기동 직후 종료, `is empty`/`is invalid` | 명시된 env/CLI 값이 비었거나 범위 밖 | stderr 한 줄 | 빈 문자열을 지우고 유효 값을 명시 | missing만 default로 둔다 |
| `redis-password-file is missing/read failed/not valid UTF-8/empty` | credential file 상태 | 경로, owner `0600`, UTF-8 | 파일을 고친 뒤 restart. no-auth로 바꾸지 않음 | secret provisioning을 파일 경로로만 |
| `Redis authentication failed` | AUTH 거절 | Redis requirepass와 file 내용이 일치하는지 운영 절차로 확인 | 값을 로그에 찍지 말고 file을 교체 후 restart | password를 CLI/plist에 넣지 않음 |
| `/ready` 503, connection refused | Host `127.0.0.1:6379`에 Redis 없음 | `curl /ready`, Redis listener | Host Source Redis를 loopback에 두기. 외부 publish 금지 | native 전제를 설치 전에 확인 |
| observations 200, `proxyConnections=[]`, readIssue | access log 읽기 문제. Redis는 성공 | `readIssues`, `test -r` | Redis snapshot을 버리지 말고 log 권한/경로를 고침 | 서비스 사용자 읽기 권한을 설치 시 검증 |
| access log not readable / not valid UTF-8 | permission 또는 decode 실패 | readIssue 메시지 | world-readable로 숨기지 말고 owner/ACL을 맞춤 | UTF-8 JSONL 유지 |
| `18084` already in use | 다른 프로세스가 native port를 점유 | `lsof -nP -iTCP:18084` | 점유 프로세스를 정리하거나 중복 등록을 제거 | bootstrap 전 smoke |
| secret을 바꿨는데 이전 AUTH가 유지 | 시작 시 1회 읽기 | 파일 mtime과 restart 시각 | kickstart/restart | rotate 절차에 restart를 포함 |

실패를 disabled나 빈 성공으로 해석하지 않습니다.

## 6. 개발 및 기존 환경 호환

### 6-1. 개발 확인

Python 3.12 이상, runtime dependency 없음.

```sh
uv build --package tirosh-vitaldb-observer --wheel
uv venv .venv-vitaldb-observer
uv pip install --python .venv-vitaldb-observer/bin/python --no-deps \
  dist/tirosh_vitaldb_observer-0.2.0-py3-none-any.whl
.venv-vitaldb-observer/bin/vitaldb-observer --help
.venv-vitaldb-observer/bin/python -m vitaldb_observer.server --help

.venv/bin/python -m pytest apps/vitaldb-observer/tests
.venv/bin/ruff check apps/vitaldb-observer
.venv/bin/ruff format --check apps/vitaldb-observer
.venv/bin/python -m mypy apps/vitaldb-observer
uv lock --check
```

`.venv-vitaldb-observer`는 개발 확인용입니다. launchd는 system venv만 사용합니다.

### 6-2. Docker/Compose

Docker와 Native는 다른 구현이 아닙니다. 같은 `apps/vitaldb-observer` runtime입니다.
Dockerfile CMD와 Compose healthcheck는 `python -m vitaldb_observer.server`와 `/ready`를
유지합니다. Compose가 이미 넣는 env를 Native plist 기본값으로 바꾸지 않습니다.

### 6-3. 범위 밖과 관련 문서

Linux systemd, Windows service, macOS PKG/DMG, GitHub Actions, signing/notarization,
PyPI publish는 이 문서 범위 밖입니다.

| 문서 | 역할 |
|---|---|
| [앱 README](../../apps/vitaldb-observer/README.md) | 개발 진입점 |
| [Observer OpenAPI](../api/vitaldb-observer.openapi.yaml) | 내부 HTTP 계약 |
| [Redis key model](../recorder/redis-key-model.md) | Source Redis key 의미 |
| [Redis Relay](../redis-relay/index.md) | Source Redis를 외부에 직접 열지 않는 relay |
| [문서 지도](../index.md) | 저장소 문서 진입 |
