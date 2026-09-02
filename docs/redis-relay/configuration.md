# Redis Relay 설정과 보안

이 문서는 Redis Relay가 소비하는 TOML과 credential file 계약의 기준입니다. 설정을 쓰는
Native operator와 Runtime Control은 이 계약을 제공하고, Relay는 이를 읽어 검증합니다.
설정 누락이나 실패를 disabled 또는 no-auth로 바꾸지 않습니다.

## 1. 설정 원칙

### 1-1. 명시적인 상태

| 상태 | 의미 | Relay 동작 |
|---|---|---|
| config missing | 설정 파일이 없음 | `config_invalid`, 연결하지 않음 |
| config unreadable | 파일 접근 실패 | `config_invalid`, 연결하지 않음 |
| config invalid | UTF-8, TOML 또는 필드 계약 오류 | `config_invalid`, 연결하지 않음 |
| disabled | `redis_relay.enabled = false` | credential을 읽거나 Redis에 연결하지 않음 |
| enabled | 유효한 Source, Target, credential 제공 | relay loop 실행 |

`enabled` 필드는 필수입니다. 설정 파일이 없거나 `enabled`가 빠진 상태는 disabled가
아닙니다. 명시적인 `enabled = false`만 disabled입니다.

### 1-2. 설정과 credential 소유권

Native 환경에서는 operator가 TOML과 secret file을 소유합니다. Guest/Container 환경에서는
Runtime Control의 설정 repository가 이 파일을 소유합니다. Relay는 consumer이므로 파일을
생성하거나 credential 값을 보정하지 않습니다.

TOML에는 credential 값이 아니라 `username_file`, `password_file` path만 기록합니다. CLI와
환경변수도 Redis credential 전달 수단으로 사용하지 않습니다.

## 2. 연결 및 실행 설정

### 2-1. 전체 설정 예제

```toml
[redis_relay]
enabled = true
scope = "vital_reconstruction"
include_recorder_network_context = false
interval_seconds = 1.0
scan_count = 1000
status_interval_seconds = 5.0

[source]
host = "127.0.0.1"
port = 6379
database = 0
# password_file = "/path/to/redis-relay-source-password"

[target]
url = "rediss://redis.example:6380/2"
username_file = "/path/to/redis-relay-target-username"
password_file = "/path/to/redis-relay-target-password"

[publish]
target_key_prefix = "vitalserver:"
event_stream_key = "vitalserver:relay:events"
fingerprint_hash_key = "vitalserver:relay:fingerprints"
publish_dedupe_hash_key = "vitalserver:relay:published"
event_stream_maxlen = 100000
publisher_id = "vitalserver-helper-relay"
```

운영 예제 파일은 다음 위치에 있습니다.

- macOS: `apps/vitalserver-redis-relay/packaging/macos/native-redis-relay.example.toml`
- Linux: `apps/vitalserver-redis-relay/packaging/linux/native-redis-relay.example.toml`

### 2-2. Relay 실행 제어

| 필드 | 필수 | 기본값 | 계약 |
|---|---:|---:|---|
| `enabled` | 예 | 없음 | boolean. `false`만 disabled |
| `scope` | 아니요 | `vital_reconstruction` | 정의된 scope 이름만 허용 |
| `include_recorder_network_context` | 아니요 | `false` | recorder network context 추가 여부 |
| `interval_seconds` | 아니요 | `1.0` | finite number, 최소 `0.1` |
| `scan_count` | 아니요 | `1000` | integer, 최소 `1` |
| `status_interval_seconds` | 아니요 | `5.0` | disabled 상태 기록 간격, 최소 `0.5` |

`true`와 `false`는 숫자로 취급하지 않습니다. `NaN`과 infinity도 interval로 허용하지
않습니다.

### 2-3. Source Redis

Relay가 활성화되면 `[source]`와 비어 있지 않은 `source.host`가 필수입니다.

| 필드 | 필수 | 기본값 | 계약 |
|---|---:|---:|---|
| `host` | 예 | 없음 | Source Redis host |
| `port` | 아니요 | `6379` | `1..65535` |
| `database` | 아니요 | `0` | `0` 이상 |
| `tls` | 아니요 | `false` | TLS 연결 여부 |
| `password_file` | 아니요 | 없음 | Redis 3.2 password-only AUTH 파일 |

Source에는 `username`, `username_file`, TOML `password` 값을 사용할 수 없습니다. 현재
Source Redis 3.2 계약은 password-only AUTH만 지원합니다.

### 2-4. Target Redis

Relay가 활성화되면 `target.url`이 필수입니다.

| 필드 | 필수 | 계약 |
|---|---:|---|
| `url` | 예 | `redis://host:port/db` 또는 `rediss://host:port/db` |
| `username_file` | 아니요 | Target ACL username file |
| `password_file` | 아니요 | Target password file |

**Target URL 계약**

URL에는 scheme, host, port, database만 둡니다.

```text
redis://192.168.64.1:16381/0
redis://redis.example:6379/0
rediss://redis.example:6380/2
```

다음 값은 허용하지 않습니다.

