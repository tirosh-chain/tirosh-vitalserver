# VitalServer Redis 데이터 구조

이 문서는 Vital Recorder 실시간 payload가 VitalServer를 거쳐 Redis에 저장되는 구조를 정리합니다.
Relay 기능을 설계할 때 어떤 key를 보존해야 하는지 판단하기 위한 근거 문서입니다.

기준 코드는 upstream `vendor/vitalserver/vitalserver-old/service/include`의 `monitor.js`와 `db.js`입니다.

## 1. 문서 목적

### 1-1. 왜 이 구조를 파악하는가

이 구조를 파악하는 목적은 단순 관찰이 아닙니다. Source Redis의 실시간 데이터를 외부 target Redis로
relay해서 upstream VitalServer를 제품 구성요소로 사용할 수 있게 만드는 것이 목적입니다.

Relay는 VitalServer raw Redis port를 외부에 직접 열지 않습니다. 대신 Helper-managed relay container가
source Redis를 read-only로 읽고, allowlisted key snapshot과 metadata event를 target Redis로 publish합니다.

### 1-2. 이 문서가 다루는 범위

이 문서는 아래 내용을 다룹니다.

- VitalServer가 `send_data` payload를 Redis key로 저장하는 흐름
- bed, recorder, timestamp key의 식별 규칙
- waveform/trend/reconstruction에 필요한 Redis key
- relay scope를 나누는 기준
- relay 구현이 지켜야 하는 binary/TTL/consumer 책임 경계

Target Redis에서 event를 어떻게 읽고 consumer group, pending recovery, DLQ를 어떻게 운영하는지는
site dev 문서의 [Redis Relay](../../site-docs/dev/redis-relay.md)를 기준으로 봅니다.

## 2. 저장 흐름

### 2-1. `send_data` 처리 순서

VitalServer는 Socket.IO `send_data` event를 받으면 아래 순서로 처리합니다.

1. zlib 압축 payload를 해제합니다.
2. JSON을 읽어 `vrcode`, `ver`, `rooms`를 꺼냅니다.
3. `rooms` 안의 각 room을 bed로 등록합니다.
4. bed별 최신 상태, timestamp index, 압축된 frame data를 Redis에 씁니다.
5. Web Monitoring 클라이언트에는 Socket.IO `recv_data` event를 emit합니다.

### 2-2. testkit payload와 같은 흐름

testkit의 `send-recorder` command는 이 흐름에 맞춰 `{vrcode, ver, rooms}` payload를 zlib으로 압축해
`send_data` event로 보냅니다.

따라서 testkit으로 만든 Redis key는 실제 Vital Recorder가 만든 Redis key와 같은 구조를 따라야 합니다.

## 3. 주요 식별자

### 3-1. `bedid`

`bedid`는 아래 값의 SHA-1 hash입니다.

```text
<admin-user-id>/<roomname>
```

기본 admin user가 `admin`이고 `roomname`이 `mnw4anvs4`이면:

```text
sha1("admin/mnw4anvs4")
= de8d5733096db32506a924ac566c903c343e2338
```

`devs_de8d5733096db32506a924ac566c903c343e2338` 같은 key는 이 `bedid`를 suffix로 사용합니다.

### 3-2. `vrcode`

`vrcode`는 recorder를 식별하는 값입니다. VitalServer는 recorder별 담당 bed 목록, 마지막 전송 시각,
recorder version 같은 context를 `vrcode` 기반 key에 저장합니다.

## 4. Redis Key Model

### 4-1. Relationship과 activity key

