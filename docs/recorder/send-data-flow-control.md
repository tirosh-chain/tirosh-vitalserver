# Recorder ingress send_data flow control contract

이 문서는 Issue #68의 `send_data` flow control 계약을 설명합니다. 핵심 목표는 upstream VitalServer를 수정하지 않고, recorder ingress가 `send_data` 유입을 명시적으로 소유해 upstream Node process가 무제한 실시간 입력을 직접 받지 않게 만드는 것입니다.

이 문서는 구현자와 운영자가 같은 mental model을 갖기 위한 문서입니다. 따라서 "왜 메모리가 늘었는가", "한 `send_data` frame이 어디로 가는가", "status에서 무엇을 봐야 하는가", "현재 구현과 목표 계약의 차이는 무엇인가"를 함께 다룹니다.

## 1. 한눈에 보기

VRecorder는 Socket.IO `send_data` event로 압축된 생체신호 payload를 계속 보냅니다. 기존 경로에서는 이 payload가 upstream VitalServer app으로 바로 전달되고, upstream은 payload마다 압축 해제, JSON parse, Redis 갱신, UI broadcast, filter/trend 처리를 수행합니다. 입력 속도가 이 처리량보다 빠르면 upstream Node heap과 Socket.IO/Redis queue가 커지고, 결국 OOM, 502, stale runtime state, watchdog recovery 실패로 이어질 수 있습니다.

Recorder ingress의 해결 방향은 upstream 처리를 없애는 것이 아닙니다. upstream이 그 처리를 무제한 실시간 입력으로 직접 받지 않게 만드는 것입니다.

### 1-1. Spool이란 무엇인가

Spool은 "지금 바로 처리하지 않고, 원본 일을 안전한 대기열에 적재하는 것"입니다. 프린터 spool을 떠올리면 쉽습니다. 사용자가 인쇄 버튼을 여러 번 눌러도 프린터가 모든 문서를 동시에 처리하지 않고, 인쇄 작업을 queue에 쌓은 뒤 순서대로 처리합니다.

여기서 spool 대상은 VRecorder가 보낸 원본 `send_data` payload입니다. Recorder ingress는 payload를 해석해 waveform/trend domain 상태를 만들지 않습니다. 대신 upstream replay에 필요한 원본 compressed payload bytes와 correlation 정보만 Redis list에 저장합니다.

```text
send_data payload
  -> spool item
  -> Redis pending list
```

이렇게 하면 burst가 upstream Node heap이 아니라 Redis pending list에 쌓입니다. 하지만 Redis pending list도 무제한 성공으로 취급하지 않습니다. `maxPendingItems`, `maxPendingBytes`, `maxPayloadBytes`를 넘으면 `spool_full`/`rejected` evidence로 노출합니다.

### 1-2. Replay란 무엇인가

Replay는 "spool에 저장한 일을 나중에 다시 꺼내서 원래 대상에게 보내는 것"입니다. 이 문서에서 replay는 Redis pending list에 쌓인 `send_data` spool item을 worker가 하나씩 claim한 뒤 upstream VitalServer에 Socket.IO `send_data` event로 다시 보내는 과정을 뜻합니다.

```text
Redis pending list
  -> replay worker claim
  -> upstream Socket.IO send_data emit
  -> replayed / retry / dead_letter
```

Replay는 upstream 처리량을 조절하는 지점입니다. Worker는 tick interval, batch size, rate limit에 맞춰 upstream으로 보내므로, VRecorder가 빠르게 보낸 burst를 upstream이 감당 가능한 속도로 바꿀 수 있습니다.

### 1-3. Spool과 replay를 합치면 무엇이 달라지는가

기존 경로는 "받자마자 upstream으로 보낸다"입니다.

```text
VRecorder -> upstream VitalServer
```

`spool_and_replay` 경로는 "먼저 저장하고, 정해진 속도로 다시 보낸다"입니다.

```text
VRecorder -> recorder ingress -> Redis spool -> replay worker -> upstream VitalServer
```

그래서 `spool_and_replay`는 upstream을 우회하거나 대체하는 기능이 아닙니다. Upstream에 들어가는 `send_data`의 속도와 실패 의미를 recorder ingress가 명시적으로 소유하게 만드는 flow control 기능입니다.

```text
VRecorder
  -> recorder ingress
     -> observe/audit send_data
     -> store original payload in Redis spool
     -> optionally suppress direct upstream send_data relay
     -> replay worker sends send_data to upstream at controlled pace
  -> upstream VitalServer
```

운영 목표 mode는 `spool_and_replay`입니다.

- ingress는 client `send_data` frame을 upstream direct relay에서 제거합니다.
- ingress는 원본 compressed payload를 Redis pending list에 저장합니다.
- replay worker는 pending item을 claim해 upstream Socket.IO `send_data`로 다시 보냅니다.
- pending이 너무 커지면 성공처럼 숨기지 않고 `spool_full`/`rejected` evidence를 남깁니다.
- upstream 장애와 spool 장애는 서로 다른 failure로 남깁니다.

## 2. 왜 upstream이 메모리를 많이 쓰는가

