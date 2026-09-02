# Redis Relay 운영 가이드

이 문서는 Redis Relay wheel을 Native Host에 설치하고 launchd 또는 systemd로 운영하는 절차와,
기존 VM/Container 실행의 상태 연결 방식을 설명합니다. 앱은 foreground 단일 프로세스로만
동작하며 process lifetime과 restart는 supervisor가 소유합니다.

## 1. 지원 범위와 전제조건

### 1-1. 지원 환경

| 환경 | 설치/실행 | Process owner | 상태 출력 |
|---|---|---|---|
| macOS Native | wheel + system venv | launchd | JSON file |
| Linux Native | wheel + system venv | systemd | JSON file |
| VM Guest | 기존 image/Compose | Guest supervisor | file + HTTP owner |
| Linux Container | 기존 image/Compose | Container supervisor | file + Unix socket owner |

Windows Native Service, PyPI publish, signing/notarization, 제품 PKG/installer 자동 연결은 현재
범위 밖입니다. 제공되는 plist와 systemd unit은 operator가 명시적으로 설치하는 예제입니다.

### 1-2. 실행 조건

- Python 3.12 이상
- 실행 환경에서 접근 가능한 Source와 Target Redis
- 전용 서비스 사용자
- 설정, secret, status 디렉터리
- Target production 환경에서는 Redis ACL과 TLS 권장

## 2. Wheel build와 개발 확인

### 2-1. Wheel build

저장소 root에서 실행합니다.

```sh
uv build --package tirosh-vitalserver-redis-relay --wheel
```

Package 이름은 `tirosh-vitalserver-redis-relay`이고 현재 runtime line version은 `0.2.0`입니다.
Runtime dependency 없이 Python 표준 라이브러리만 사용합니다.

### 2-2. Development venv

Repository-local venv는 command와 wheel을 확인하는 용도입니다. launchd와 systemd가 이 경로를
사용하면 안 됩니다.

```sh
uv venv .venv-redis-relay
uv pip install --python .venv-redis-relay/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
.venv-redis-relay/bin/vitalserver-redis-relay --help
.venv-redis-relay/bin/python -m vitalserver_redis_relay --help
```

### 2-3. System executable 계약

| OS | system venv | supervisor executable |
|---|---|---|
| macOS | `/usr/local/libexec/vitalserver-redis-relay/venv` | `/usr/local/libexec/vitalserver-redis-relay/venv/bin/vitalserver-redis-relay` |
| Linux | `/opt/vitalserver/redis-relay/venv` | `/opt/vitalserver/redis-relay/venv/bin/vitalserver-redis-relay` |

## 3. Native Host 설치

### 3-1. macOS Native

**파일과 권한**

먼저 `_vitalserver-redis-relay` 전용 사용자를 생성합니다. 사용자 생성은 operator의 책임입니다.

| Path | 생성자 | Owner | Mode | 역할 |
|---|---|---|---|---|
| `/usr/local/libexec/vitalserver-redis-relay` | operator | root | `0755` | venv parent |
| `/usr/local/libexec/vitalserver-redis-relay/venv` | `uv venv` | root | venv default | system venv |
| `/usr/local/etc/vitalserver` | operator | root | `0755` | config parent |
| `/usr/local/etc/vitalserver/redis-relay.toml` | operator | `root:_vitalserver-redis-relay` | `0640` | config |
| `/Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist` | operator | `root:wheel` | `0644` | launchd definition |
| `/usr/local/etc/vitalserver/secrets` | operator | `_vitalserver-redis-relay` | `0750` | secret parent |
| `/usr/local/etc/vitalserver/secrets/redis-relay-target-username` | operator | `_vitalserver-redis-relay` | `0600` | Target username |
| `/usr/local/etc/vitalserver/secrets/redis-relay-target-password` | operator | `_vitalserver-redis-relay` | `0600` | Target password |
| `/usr/local/var/vitalserver` | operator | `_vitalserver-redis-relay` | `0755` | status parent |
| `/usr/local/var/vitalserver/redis-relay-status.json` | Relay | `_vitalserver-redis-relay` | runtime-created | status |
| `/usr/local/var/log/vitalserver` | operator | `_vitalserver-redis-relay` | `0755` | log parent |

**설치**

아래 명령은 이미 전용 사용자가 존재한다는 전제입니다. Secret 값은 command line에 쓰지 말고
해당 파일에 안전하게 입력합니다.

