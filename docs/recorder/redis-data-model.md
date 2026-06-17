# VitalServer Redis 데이터 구조

이 문서는 Vital Recorder 실시간 payload가 VitalServer를 거쳐 Redis에 저장되는 구조를
정리합니다. 기준 코드는 upstream `vendor/vitalserver/vitalserver-old/service/include`의
`monitor.js`와 `db.js`입니다.

이 구조를 파악하는 목적은 단순 관찰이 아니라, source Redis의 실시간 데이터를 다른 Redis
서버로 relay해서 upstream VitalServer를 제품 구성요소로 사용할 수 있게 만드는 것입니다.

## 저장 흐름

VitalServer는 Socket.IO `send_data` event를 받으면 아래 순서로 처리합니다.

1. zlib 압축 payload를 해제합니다.
2. JSON을 읽어 `vrcode`, `ver`, `rooms`를 꺼냅니다.
3. `rooms` 안의 각 room을 bed로 등록합니다.
4. bed별 최신 상태, timestamp index, 압축된 frame data를 Redis에 씁니다.
5. Web Monitoring 클라이언트에는 Socket.IO `recv_data` event를 emit합니다.

testkit의 `send-recorder` command는 이 흐름에 맞춰 `{vrcode, ver, rooms}` payload를
zlib으로 압축해 `send_data` event로 보냅니다.

## 주요 식별자

`bedid`는 아래 값의 SHA-1 hash입니다.

```text
<admin-user-id>/<roomname>
```

기본 admin user가 `admin`이고 `roomname`이 `mnw4anvs4`이면:

```text
sha1("admin/mnw4anvs4")
= de8d5733096db32506a924ac566c903c343e2338
```

사진에 보이는 `devs_de8d5733096db32506a924ac566c903c343e2338` 같은 key는 이 `bedid`를
suffix로 사용합니다.

## 실시간 key

| Key pattern | Type | TTL | 내용 |
| --- | --- | --- | --- |
| `beds` | Set | 없음 | 등록된 `bedid` 목록 |
| `beds:<bedid>` | String | 없음 | `{"vrcode": "...", "bedname": "..."}` |
| `vrs` | Set | 없음 | 등록된 recorder code 목록 |
| `vrs:<vrcode>` | Set | 없음 | recorder가 담당하는 `bedid` 목록 |
| `utime_<vrcode>` | String | 없음 | recorder가 마지막으로 data를 보낸 Unix time |
| `vrver_<vrcode>` | String | 없음 | recorder version |
| `utime_<bedid>` | String | 없음 | bed가 마지막으로 data를 받은 Unix time |
| `utimes` | Sorted Set | 최근 4시간 score 유지 | active bed index. member는 `bedid`, score는 Unix time |
| `devs_<bedid>` | String | 약 4시간 | device metadata JSON |
| `dtapp_<bedid>` | String | 약 4시간 | recorder app timestamp |
| `filts_<bedid>` | String | 약 4시간 | filter metadata JSON. payload에 `filts`가 있을 때만 갱신 |
| `ptcon_<bedid>` | String | 약 5분 | patient connected 여부. `1` 또는 `0` |
| `dts_<bedid>` | Sorted Set | 최근 4시간 score 유지 | frame timestamp index. member와 score가 timestamp |
| `<bedid><timestamp>` | String | 약 4시간 | zlib gzip으로 압축된 room JSON frame |
| `trend_<bedid>_<minute_ts>` | String | 약 6시간 | 1분 단위 trend summary JSON |
| `dts_trend_result_<bedid>` | Sorted Set | 최근 6시간 score 유지 | trend timestamp index |

TTL 값은 upstream 코드의 `EX` 값 기준입니다.

- 4시간: `14400`
- 6시간: `21600`
- 5분: `300`

## 예시

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

`<bedid><timestamp>` key는 raw JSON이 아니라 zlib gzip으로 압축된 binary입니다.
읽을 때는 먼저 Redis `GET`으로 bytes를 가져온 뒤 압축을 해제해야 합니다.