- username, password 또는 다른 user-info
- query, params, fragment
- 빈 port, `0`, `65535`를 초과한 port
- 정수가 아니거나 음수인 database
- `redis`, `rediss` 이외의 scheme

오류 메시지는 입력 URL이나 credential 원문을 반사하지 않습니다.

**Target AUTH 조합**

| Username file | Password file | 결과 |
|---|---|---|
| 없음 | 없음 | no-auth. 개발 호환용이며 운영 환경에는 권장하지 않음 |
| 없음 | 있음 | password-only AUTH |
| 있음 | 있음 | ACL username/password AUTH |
| 있음 | 없음 | 설정 오류 |

운영 Target Redis에는 `rediss`와 ACL credential 사용을 권장합니다.

## 3. Publish 및 key filter

### 3-1. Publish 설정

| 필드 | 기본값 | 의미 |
|---|---|---|
| `target_key_prefix` | `vitalserver:` | 복제 key prefix. 빈 문자열도 명시적으로 허용 |
| `event_stream_key` | `vitalserver:relay:events` | Protocol v1 event stream |
| `fingerprint_hash_key` | `vitalserver:relay:fingerprints` | payload fingerprint hash |
| `publish_dedupe_hash_key` | `vitalserver:relay:published` | publish dedupe hash |
| `event_stream_maxlen` | `100000` | stream approximate max length. `null`이면 제한 없음 |
| `publisher_id` | `vitalserver-helper-relay` | event publisher 식별자 |

`event_stream_key`, fingerprint/dedupe key, `publisher_id`는 빈 문자열일 수 없습니다.

### 3-2. Scope preset

**`waveform_trend_only`**

Waveform과 trend payload key만 전달합니다.

- waveform chunk: `<40자 bed id><timestamp>` 형태
- `dts_<bedid>`
- `dts_trend_result_<bedid>`
- `trend_<bedid>_<index>`

**`vital_reconstruction`**

`waveform_trend_only`에 더해 bed, recorder, device와 reconstruction context를 전달합니다.
대표적으로 `beds`, `vrs`, `utimes`, `devs_*`, `dtapp_*`, `filts_*`, `ptcon_*`가
포함됩니다. 정확한 key 의미는 [Recorder Redis key model](../recorder/redis-key-model.md)을
기준으로 봅니다.

**Recorder network context**

`include_recorder_network_context = true`이면 `ip_*`, `info_*`, `vrconf_*`를 scope에
추가합니다. 기본값은 `false`입니다.

### 3-3. 항상 차단하는 key

scope보다 deny policy가 먼저 적용됩니다. session, users, websocket ticket, auth, token,
credential, secret, login attempt, rate limit, audit event, websocket/HCT session key는 항상
차단합니다. UI나 TOML에서 정규식 규칙을 추가할 수 없습니다.

## 4. Credential 보안

### 4-1. Secret file 읽기 계약

- 상대 path는 TOML이 있는 디렉터리를 기준으로 해석합니다.
- UTF-8로 읽습니다.
- 끝의 `\n` 또는 `\r\n` 한 개만 제거합니다.
- 나머지 whitespace는 credential 값의 일부로 보존합니다.
- path가 설정되었다면 빈 문자열이나 공백뿐인 path는 오류입니다.
- missing, read failure, invalid UTF-8, empty file은 각각 다른 오류입니다.

Relay는 secret file의 POSIX mode를 변경하지 않습니다. Native operator는 secret directory를
전용 사용자만 접근할 수 있게 만들고 파일을 `0600`으로 유지합니다. Container secret mount는
runtime이 제공하는 별도 mode를 사용할 수 있습니다.

### 4-2. Credential 비노출 계약

Credential 값은 다음 위치에 포함하지 않습니다.

- TOML과 Target URL
- CLI flag와 환경변수
- launchd plist와 systemd unit
- status document와 settings fingerprint
- endpoint `repr`, 설정 오류와 인증 오류
- Runtime Control GET response

Status와 API는 값 대신 `targetUsernameConfigured`, `targetPasswordConfigured` 또는 같은
의미의 boolean만 제공합니다.

## 5. 변경 적용과 migration

### 5-1. 설정과 credential reload

Relay는 loop마다 TOML과 credential file을 다시 읽습니다. 숨겨진 credential cache는 없습니다.
유효한 credential file을 원자적으로 교체하면 다음 loop부터 새 값이 사용됩니다. 변경 실패를
피하려면 임시 파일을 같은 filesystem에 쓰고 permission을 설정한 뒤 replace합니다.

### 5-2. Legacy URL username migration

Guest Control은 legacy `redis://username@host:port/db`와 기존 password file을 canonical URL,
`username_file`, `password_file`로 명시적으로 migration할 수 있습니다. 이 migration은 Compose
`UP` 또는 settings save/apply 명령 경계에서만 수행합니다. GET/read는 파일을 변경하지 않습니다.

Relay 자체는 URL username이나 password를 수용하지 않습니다. URL password, username-only,
잘못된 contract path, missing/unreadable/non-UTF-8/empty password file은 migration이나 no-auth로
바꾸지 않고 오류로 남깁니다. 자세한 대응은
[TS-193](../troubleshooting/193_redis-relay-legacy-url-username-migration.md)을 봅니다.