Upstream VitalServer에서 `send_data`는 "받은 데이터를 그대로 다른 곳으로 전달하는 event"가 아닙니다. 하나의 `send_data` payload는 작은 압축 상자처럼 들어오지만, upstream 안에서는 여러 형태로 풀리고, 복사되고, 다시 압축되고, Redis와 UI로 흘러갑니다.

먼저 큰 그림은 이렇습니다.

```text
compressed Socket.IO payload
  -> inflate to JSON string
  -> parse to JavaScript object
  -> register recorder/bed relationship
  -> process each room
     -> write Redis activity/context/frame/trend keys
     -> gzip room payload again
     -> broadcast recv_data to UI clients
     -> optionally run filter/trend paths
```

메모리가 늘어나는 핵심은 "payload 하나가 처리되는 동안 같은 데이터가 여러 표현으로 동시에 존재한다"는 점입니다. 예를 들어 payload 하나가 들어오면 upstream은 압축된 Buffer, 압축 해제된 JSON string, `JSON.parse`가 만든 object graph를 순서대로 만들지만, 각 객체가 즉시 사라진다고 보장할 수 없습니다. 그 상태에서 room별 broadcast를 위해 다시 `JSON.stringify`와 `gzipSync`를 수행하면 room 단위 string/buffer와 Socket.IO outgoing packet도 추가됩니다.

### 2-1. 1단계: 압축 payload가 JSON object로 커진다

VRecorder가 보낸 payload는 압축되어 있습니다. Upstream은 `vendor/vitalserver/vitalserver-old/service/app.js`의 Socket.IO handler에서 이 payload를 받아 `monitor.send_data(io, payload)`로 넘기고, `service/include/monitor.js`에서 처리합니다.

초기 단계는 아래와 같습니다.

```text
payload
  -> Buffer.from(payload, "binary")
  -> zlib.inflateSync(...)
  -> JSON string cleanup
  -> JSON.parse(...)
  -> JavaScript object graph
```

이 단계에서 압축된 payload는 상대적으로 작을 수 있지만, inflate된 JSON string과 parsed object는 훨씬 클 수 있습니다. 특히 `rooms` 안에 여러 bed, device, track sample이 들어 있으면 object graph는 payload 크기보다 더 많은 메모리를 차지합니다.

또 하나 중요한 점은 `inflateSync`가 synchronous 작업이라는 것입니다. 이 작업을 하는 동안 Node event loop는 다른 일을 처리하지 못합니다. 즉 payload 하나를 풀고 parse하는 동안 새 `send_data` frame은 Socket.IO/Engine.IO 쪽 대기열에 쌓일 수 있습니다.

### 2-2. 2단계: recorder와 bed 관계를 갱신한다

JSON object가 만들어지면 upstream은 `vrcode`, `ver`, `rooms`를 읽고 `db.register_bed(vrcode, rooms)`를 실행합니다. 이 단계는 단순 계산이 아니라 recorder가 담당하는 bed 관계를 Redis에 반영하는 작업입니다.

이때 이미 payload는 아래 형태로 메모리에 남아 있을 수 있습니다.

```text
compressed buffer
inflated JSON string
parsed payload object
rooms object
Redis command callbacks/promises
```

Redis가 빠르게 응답하면 부담이 작지만, Redis command가 밀리면 Redis client 내부 queue와 callback/Promise closure도 Node process 안에 남습니다. 즉 "Redis에 쓰는 일"도 upstream process memory와 무관하지 않습니다.

### 2-3. 3단계: 각 room을 다시 가공해서 UI와 Redis로 보낸다

그 다음 upstream은 `rooms`의 각 room을 순회합니다. 이 단계가 무거운 이유는 한 room에 대해 여러 일을 동시에 하기 때문입니다.

```text
room
  -> room name을 bed id로 hash
  -> filter/hid/islinux 같은 보조 상태를 Redis에서 read
  -> room payload를 JSON.stringify
  -> zlib.gzipSync(...)
  -> UI bed room에 recv_data broadcast
  -> Redis activity/context/frame keys write
```

여기서 다시 메모리 복제가 생깁니다. 이미 parsed object 안에 room data가 있는데, UI broadcast를 위해 room payload를 다시 JSON string으로 만들고, 다시 gzip buffer로 만듭니다. UI client가 느리거나 Socket.IO outgoing buffer가 밀리면 이 broadcast packet도 즉시 해소되지 않을 수 있습니다.

Redis에는 `utime_*`, `vrver_*`, `devs_*`, `dtapp_*`, `filts_*`, `ptcon_*`, `dts_*`, `utimes`, `<bedid><timestamp>` 같은 key가 갱신됩니다. 이 key들의 의미와 TTL은 [VitalServer recorder Redis key model](redis-key-model.md)을 기준으로 봅니다.

### 2-4. 4단계: filter와 trend path가 추가 작업을 만들 수 있다

일부 bed는 filter/trend 경로를 탑니다. 이 경우 upstream은 현재 payload만 처리하지 않고 과거 sample을 Redis에서 다시 읽을 수 있습니다.