```python
import json
import zlib

raw = redis_client.get(f"{bedid}{timestamp}")
frame = json.loads(zlib.decompress(raw, 16 + zlib.MAX_WBITS))
```

## relay 대상

다른 Redis 서버로 실시간 전송할 때 우선 relay해야 하는 것은 아래입니다.

- `beds`, `beds:<bedid>`
- `vrs`, `vrs:<vrcode>`
- `utime_<vrcode>`, `vrver_<vrcode>`
- `utime_<bedid>`, `utimes`
- `devs_<bedid>`, `dtapp_<bedid>`, `filts_<bedid>`, `ptcon_<bedid>`
- `dts_<bedid>`, `<bedid><timestamp>`
- 필요하면 `trend_<bedid>_<minute_ts>`, `dts_trend_result_<bedid>`

처음에는 Web Monitoring과 downstream consumer가 최근 bed 상태와 frame data를 재구성할 수
있도록 `utimes`, `dts_<bedid>`, `<bedid><timestamp>`, `devs_<bedid>`, `beds:<bedid>`를
우선 relay합니다.

## relay 방식 제안

초기 구현은 Redis keyspace notification이 아니라 polling 방식이 안전합니다.
upstream Redis 설정을 건드리지 않아도 되고, 놓친 frame을 `dts_<bedid>` index로 다시 읽을
수 있기 때문입니다.

권장 loop:

1. source Redis의 `utimes`에서 최근 N초 안에 갱신된 active `bedid`를 읽습니다.
2. bed별로 마지막 relay timestamp를 local state에 보관합니다.
3. `ZRANGEBYSCORE dts_<bedid> (<last_ts> +inf`로 새 frame timestamp를 읽습니다.
4. 각 timestamp마다 `<bedid><timestamp>` binary frame을 `GET`합니다.
5. target Redis에 원본 key와 같은 TTL로 `SET`합니다.
6. target Redis의 `dts_<bedid>`와 `utimes`도 같은 score/member로 갱신합니다.
7. `devs_<bedid>`, `dtapp_<bedid>`, `filts_<bedid>`, `ptcon_<bedid>`, `beds:<bedid>` 같은
   상태 key도 주기적으로 복제합니다.

주의할 점:

- `<bedid><timestamp>` 값은 binary라 문자열 decode를 하면 안 됩니다.
- source key TTL을 읽어 target에 같은 TTL로 쓰는 것이 좋습니다.
- relay가 잠깐 멈춰도 `dts_<bedid>`에 남아 있는 4시간 window 안에서는 catch-up이 가능합니다.
- target Redis가 다른 VitalServer에서 직접 읽힐 예정이면 key 이름을 그대로 유지합니다.
- target Redis를 분석/저장용으로만 쓴다면 namespace prefix를 둘 수 있지만, VitalServer 호환성은
  떨어집니다.

## 외부 Redis relay 계약

외부 consumer가 VitalServer host와 같은 Docker network에 없고 다른 PC 또는 Kubernetes에서 실행될 때도
source Redis를 직접 외부에 노출하지 않습니다. 대신 VitalServer compose 내부의 relay container가
source Redis 3.2에 Redis protocol로 직접 접근하고, 설정된 target Redis 8.x endpoint로 publish합니다.

relay는 source Redis에는 write하지 않습니다. Source에서는 `SCAN`, `TYPE`, `PTTL`, `DUMP`를 사용하고,
target Redis에는 `RESTORE`로 binary-safe하게 복제합니다. HTTP/base64 export는 실시간/대용량 waveform
relay 경로로 사용하지 않습니다.

`.vital`과 비슷한 수준의 복원을 목표로 할 때 relay scope는 credential/session/auth key를 제외하고
waveform/trend payload와 bed/recorder/device context key를 포함해야 합니다. Helper app은 regex를
노출하지 않고, `waveform_trend_only` 또는 `vital_reconstruction` 같은 preset만 설정합니다.