```sh
sudo install -d -m 0755 /usr/local/libexec/vitalserver-redis-relay
sudo install -d -m 0755 /usr/local/etc/vitalserver
sudo install -d -o _vitalserver-redis-relay -g _vitalserver-redis-relay -m 0750 \
  /usr/local/etc/vitalserver/secrets
sudo install -d -o _vitalserver-redis-relay -g _vitalserver-redis-relay -m 0755 \
  /usr/local/var/vitalserver /usr/local/var/log/vitalserver
sudo uv venv /usr/local/libexec/vitalserver-redis-relay/venv
sudo uv pip install --python /usr/local/libexec/vitalserver-redis-relay/venv/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
sudo cp apps/vitalserver-redis-relay/packaging/macos/native-redis-relay.example.toml \
  /usr/local/etc/vitalserver/redis-relay.toml
sudo chown root:_vitalserver-redis-relay /usr/local/etc/vitalserver/redis-relay.toml
sudo chmod 0640 /usr/local/etc/vitalserver/redis-relay.toml
# Secret 파일에 값을 기록한 다음 permission을 설정합니다.
sudo chown _vitalserver-redis-relay:_vitalserver-redis-relay \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-username \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-password
sudo chmod 0600 \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-username \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-password
```

**Foreground 확인**

launchd에 등록하기 전에 같은 사용자와 executable로 실행합니다.

```sh
sudo -u _vitalserver-redis-relay \
  /usr/local/libexec/vitalserver-redis-relay/venv/bin/vitalserver-redis-relay \
  --config-path /usr/local/etc/vitalserver/redis-relay.toml \
  --status-path /usr/local/var/vitalserver/redis-relay-status.json
```

**launchd 등록**

```sh
sudo cp apps/vitalserver-redis-relay/packaging/macos/ai.tirosh.vitalserver.redis-relay.plist \
  /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
sudo chown root:wheel /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
sudo chmod 0644 /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
```

중지와 재시작은 launchd가 소유합니다.

```sh
sudo launchctl bootout system/ai.tirosh.vitalserver.redis-relay
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
python -c 'import json; print(json.load(open("/usr/local/var/vitalserver/redis-relay-status.json"))["state"])'
```

### 3-2. Linux Native

**파일과 권한**

먼저 `vitalserver-redis-relay` 전용 사용자를 생성합니다.

| Path | 생성자 | Owner | Mode | 역할 |
|---|---|---|---|---|
| `/opt/vitalserver/redis-relay` | operator | root | `0755` | venv parent |
| `/opt/vitalserver/redis-relay/venv` | `uv venv` | root | venv default | system venv |
| `/etc/vitalserver` | operator | root | `0755` | config parent |
| `/etc/vitalserver/redis-relay.toml` | operator | `root:vitalserver-redis-relay` | `0640` | config |
| `/etc/systemd/system/vitalserver-redis-relay.service` | operator | `root:root` | `0644` | systemd unit |
| `/etc/vitalserver/secrets` | operator | `vitalserver-redis-relay` | `0750` | secret parent |
| `/etc/vitalserver/secrets/redis-relay-target-username` | operator | `vitalserver-redis-relay` | `0600` | Target username |
| `/etc/vitalserver/secrets/redis-relay-target-password` | operator | `vitalserver-redis-relay` | `0600` | Target password |
| `/var/lib/vitalserver/redis-relay` | operator | `vitalserver-redis-relay` | `0755` | status parent |
| `/var/lib/vitalserver/redis-relay/status.json` | Relay | `vitalserver-redis-relay` | runtime-created | status |

**설치**

```sh
sudo install -d -m 0755 /opt/vitalserver/redis-relay /etc/vitalserver
sudo install -d -o vitalserver-redis-relay -g vitalserver-redis-relay -m 0750 \
  /etc/vitalserver/secrets
sudo install -d -o vitalserver-redis-relay -g vitalserver-redis-relay -m 0755 \
  /var/lib/vitalserver/redis-relay
sudo uv venv /opt/vitalserver/redis-relay/venv
sudo uv pip install --python /opt/vitalserver/redis-relay/venv/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
sudo cp apps/vitalserver-redis-relay/packaging/linux/native-redis-relay.example.toml \
  /etc/vitalserver/redis-relay.toml
sudo chown root:vitalserver-redis-relay /etc/vitalserver/redis-relay.toml
sudo chmod 0640 /etc/vitalserver/redis-relay.toml
# Secret 파일에 값을 기록한 다음 permission을 설정합니다.
sudo chown vitalserver-redis-relay:vitalserver-redis-relay \
  /etc/vitalserver/secrets/redis-relay-target-username \
  /etc/vitalserver/secrets/redis-relay-target-password
sudo chmod 0600 \
  /etc/vitalserver/secrets/redis-relay-target-username \
  /etc/vitalserver/secrets/redis-relay-target-password
```

**Foreground 확인**