```text
filter/trend path
  -> old sample Redis read
  -> gunzipSync
  -> JSON.parse
  -> filter service call
  -> filter result/trend summary Redis write
  -> old score range cleanup
```

즉 payload 하나가 "현재 frame 저장"으로 끝나지 않을 수 있습니다. 과거 sample read, 추가 gunzip/parse, 외부 filter service 호출, trend summary write가 붙으면 처리 시간과 메모리 점유 시간이 늘어납니다.

### 2-5. 그래서 병목은 하나가 아니다

`send_data` 처리량은 하나의 함수 실행 시간으로 설명하기 어렵습니다. 실제 처리량은 아래 작업을 모두 합친 값입니다.

- 압축 해제와 JSON parse
- recorder/bed 관계 갱신
- room/track 순회
- Redis read/write
- UI Socket.IO broadcast
- filter/trend 계산
- Redis client queue와 Socket.IO queue가 해소되는 속도

따라서 메모리 압력도 한 곳에서만 생기지 않습니다.

| 위치 | 메모리가 늘어나는 이유 |
|---|---|
| payload decode | compressed buffer, inflated JSON string, parsed object가 동시에 존재 |
| room broadcast | room별 stringify/gzip buffer와 Socket.IO outgoing packet 생성 |
| Redis IO | command queue와 callback/Promise closure가 process 안에 남음 |
| event loop | synchronous zlib 작업 동안 새 frame이 대기열에 쌓임 |
| filter/trend | 과거 sample read, gunzip, parse, service call, result write가 추가됨 |

결국 VRecorder 입력 속도가 이 전체 처리량보다 빠르면 아직 처리되지 않은 payload와 중간 객체가 upstream Node process memory에 누적됩니다. Issue #68은 이 upstream 내부 로직을 patch하지 않고, 앞단에서 `send_data` 유입을 명시적으로 조절하는 문제입니다.

## 3. spool_and_replay가 이 문제를 어떻게 줄이는가

`spool_and_replay`는 upstream의 무거운 `send_data` 처리를 없애지 않습니다. 대신 upstream이 그 처리를 "VRecorder가 보내는 순간의 속도"로 직접 떠안지 않게 만듭니다. 핵심은 backlog의 소유자를 upstream Node heap에서 recorder ingress의 Redis spool로 옮기고, replay worker가 upstream으로 보내는 속도를 통제하는 것입니다.

기존 경로에서는 VRecorder burst가 곧바로 upstream Socket.IO 입력 queue가 됩니다.

```text
VRecorder burst
  -> upstream Socket.IO queue
  -> inflate / parse / Redis / UI broadcast / filter
  -> upstream Node heap pressure
```

`spool_and_replay`에서는 같은 burst가 먼저 Redis pending list로 들어가고, upstream은 worker가 꺼낸 만큼만 받습니다.

```text
VRecorder burst
  -> recorder ingress
  -> Redis pending list
  -> replay worker controlled send_data
  -> upstream processing at bounded pace
```

이 차이가 메모리 압력을 줄이는 방식은 단계별로 볼 수 있습니다.

### 3-1. direct relay를 끊어 upstream의 즉시 유입을 막는다

`spool_and_replay` mode에서 recorder ingress는 client WebSocket frame을 검사해 `send_data` text event와 그 binary attachment를 upstream direct relay에서 제거합니다. `join_vr`, `req_cmd`, ping/pong 같은 control 흐름은 계속 통과하지만, 메모리 압력의 원인이 되는 `send_data` payload는 upstream으로 바로 가지 않습니다.

이것이 가장 중요한 차단점입니다. Direct relay가 살아 있으면 spool을 하더라도 upstream은 여전히 원래 burst를 그대로 받습니다. 그 경우 Redis spool은 증거를 남길 뿐, OOM을 구조적으로 줄이지 못합니다. `spool_and_replay`는 direct relay를 끊고 replay worker만 upstream 유입 경로로 남깁니다.

### 3-2. backlog를 Node heap이 아니라 명시적인 Redis queue로 옮긴다

Upstream에서 backlog가 생기면 아직 inflate/parse되지 않은 Socket.IO frame, 처리 중인 JSON string/object, Redis command queue, UI outgoing packet이 Node process 안팎에 뒤섞여 쌓입니다. 이 상태는 운영자가 "얼마나 밀렸는지", "어느 recorder가 원인인지", "언제부터 오래된 payload가 남아 있는지"를 읽기 어렵습니다.

Recorder ingress는 backlog를 `send_data` spool item으로 바꿔 Redis pending list에 넣습니다. 이 queue는 domain state가 아니라 flow control state입니다. 그래서 status에서 `pendingItems`, `pendingBytes`, `oldestPendingAgeSeconds`, `replayLagSeconds`처럼 backlog를 직접 읽을 수 있습니다.

중요한 점은 Redis로 옮겼다고 해서 backlog가 사라지는 것이 아니라는 점입니다. 문제를 숨긴 것이 아니라, upstream heap 안의 암묵적인 대기열을 운영 가능한 명시적 queue로 바꾼 것입니다.