| Key pattern | Type | TTL | 내용 |
|---|---|---|---|
| `beds` | Set | 없음 | 등록된 `bedid` 목록 |
| `beds:<bedid>` | String | 없음 | `{"vrcode": "...", "bedname": "..."}` |
| `vrs` | Set | 없음 | 등록된 recorder code 목록 |
| `vrs:<vrcode>` | Set | 없음 | recorder가 담당하는 `bedid` 목록 |
| `utime_<vrcode>` | String | 없음 | recorder가 마지막으로 data를 보낸 Unix time |
| `vrver_<vrcode>` | String | 없음 | recorder version |
| `utime_<bedid>` | String | 없음 | bed가 마지막으로 data를 받은 Unix time |
| `utimes` | Sorted Set | 최근 4시간 score 유지 | active bed index. member는 `bedid`, score는 Unix time |

이 key들은 bed/recorder 관계와 최신 activity를 복원하는 데 필요합니다.

### 4-2. Device와 patient context key

| Key pattern | Type | TTL | 내용 |
|---|---|---|---|
| `devs_<bedid>` | String | 약 4시간 | device metadata JSON |
| `dtapp_<bedid>` | String | 약 4시간 | recorder app timestamp |
| `filts_<bedid>` | String | 약 4시간 | filter metadata JSON. payload에 `filts`가 있을 때만 갱신 |
| `ptcon_<bedid>` | String | 약 5분 | patient connected 여부. `1` 또는 `0` |

이 key들은 `.vital`과 비슷한 수준의 context 복원이나 downstream reconstruction에 필요합니다.

### 4-3. Waveform과 trend key

| Key pattern | Type | TTL | 내용 |
|---|---|---|---|
| `dts_<bedid>` | Sorted Set | 최근 4시간 score 유지 | frame timestamp index. member와 score가 timestamp |
| `<bedid><timestamp>` | String | 약 4시간 | zlib gzip으로 압축된 room JSON frame |
| `trend_<bedid>_<minute_ts>` | String | 약 6시간 | 1분 단위 trend summary JSON |
| `dts_trend_result_<bedid>` | Sorted Set | 최근 6시간 score 유지 | trend timestamp index |

Waveform frame payload는 binary로 다뤄야 합니다. 문자열 decode를 먼저 시도하면 payload가 깨질 수 있습니다.

### 4-4. TTL 기준

TTL 값은 upstream 코드의 `EX` 값 기준입니다.

- 4시간: `14400`
- 6시간: `21600`
- 5분: `300`

Relay는 source key의 TTL 의미를 target Redis에 유지해야 합니다. Source key가 이미 만료되었거나 scan
시점에 사라진 경우는 empty success가 아니라 missing snapshot으로 다룹니다.

## 5. Payload 예시

### 5-1. Redis UI에서 보이는 key

샘플 payload를 전송하면 Redis UI에서 아래와 비슷한 key를 볼 수 있습니다.

```text
beds
beds:de8d5733096db32506a924ac566c903c343e2338
devs_de8d5733096db32506a924ac566c903c343e2338
dtapp_de8d5733096db32506a924ac566c903c343e2338
dts_de8d5733096db32506a924ac566c903c343e2338
de8d5733096db32506a924ac566c903c343e23381778392870.112
ptcon_de8d5733096db32506a924ac566c903c343e2338
utime_de8d5733096db32506a924ac566c903c343e2338
utimes
vrs
vrs:de8d5733096db32506a924ac566c903c343e2338
vrver_de8d5733096db32506a924ac566c903c343e2338
```

### 5-2. Device metadata JSON

`devs_<bedid>` 값은 JSON string입니다.

```json
[
  {
    "type": "Demo",
    "name": "Demo",
    "status": "on",
    "ycable": "0",
    "port": ""
  },
  {
    "type": "Demo",
    "name": "Demo2",
    "status": "on",
    "ycable": "0",
    "port": ""
  }
]
```

### 5-3. Frame payload 읽기

`<bedid><timestamp>` key는 raw JSON이 아니라 zlib gzip으로 압축된 binary입니다. 읽을 때는 Redis `GET`으로
bytes를 가져온 뒤 압축을 해제해야 합니다.

```python
import json
import zlib

raw = redis_client.get(f"{bedid}{timestamp}")
frame = json.loads(zlib.decompress(raw, 16 + zlib.MAX_WBITS))
```