```sh
sudo -u vitalserver-redis-relay \
  /opt/vitalserver/redis-relay/venv/bin/vitalserver-redis-relay \
  --config-path /etc/vitalserver/redis-relay.toml \
  --status-path /var/lib/vitalserver/redis-relay/status.json
```

**systemd 등록**

```sh
sudo cp apps/vitalserver-redis-relay/packaging/linux/vitalserver-redis-relay.service \
  /etc/systemd/system/vitalserver-redis-relay.service
sudo chown root:root /etc/systemd/system/vitalserver-redis-relay.service
sudo chmod 0644 /etc/systemd/system/vitalserver-redis-relay.service
sudo systemctl daemon-reload
sudo systemctl enable --now vitalserver-redis-relay.service
```

```sh
sudo systemctl stop vitalserver-redis-relay.service
sudo systemctl restart vitalserver-redis-relay.service
python -c 'import json; print(json.load(open("/var/lib/vitalserver/redis-relay/status.json"))["state"])'
```

## 4. Runtime과 process lifecycle

### 4-1. VM과 Container 실행

기존 Docker/VM runtime은 `python -m vitalserver_redis_relay`를 유지합니다. Native와 같은 config,
filter, Protocol v1 코드를 사용하고 status owner adapter만 다르게 조립합니다.

| Runtime | Status output | 선택 입력 |
|---|---|---|
| Native Host | JSON file | owner URL/socket을 지정하지 않음 |
| VM Guest | file + HTTP `PUT /runtime/redis-relay/status` | `REDIS_RELAY_STATUS_OWNER_URL` |
| Linux Container | file + HTTP-over-Unix-socket PUT | `REDIS_RELAY_STATUS_OWNER_SOCKET` |

Owner URL과 socket을 동시에 지정하면 시작 오류입니다. Relay는 OS나 runtime mode를 감지해
adapter를 추측하지 않습니다.

### 4-2. Process lifecycle

Relay는 foreground 단일 프로세스입니다. daemonize, pidfile, 자체 restart manager가 없습니다.
launchd는 `RunAtLoad`와 `KeepAlive`, systemd는 `Type=simple`과 `Restart=on-failure`로 lifetime을
소유합니다. CLI의 주요 입력은 다음과 같습니다.

| CLI | 환경변수 | 기본값 |
|---|---|---|
| `--config-path` | `REDIS_RELAY_CONFIG_PATH` | `/run/tirosh/config/redis-relay.toml` |
| `--status-path` | `REDIS_RELAY_STATUS_PATH` | `/run/tirosh/status/redis-relay-status.json` |
| `--status-owner-url` | `REDIS_RELAY_STATUS_OWNER_URL` | 없음 |
| `--status-owner-socket` | `REDIS_RELAY_STATUS_OWNER_SOCKET` | 없음 |

CLI와 환경변수에는 credential 값이 들어가지 않습니다.

## 5. 관측과 운영 작업

### 5-1. Status publisher

File publisher는 항상 구성되며 같은 디렉터리의 임시 파일에 완전한 JSON을 쓴 뒤 `fsync`와
atomic replace를 수행합니다. HTTP 또는 Unix socket owner publisher는 명시된 경우에만 추가됩니다.

구성된 publisher 중 하나 이상 성공하면 relay loop를 계속하고 실패 adapter를 stderr에 기록합니다.
모든 publisher가 실패하면 process가 비정상 종료되어 supervisor가 재시작할 수 있게 합니다.

### 5-2. Relay state

| `state` | 의미 |
|---|---|
| `config_invalid` | 설정 부재, read/decode/contract 또는 credential 오류 |
| `disabled` | 유효한 설정의 `enabled = false` |
| `running` | 최근 batch가 오류 없이 완료됨 |
| `running_with_errors` | 최근 batch가 일부 key 오류와 함께 완료됨 |
| `relay_failed` | batch를 시작하거나 Redis session을 구성하는 작업이 실패함 |

### 5-3. Status 주요 필드

| 필드 | 의미 |
|---|---|
| `schemaVersion` | Status schema. 현재 `1` |
| `observedAt` | 문서 생성 시각 |
| `enabled`, `state` | 설정 활성화와 실행 상태 |
| `scope` | 적용된 key scope |
| `targetUrl` | user-info가 제거된 Target endpoint |
| `targetUsernameConfigured` | username 존재 여부 |
| `targetPasswordConfigured` | password 존재 여부 |
| `settingsFingerprint` | 비밀값을 제외한 설정 identity |
| `batches`, `totals`, `lastBatch` | scan/publish 누적 및 최근 batch counter |
| `lastSuccessAt` | 오류 없는 최근 batch 완료 시각 |
| `lastErrorAt`, `lastError` | 최근 실패 시각과 요약 |
| `lastErrorSamples` | 최근 batch의 bounded key/stage/code/message sample |