### 3-3. ingest 단계에서는 payload를 upstream처럼 깊게 처리하지 않는다

Recorder ingress가 spool item을 만들 때 payload를 waveform/trend domain으로 해석하지 않습니다. Replay의 source of truth는 원본 compressed payload bytes를 담은 `payloadBase64`입니다. Audit과 routing에 필요한 요약은 만들 수 있지만, upstream처럼 room별 `JSON.stringify`, `gzipSync`, Redis frame write, UI broadcast, filter/trend 계산을 수행하지 않습니다.

그래서 ingest 단계의 메모리 사용은 upstream 처리와 성격이 다릅니다. Upstream은 payload 하나를 실제 VitalServer domain 처리로 확장하지만, recorder ingress는 "나중에 upstream으로 다시 보낼 원본 일감"을 보존합니다. 이 차이 때문에 VRecorder burst가 들어오는 순간에 upstream 수준의 object expansion과 broadcast buffer가 만들어지지 않습니다.

### 3-4. replay worker가 upstream 유입 속도를 제한한다

Replay worker는 pending item을 한 번에 무제한 꺼내지 않습니다. 설정된 interval마다 실행되고, `batchSize`와 `rateLimitPerSecond` 중 더 작은 값만큼 claim합니다. Claim한 item은 `pending -> in_flight`로 이동한 뒤 upstream Socket.IO `send_data`로 emit되고, 결과에 따라 `replayed`, `requeued`, `dead_letter`로 정리됩니다.

이 구조에서는 VRecorder 입력 속도와 upstream 입력 속도가 분리됩니다.

```text
VRecorder input rate: burst 가능
Redis pending growth: backpressure limit까지 명시적으로 증가
upstream replay rate: worker 설정으로 제한
```

따라서 upstream은 "VRecorder가 지금 보내는 속도"가 아니라 "replay worker가 허용한 속도"로만 `send_data`를 받습니다. Replay rate를 upstream이 지속적으로 처리 가능한 수준보다 낮게 잡으면, section 2에서 설명한 inflate/parse/Redis/UI/filter 작업이 동시에 과도하게 쌓이는 상황을 줄일 수 있습니다.

### 3-5. 과부하는 성공처럼 숨기지 않고 명시적인 상태가 된다

`spool_and_replay`의 목표는 모든 입력을 무조건 성공으로 받는 것이 아닙니다. Redis pending list도 한계가 있으므로 `maxPayloadBytes`, `maxPendingItems`, `maxPendingBytes`를 넘으면 ingress는 `rejected` outcome과 `spool_full` reason을 남깁니다.

Upstream이 내려가 있거나 느리면 replay item은 retry되거나 retry 한도를 넘은 뒤 `dead_letter`가 됩니다. Spool write 실패, invalid payload, replay retryable failure, dead letter는 서로 다른 의미로 남습니다. 이 구분이 있어야 운영자가 "입력이 너무 많았는지", "Redis가 실패했는지", "upstream 연결이 실패했는지", "payload 자체가 invalid인지"를 분리해서 볼 수 있습니다.

정리하면 아래와 같습니다.

| upstream 메모리 압력 지점 | spool_and_replay가 바꾸는 점 |
|---|---|
| VRecorder burst가 upstream Socket.IO queue로 바로 들어감 | `send_data` direct relay를 제거하고 Redis pending list에 먼저 저장 |
| payload가 즉시 inflate/string/object/room buffer로 확장됨 | ingest 단계에서는 원본 compressed payload를 replay item으로 보존 |
| room별 UI broadcast와 Redis write가 burst 속도로 생성됨 | replay worker가 upstream으로 보내는 속도를 제한 |
| backlog가 Node heap, Redis client queue, Socket.IO queue에 섞임 | `pendingItems`, `pendingBytes`, lag, failure counter로 읽히는 명시적 queue로 이동 |
| 과부하가 OOM이나 502로 늦게 드러남 | `spool_full`, `rejected`, retry, dead letter로 조기에 드러남 |

단, `spool_and_replay`가 upstream 내부 처리 비용을 없애는 것은 아닙니다. Replay된 item은 결국 upstream에서 section 2의 inflate/parse/Redis/UI/filter 경로를 탑니다. 이 해결책의 본질은 비용 제거가 아니라 burst 흡수, 유입 속도 제한, backlog 가시화, 과부하의 명시적 실패화입니다.

## 4. 책임 경계

Recorder ingress가 소유하는 책임은 flow control과 evidence입니다.

- VRecorder client의 `join_vr`와 `send_data` 흐름 관측
- `send_data` 원본 compressed payload를 durable spool item으로 기록
- spool item을 upstream VitalServer로 통제된 속도로 replay
- spool/replay 상태, lag, failure reason 노출
- recorder별 pending, lag, failure counter 노출
- upstream app OOM을 막기 위한 backpressure 적용

Recorder ingress가 소유하지 않는 책임도 명확합니다.

- upstream VitalServer Redis write의 domain 의미 변경
- bed online/offline domain 상태 생성
- waveform/trend payload 해석
- upstream app 코드 patch
- spool 실패를 성공으로 숨기는 fallback
- replay 성공을 VitalServer domain success로 확대 해석