## 6. Relay Scope

### 6-1. `waveform_trend_only`

Waveform과 trend를 외부 consumer가 decode하는 목적이면 아래 key가 우선 대상입니다.

- `dts_<bedid>`, `<bedid><timestamp>`
- `trend_<bedid>_<minute_ts>`, `dts_trend_result_<bedid>`

이 scope는 payload volume이 큰 waveform/trend path를 우선합니다. Bed/recorder 관계나 device context를
완전히 복원하기 위한 scope는 아닙니다.

### 6-2. `vital_reconstruction`

`.vital`과 비슷한 수준으로 source Redis context를 재구성해야 하면 아래 key를 함께 relay합니다.

- `beds`, `beds:<bedid>`
- `vrs`, `vrs:<vrcode>`
- `utime_<vrcode>`, `vrver_<vrcode>`
- `utime_<bedid>`, `utimes`
- `devs_<bedid>`, `dtapp_<bedid>`, `filts_<bedid>`, `ptcon_<bedid>`
- `waveform_trend_only` scope의 모든 key

이 scope는 reconstruction에 필요한 bed/recorder/device context를 포함합니다.

### 6-3. Recorder network context

Recorder connection IP나 active IP 확인 같은 network context가 필요할 때만 아래 key를 추가로 포함합니다.

- `ip_<vrcode>`
- `info_<vrcode>`
- `vrconf_<vrcode>`

이 정보는 credential은 아니지만 현장 network context를 포함할 수 있으므로 별도 option으로 둡니다.

### 6-4. Denylist

Credential, session, token, auth, rate-limit, websocket 같은 운영 내부 key는 relay하지 않습니다.
Relay는 allowlist보다 denylist를 먼저 적용합니다.

## 7. Relay 방식

### 7-1. Source read 방식

현재 relay는 Redis keyspace notification이나 per-bed timestamp cursor를 사용하지 않습니다. Source Redis
설정을 바꾸지 않고 아래 command로 allowlisted key snapshot을 읽습니다.

- `SCAN`
- `TYPE`
- `PTTL`
- `DUMP`

`DUMP` payload는 opaque snapshot으로 취급합니다. Domain layer는 payload 내부를 해석하지 않습니다.

### 7-2. Target publish 방식

Target Redis에는 VitalServer Redis Relay Protocol v1로 publish합니다.

Publisher는 target key `RESTORE`, fingerprint update, publish dedupe, `key_published` stream event를
atomic하게 기록합니다. HTTP/base64 export는 실시간/대용량 waveform relay 경로로 사용하지 않습니다.

### 7-3. Consumer 책임

Target Redis consumer는 stream event의 `target_key`를 fetch해서 decode해야 합니다.

Consumer group pending recovery, DLQ, decode idempotency, downstream write idempotency는 relay가 아니라
target consumer 책임입니다.

## 8. 외부 Redis Relay 계약

### 8-1. Source Redis는 외부에 공개하지 않음

외부 consumer가 VitalServer host와 같은 Docker network에 없고 다른 PC 또는 Kubernetes에서 실행될 때도
source Redis를 직접 외부에 노출하지 않습니다.

대신 VitalServer compose 내부의 relay container가 source Redis 3.2에 Redis protocol로 직접 접근하고,
설정된 target Redis 8.x endpoint로 publish합니다.

### 8-2. Helper UI는 preset만 노출

Helper app은 regex를 노출하지 않고, `waveform_trend_only` 또는 `vital_reconstruction` 같은 preset만
설정합니다.

Regex allowlist와 denylist는 relay code의 policy가 소유합니다. UI가 domain policy를 만들거나 수정하지
않습니다.

### 8-3. Contract reference

Target Redis key prefix, event stream, Protocol v1 field, consumer 권장 흐름은 site dev 문서의
[Redis Relay](../../site-docs/dev/redis-relay.md)를 기준으로 봅니다.