`settingsFingerprint`에는 host, port, database, TLS, credential configured boolean, scope와
publish contract가 들어갑니다. Credential 값 자체는 들어가지 않으므로 password rotation만으로는
fingerprint가 바뀌지 않습니다.

### 5-4. Publish error code

| Code | Stage | 의미 |
|---|---|---|
| `source_dump_failed` | `source_dump` | Source key metadata 또는 `DUMP` 실패 |
| `target_publish_failed` | `target_publish` | Target atomic publish 실패 |

### 5-5. 반복 운영 작업

**Credential rotation**

1. 같은 secret directory에 새 임시 파일을 생성합니다.
2. 서비스 사용자 ownership과 `0600` mode를 적용합니다.
3. 기존 contract path로 atomic replace합니다.
4. 다음 loop 뒤 status의 `lastSuccessAt`과 오류 상태를 확인합니다.

Credential 원문을 shell history, ticket, log 또는 확인 command 출력에 남기지 않습니다. Relay는
loop마다 파일을 다시 읽으므로 정상적인 file replace에는 process restart가 필요하지 않습니다.

**Wheel update**

1. 새 wheel과 version을 확인합니다.
2. 기존 TOML과 secret file을 별도로 보존합니다.
3. 새 system venv를 staging path에 만들고 `--no-deps`로 wheel을 설치합니다.
4. console `--help`와 foreground disabled smoke를 확인합니다.
5. supervisor executable이 가리키는 venv를 명시적으로 전환합니다.
6. 서비스를 재시작하고 status와 Target event를 확인합니다.

기존 venv를 즉시 삭제하지 않아야 rollback할 수 있습니다. 현재 repository는 이 절차를 자동화한
Native installer나 release transaction을 제공하지 않으므로 operator가 교체와 rollback을 소유합니다.

**제거**

1. launchd 또는 systemd에서 서비스를 중지하고 definition을 제거합니다.
2. system venv를 제거합니다.
3. status와 log의 보존 정책을 결정합니다.
4. TOML과 credential file은 보존 또는 파기를 명시적으로 선택합니다.

Credential과 설정을 자동으로 남기거나 지우지 않습니다. 제거 대상과 보존 정책이 확정된 뒤
operator가 실행합니다.

## 6. 장애 판단과 점검

### 6-1. 장애 판단 기준

| 증상 | 먼저 확인할 상태 | 방향 |
|---|---|---|
| Status가 생성되지 않음 | supervisor stderr, status parent permission | File publisher 실패 해결 |
| `config_invalid` | `lastError` | missing/read/UTF-8/TOML/field/credential 오류를 구분 |
| `relay_failed` | Source/Target endpoint와 인증 | session 또는 batch 시작 실패 해결 |
| `running_with_errors` | `lastErrorSamples[].code` | Source dump와 Target publish를 분리 |
| Target event가 멈춤 | `lastSuccessAt`, batch counters | unchanged인지 연결 실패인지 구분 |
| 설정과 실행 endpoint 불일치 | `settingsFingerprint`, redacted Target 필드 | owner 설정과 Relay 소비 상태 비교 |

Target 연결 장애가 container liveness 실패로 숨겨지지 않도록 status를 확인합니다. 장시간 Target
장애 뒤 Source에서 만료된 key는 Relay로 복구할 수 없습니다.

### 6-2. 운영 점검표

**설치 전**

- Source Redis가 외부가 아닌 local/private 주소에 있는가
- Relay 전용 사용자와 디렉터리를 만들었는가
- TOML에 credential 값이나 URL user-info가 없는가
- Secret file owner와 permission이 올바른가
- Target TLS/ACL policy를 검토했는가

**시작 후**

- Supervisor가 정확한 system venv executable을 시작했는가
- Status가 `running` 또는 의도한 `disabled`인가
- `targetUrl`에 user-info가 없는가
- `targetUsernameConfigured`와 `targetPasswordConfigured`가 기대와 같은가
- Target key와 `key_published` event가 함께 생성되는가

**업데이트 후**

- 기존 config와 credential이 보존되었는가
- `settingsFingerprint` 변경이 의도한 비밀이 아닌 설정 변경과 일치하는가
- 최근 batch와 Target consumer 처리가 정상인가
- 이전 venv로 rollback할 수 있는가

### 6-3. 관련 Troubleshooting

- [TS-088: Redis Relay가 package bundle에서 누락됨](../troubleshooting/088_redis-relay-missing-from-package-bundle.md)
- [TS-193: Legacy URL username migration 실패](../troubleshooting/193_redis-relay-legacy-url-username-migration.md)
- [Troubleshooting 전체 목록](../troubleshooting/index.md)