Replay 성공은 "upstream으로 `send_data` emit을 완료했다"는 뜻입니다. Upstream handler는 ack를 요구하지 않으므로, ingress는 upstream 내부 `monitor.send_data` 처리 결과를 domain success로 추정하지 않습니다. VitalServer가 내부 Redis key를 어떤 상태로 만들었는지는 upstream의 책임입니다.

## 5. Mode별 동작

`RECORDER_INGRESS_SEND_DATA_MODE`는 ingress가 client `send_data`를 upstream으로 직접 통과시킬지, spool에만 기록할지, replay worker를 사용할지 결정합니다.

기본 운영값은 `spool_and_replay`입니다. Helper Settings의 `send_data mode`는 이 값을 `runtime-settings.json`에 저장하고, guest compose runner가 `RECORDER_INGRESS_SEND_DATA_MODE` 환경변수로 recorder ingress에 전달합니다. 이 설정은 VM restart가 아니라 container service reconcile로 적용됩니다.

`mirror_spool`에서 Redis pending이 늘어나는 것은 "replay worker가 밀려서 소비하지 못하는 backlog"가 아닙니다. 이 mode는 upstream direct relay를 그대로 유지하면서 Redis에 관측용 사본을 남기고, replay를 명시적으로 켜지 않으면 소비자가 없습니다. 따라서 status에서는 이런 상태를 `draining`이 아니라 `mirroring, replay disabled`로 해석해야 합니다. Upstream 메모리 압력을 구조적으로 줄이려면 `mirror_spool`이 아니라 `spool_and_replay`를 사용해야 합니다.

| Mode | Direct upstream relay | Spool write | Replay worker | 용도 |
|---|---:|---:|---:|---|
| `passthrough` | 예 | 아니오 | 아니오 | spool 기능 비활성화. 기존 동작에 가깝습니다. |
| `mirror_spool` | 예 | 예 | 설정에 따름 | 안전한 관측/증거 수집용입니다. Upstream OOM을 구조적으로 막지는 않습니다. |
| `spool_only` | 아니오 | 예 | 아니오 | upstream direct 유입 차단 검증과 cutover 준비용입니다. |
| `spool_and_replay` | 아니오 | 예 | 예 | 목표 운영 mode입니다. |

`spool_only`와 `spool_and_replay`에서는 recorder ingress가 client WebSocket frame을 frame-level로 검사합니다. Socket.IO `send_data` text event와 관련 binary attachment는 upstream direct relay에서 제거하고, `join_vr`, `req_cmd`, control frame 등 다른 frame은 계속 전달합니다.

현재 구현에서 중요한 점은 client frame relay와 spool write가 같은 synchronous transaction이 아니라는 것입니다. Socket.IO audit service가 `send_data`를 관측하면 spool 기록을 비동기로 요청하고, WebSocket relay는 mode에 따라 `send_data` frame을 제거합니다. 따라서 `spool_and_replay`에서 spool write가 실패해도 해당 client frame이 upstream으로 fallback relay되지 않습니다. 실패는 client ack가 아니라 `/recorder-ingress/status`의 spool failure evidence로 확인해야 합니다.

## 6. 한 send_data의 lifecycle

`spool_and_replay`에서 정상적인 `send_data` 하나는 아래 순서로 이동합니다.

```text
client WebSocket frame observed
  -> send_data payload summarized
  -> original payload converted to spool item
  -> backpressure policy evaluated
  -> Redis pending list append
  -> replay worker claim: pending -> in_flight
  -> upstream Socket.IO send_data emit
  -> replay result stored: replayed | requeued | dead_letter
  -> status counters updated
```

이 lifecycle에서 각 단계의 실패는 서로 다른 의미를 갖습니다.

- 관측 실패: Socket.IO packet을 decode하지 못했습니다. Audit/parse failure입니다.
- invalid payload: spool item을 만들 수 없습니다. 예를 들어 payload가 string/buffer가 아니거나 `vrcode`를 찾을 수 없습니다.
- rejected: pending item/byte limit 또는 payload limit을 넘어 spool에 받지 않았습니다.
- spool write failed: Redis append가 실패했습니다.
- replay retryable failed: upstream 연결 실패나 timeout처럼 다시 시도할 수 있는 실패입니다.
- dead lettered: invalid spool document이거나 retry 한도를 넘겨 더 이상 재시도하지 않습니다.

## 7. Spool item schema

Spool item은 upstream replay에 필요한 원본 payload와 진단 정보를 보존하는 문서입니다. Payload는 waveform/trend domain으로 해석하지 않습니다. 원본 compressed payload를 opaque data로 보존하는 것이 목적입니다.

현재 구현의 item shape는 아래와 같습니다.

```json
{
  "schemaVersion": 1,
  "id": "senddata_01J...",
  "state": "pending",
  "vrcode": "VR001",
  "connectionId": "connection-1",
  "requestId": "request-1",
  "receivedAt": "2026-06-22T09:00:00.000Z",
  "payloadEncoding": "binary",
  "payloadBytes": 12345,
  "payloadBase64": "<base64 encoded original payload>",
  "payloadSummary": {
    "bytes": 12345,
    "vrcode": "VR001",
    "rooms_count": 4
  },
  "attemptCount": 0,
  "lastAttemptAt": null,
  "lastFailure": null
}
```

| Field | 의미 |
|---|---|
| `schemaVersion` | item decode 계약 버전 |
| `id` | replay idempotency와 diagnostics를 위한 고유 ID |
| `state` | spool item state |
| `vrcode` | recorder identity. payload summary에서 얻지 못하면 `join_vr` context 값을 사용합니다. 둘 다 없으면 invalid입니다. |
| `connectionId` / `requestId` | ingress 관측 correlation |
| `receivedAt` | ingress 수신 시각 |
| `payloadEncoding` | `string` 또는 `binary` |
| `payloadBytes` | 원본 compressed payload byte length |
| `payloadBase64` | upstream replay에 필요한 원본 payload bytes |
| `payloadSummary` | audit/status용 요약 정보. replay source of truth가 아닙니다. |
| `attemptCount` | replay 시도 횟수 |
| `lastAttemptAt` | 마지막 replay 시도 시각 |
| `lastFailure` | 마지막 실패 reason/message/time |

Replay target은 `payloadBase64`를 decode한 뒤 `payloadEncoding`에 따라 string 또는 Buffer로 복원해 upstream Socket.IO `send_data` event를 emit합니다.

## 8. State, outcome, failure reason

### 8-1. Ingress outcome

Ingress outcome은 수신 시점의 결과입니다.

| Outcome | 의미 |
|---|---|
| `accepted` | ingress가 payload를 수신했고 spool 시도를 시작할 수 있습니다. |
| `spooled` | durable spool 기록이 완료되었습니다. |
| `rejected` | backpressure 정책으로 spool 기록을 거부했습니다. |
| `invalid_payload` | Socket.IO event 또는 binary attachment를 spool item으로 만들 수 없습니다. |
| `spool_write_failed` | spool 저장소 쓰기가 실패했습니다. |

`accepted`와 `spooled`는 같은 의미가 아닙니다. `accepted` 이후 Redis append가 실패하면 `spool_write_failed`로 남아야 하고, 성공처럼 집계하면 안 됩니다.

### 8-2. Spool item state

| State | 의미 |
|---|---|
| `pending` | durable spool에 저장되었고 replay 대기 중입니다. |
| `in_flight` | replay worker가 upstream 전달을 시도 중입니다. |
| `replayed` | upstream 전달이 완료된 terminal state입니다. |
| `retryable_failed` | upstream 또는 일시적 의존성 실패로 retry 대상입니다. |
| `dead_lettered` | 더 이상 retry하지 않는 terminal state입니다. |

Terminal state는 `replayed`, `dead_lettered`뿐입니다. `retryable_failed`는 실패 evidence이지만 아직 회복 가능한 pending work입니다.

### 8-3. Failure reason

| Reason | 의미 |
|---|---|
| `invalid_payload` | payload나 spool document를 replay 가능한 item으로 만들 수 없음 |
| `spool_unavailable` | spool 저장소가 준비되지 않았거나 claim할 수 없음 |
| `spool_full` | backpressure limit 초과 |
| `spool_write_failed` | spool write/move 명령 실패 |
| `upstream_unavailable` | upstream app에 접속할 수 없음 |
| `upstream_timeout` | upstream Socket.IO 연결 또는 replay timeout |
| `upstream_rejected` | upstream이 명시적으로 거부 또는 오류 응답 |
| `replay_session_unavailable` | replay에 필요한 Socket.IO session/context를 만들 수 없음 |

이 reason들은 서로 대체하지 않습니다. 예를 들어 upstream이 down된 상태에서 spool write가 성공했다면 `spool_write_failed`가 아니라 replay failure로 남아야 합니다.

## 9. Backpressure policy

Backpressure는 pending spool이 무제한 커지는 것을 막기 위한 정책입니다. 현재 구현은 아래 조건을 검사합니다.

| 조건 | Action | Failure reason |
|---|---|---|
| spool enabled이고 limit 안쪽 | `accept` | 없음 |
| 단일 payload가 `maxPayloadBytes` 초과 | `reject` | `spool_full` |
| pending item 수가 `maxPendingItems` 이상 | `reject` | `spool_full` |
| pending bytes + payload bytes가 `maxPendingBytes` 초과 | `reject` | `spool_full` |

현재 구현은 `dead_letter_oldest` action을 실행하지 않습니다. 오래된 item을 자동으로 drop하거나 dead-letter로 옮기는 정책은 운영자가 명시적으로 선택한 뒤 별도 구현되어야 합니다. 기본 동작은 silent drop이 아니라 reject evidence를 남기는 것입니다.

Mode에 따라 reject의 의미도 다릅니다.

- `mirror_spool`: upstream direct relay는 유지됩니다. 따라서 `rejected`는 network 수신 거부가 아니라 "mirror spool 기록을 거부했다"는 evidence입니다.
- `spool_only` / `spool_and_replay`: upstream direct relay는 제거됩니다. 현재 구현은 client에게 별도 Socket.IO ack/error를 돌려주지 않으므로, reject는 status와 metrics에서 확인해야 합니다.

## 10. Replay worker

Replay worker는 Redis pending list에서 item을 claim해 upstream으로 재전송합니다.

```text
RPOPLPUSH pending -> in_flight
  -> decode JSON document
  -> validate replayable item
  -> mark attempt: state=in_flight, attemptCount += 1
  -> emit upstream Socket.IO send_data
  -> success: move in_flight -> replayed
  -> retryable failure: move in_flight -> pending
  -> invalid/max attempts: move in_flight -> dead_letter
```

Replay worker는 tick마다 `min(batchSize, rateLimitPerSecond)`개까지 처리합니다. 따라서 `RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND`만 높이고 `RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE`를 기본값 `1`로 두면 실제 처리량은 tick마다 1개로 제한됩니다.

Upstream replay는 새 Socket.IO client connection을 만들고 `send_data` event를 emit한 뒤 connection을 닫습니다. Upstream handler가 ack를 제공하지 않으므로 replay 성공은 "emit 완료"입니다. Upstream 내부 처리 성공을 의미하지 않습니다.

## 11. Runtime 설정

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `RECORDER_INGRESS_SEND_DATA_MODE` | `spool_and_replay` | `passthrough`, `mirror_spool`, `spool_only`, `spool_and_replay` 중 하나 |
| `RECORDER_INGRESS_SEND_DATA_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:pending` | durable `send_data` spool Redis List key |
| `RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:in_flight` | replay worker가 claim한 item의 in-flight Redis List key |
| `RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:replayed` | replay 완료 item Redis List key |
| `RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:dead_letter` | retry하지 않는 dead-letter item Redis List key |
| `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS` | `10000` | pending spool item limit |
| `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES` | `536870912` | pending spool byte limit |
| `RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES` | `10485760` | 단일 `send_data` payload spool limit |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED` | mode 기반 | 빈 값이면 `spool_and_replay`에서 활성화, 그 외 mode에서 비활성화 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS` | `1000` | replay worker tick interval |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE` | `1` | worker tick마다 처리할 최대 item 수 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS` | `3` | retry 후 dead-letter로 전환할 최대 replay 시도 수 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND` | `1` | worker tick에서 적용하는 replay rate limit |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS` | `5000` | upstream Socket.IO replay 연결 timeout |

현재 구현은 mode와 numeric env에 documented default/fallback을 사용합니다. 즉 invalid mode나 invalid number가 process startup failure가 되지는 않습니다. 이 점은 "외부 상태를 성공으로 숨기지 않는다"는 runtime/domain 원칙과는 별개로, 설정 parser의 현재 구현 상태입니다. 이후 strict config validation을 도입하면 invalid config를 명시 실패로 승격할 수 있습니다.

## 12. Status 읽는 법

Recorder ingress `/recorder-ingress/status`는 전체 상태와 recorder별 상태를 함께 제공합니다.

- `spool`: 전체 spool 상태
- `replay`: 전체 replay 상태
- `recorders[].spool`: recorder별 spool 상태
- `recorders[].replay`: recorder별 replay 상태

중요한 필드는 아래처럼 읽습니다.

| Field | 정상 해석 | 주의해야 할 해석 |
|---|---|---|
| `spool.status` | `ready`면 spool write가 가능한 상태 | `degraded`는 reject가 있었거나 일부 실패가 있었다는 뜻입니다. `failed`는 write failure가 있었다는 뜻입니다. |
| `spool.pendingItems` / `pendingBytes` | replay 대기 중인 backlog | 계속 증가하면 replay 처리량이 입력보다 낮거나 upstream 장애가 있을 수 있습니다. |
| `spool.oldestPendingAgeSeconds` | 가장 오래된 pending item age | 증가하면 replay lag가 쌓이는 중입니다. |
| `spool.rejectedEvents` | backpressure reject count | overload를 숨기지 않고 드러낸 evidence입니다. |
| `spool.writeFailures` | Redis append/move 실패 count | upstream 장애가 아니라 spool 저장소 문제입니다. |
| `replay.status` | `idle` 또는 `replaying`이면 worker가 동작 중 | `degraded`는 retry/dead-letter가 있었다는 뜻입니다. `failed`는 claim/store command 실패가 있었다는 뜻입니다. |
| `replay.pendingItems` | replay 관점의 pending count | spool pending과 함께 봐야 합니다. |
| `replay.inFlightItems` | claim 후 처리 중인 item 수 | 오래 유지되면 worker crash나 store move 실패를 의심해야 합니다. |
| `replay.retryableFailures` | retry 대상 실패 count | upstream unavailable/timeout이 반복될 때 증가합니다. |
| `replay.deadLetteredEvents` | terminal failure count | invalid spool document나 retry 한도 초과를 확인해야 합니다. |
| `replay.replayLagSeconds` | replay 완료 또는 실패 item의 lag | 부하 종료 뒤 감소해야 합니다. 계속 증가하면 replay 처리량이 부족합니다. |
| `lastFailure` | 마지막 실패 reason/message/time | 실패 종류를 operator가 판단하는 1차 evidence입니다. |

macOS Helper의 Status 탭은 Redis를 직접 읽지 않습니다. Host UI는 Guest 내부 Redis key 구조를 추측하지 않고, recorder ingress가 `/recorder-ingress/status`로 제공한 `spool`/`replay` read model만 표시합니다. 이 경계가 있어야 Redis key 이름이나 list layout이 바뀌어도 Host UI가 Guest 내부 저장소 구현에 묶이지 않습니다.

Status 탭의 `Recorder ingress queue` 항목은 전체 queue 상태를 요약합니다.

| Helper 표시 | 의미 |
|---|---|
| `healthy, 0 pending` | status 계약에 queue field가 있고 현재 replay backlog가 없습니다. |
| `draining, N pending, oldest ..., replay lag ...` | backlog가 있으며 replay worker가 따라잡는 중입니다. pending이 있다는 사실만으로 upstream 장애는 아닙니다. |
| `degraded, ... rejected/retryable failures ...` | backpressure reject 또는 upstream retryable failure evidence가 있습니다. 입력 속도, replay rate, upstream 상태를 함께 봐야 합니다. |
| `failed` 또는 `dead letters` 포함 | spool write failure나 terminal replay failure가 있어 운영자가 확인해야 합니다. |
| `Not reported` | recorder ingress status는 읽혔지만 `spool`/`replay` field가 없습니다. 실제 `0 pending`으로 해석하지 않습니다. |
| status read error | `/recorder-ingress/status` 자체를 읽지 못했습니다. queue가 비었다는 뜻이 아닙니다. |

OpenAPI schema는 `docs/api/recorder-ingress.openapi.yaml`에 있습니다.

## 13. 검증 방법

### Unit/integration proof

Recorder ingress tests는 아래 계약을 확인해야 합니다.

- mode/outcome/state/reason enum이 OpenAPI와 일치함
- spool item이 `payloadBase64`, `payloadEncoding`, `vrcode`, correlation id를 보존함
- invalid payload가 success로 축소되지 않음
- backpressure limit 초과가 `rejected`와 `spool_full`으로 남음
- replay 성공은 `replayed`, upstream 장애는 retry, invalid/max attempts는 `dead_lettered`가 됨
- `spool_only`/`spool_and_replay`에서 client `send_data` frame과 binary attachment가 upstream direct relay에서 제거됨

### Compose replay proof

Compose 환경 proof는 실제 `recorder-ingress`, upstream `app`, `redis`, testkit Socket.IO client를 함께 사용해 `spool_and_replay` 경로를 확인합니다.

```sh
make testkit/recorder-ingress/replay
```

성공 조건은 testkit stream이 보낸 `send_data` 수만큼 이번 실행의 recorder ingress status delta에서 `sendDataEventsObserved`, `spooledEvents`, `replayedEvents`가 증가하고, `pending`/`in_flight` 상태가 비어 있으며 Redis `dead_letter` list가 비어 있는 것입니다.

### Load proof

```sh
make testkit/recorder-ingress/load
```

이 proof는 `spool_and_replay`에서 5 recorder x 100 `send_data`를 보내고, observed/spooled/replayed delta, Redis `dead_letter` 부재, replay lag, app container `oomKilled=false`, restart count 불변을 확인합니다. replay interval/rate/batch를 함께 명시해 load 종료 후 pending spool이 drain 되는지도 확인합니다.

### Backpressure proof

```sh
make testkit/recorder-ingress/backpressure
```

이 proof는 의도적으로 `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS=1`과 낮은 replay rate를 사용해 `rejectedEvents` delta가 증가하는지 확인합니다. 성공은 모든 event가 replay된다는 뜻이 아닙니다. overload를 숨기지 않고 `spool_full` 계열 rejection evidence로 노출한다는 뜻입니다.

## 14. 현재 한계와 후속 작업

현재 구현과 목표 계약 사이에는 의도적으로 남겨둔 경계가 있습니다.

- Client-visible reject가 없습니다. `spool_only`/`spool_and_replay`에서 spool write나 backpressure reject가 발생해도 client에게 Socket.IO ack/error를 돌려주지 않습니다. 운영자는 status evidence로 확인해야 합니다.
- Spool write와 frame suppression은 같은 transaction이 아닙니다. `spool_and_replay`에서 spool write 실패가 발생해도 upstream direct fallback relay를 하지 않습니다.
- Config parser는 documented default/fallback을 사용합니다. strict invalid config failure는 별도 작업입니다.
- `dead_letter_oldest` 같은 backlog pruning policy는 현재 구현되어 있지 않습니다. 기본은 reject evidence를 남기는 것입니다.
- Replay 성공은 upstream emit 완료입니다. Upstream 내부 Redis write/domain success를 보장하지 않습니다.

이 한계는 fallback으로 상태를 숨기기 위한 것이 아닙니다. 현재 구현이 소유하는 상태와 아직 소유하지 않는 상태를 구분하기 위한 경계입니다.
