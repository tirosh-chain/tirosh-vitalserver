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

Replay는 upstream 처리량을 조절하는 지점입니다. Worker는 tick interval, batch size, byte throughput limit에 맞춰 upstream으로 보내므로, VRecorder가 빠르게 보낸 burst를 upstream이 감당 가능한 속도로 바꿀 수 있습니다.

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

이때 Redis write path도 flow control의 일부입니다. Recorder ingress가 `send_data`를 받을 때마다 spool append, audit append, recorder IP sync 같은 Redis command를 실행하는데, 이 command마다 새 TCP connection을 만들면 큰 burst에서 connection storm이 먼저 병목이 됩니다. 그러면 VitalServer OOM 경계를 보기도 전에 `redis command timeout`, `EADDRNOTAVAIL`, `spool_write_failed`가 증가하고, replay할 item 자체가 Redis에 충분히 들어가지 못합니다.

그래서 recorder ingress의 Redis adapter는 persistent connection과 FIFO command queue를 사용합니다. Redis가 잠깐 끊기거나 timeout이 나면 retry/backoff/jitter를 적용한 뒤 최종 실패만 `spool_write_failed`, `auditWriteFailures`, `spool_unavailable` 같은 명시적 evidence로 올립니다. 이 retry는 실패를 성공으로 바꾸는 fallback이 아닙니다. 일시적인 transport 실패를 재시도하되, queue overflow나 최종 write failure는 그대로 상태에 남겨 운영자가 "upstream이 느린 것"과 "spool 저장소가 쓰기 실패한 것"을 구분할 수 있게 하는 가용성 장치입니다.

또 하나 중요한 경계는 Redis command queue를 용도별로 분리하는 것입니다. `send_data` spool/replay, audit append, recorder IP sync가 하나의 Redis client queue를 공유하면 audit이나 IP sync처럼 부가적인 관측 write가 몰렸을 때도 `send_data` spool append가 같은 in-process queue 상한에 걸릴 수 있습니다. 그러면 실제로는 Redis 전체가 죽은 것이 아니라 recorder ingress 내부의 공유 command queue가 꽉 찬 상황인데, replay할 원본 payload 자체가 저장되지 못합니다. 현재 구조는 `send_data`, audit, identity sync가 각각 별도의 persistent Redis client와 command queue를 사용합니다. 그래서 audit write failure가 늘어도 critical path인 `send_data` spool/replay queue를 직접 소모하지 않습니다.

`send_data` spool append에서 Redis command queue가 꽉 찬 경우는 일반적인 `spool_write_failed`가 아니라 backpressure로 취급합니다. 이 경우 ingress는 `spool_full` reason과 `rejected` outcome을 남기고, `writeFailures`가 아니라 `rejectedEvents`로 집계합니다. 의미가 다르기 때문입니다. `spool_write_failed`는 저장소 write가 실패한 것이고, `spool_full`은 지금 더 받으면 명시적으로 보호해야 하는 흐름 제어 한계에 도달했다는 뜻입니다.

### 3-3. ingest 단계에서는 payload를 upstream처럼 깊게 처리하지 않는다

Recorder ingress가 spool item을 만들 때 payload를 waveform/trend domain으로 해석하지 않습니다. Replay의 source of truth는 원본 compressed payload bytes를 담은 `payloadBase64`입니다. Audit과 routing에 필요한 요약은 만들 수 있지만, upstream처럼 room별 `JSON.stringify`, `gzipSync`, Redis frame write, UI broadcast, filter/trend 계산을 수행하지 않습니다.

그래서 ingest 단계의 메모리 사용은 upstream 처리와 성격이 다릅니다. Upstream은 payload 하나를 실제 VitalServer domain 처리로 확장하지만, recorder ingress는 "나중에 upstream으로 다시 보낼 원본 일감"을 보존합니다. 이 차이 때문에 VRecorder burst가 들어오는 순간에 upstream 수준의 object expansion과 broadcast buffer가 만들어지지 않습니다.

### 3-4. replay worker가 VitalServer memory를 보면서 upstream 유입 속도를 제한한다

Replay worker는 pending item을 한 번에 무제한 꺼내지 않습니다. 설정된 interval마다 실행되고, adaptive controller가 결정한 byte budget, item budget, concurrency budget을 함께 적용합니다. Claim한 item은 `pending -> in_flight`로 이동한 뒤 upstream Socket.IO `send_data`로 emit되고, 결과에 따라 `replayed`, `requeued`, `dead_letter`로 정리됩니다. Item 하나를 claim하기 전에는 그 item의 정확한 payload size를 알 수 없기 때문에 payload size는 "이번 tick에서 byte budget을 넘었는지" 확인하는 회계값으로만 사용합니다. 얼마나 많이 claim하고 동시에 몇 개를 upstream으로 보낼지는 payload 평균이 아니라 VitalServer memory guard, queue growth, replay failure가 결정합니다.

이 구조에서는 VRecorder 입력 속도와 upstream 입력 속도가 분리됩니다.

```text
VRecorder input rate: burst 가능
Redis pending growth: backpressure limit까지 명시적으로 증가
upstream replay throughput: memory guard가 허용한 worker budget으로 제한
```

따라서 upstream은 "VRecorder가 지금 보내는 속도"가 아니라 "replay worker가 현재 VitalServer memory 상태에서 허용한 replay budget"으로만 `send_data`를 받습니다. VitalServer memory가 낮고 queue가 늘면 budget을 올리고, memory가 높거나 replay failure가 보이면 budget을 낮춥니다. 이 방식은 section 2에서 설명한 inflate/parse/Redis/UI/filter 작업이 한꺼번에 쌓이는 상황을 줄이면서도, memory 여유가 있을 때는 20대 recorder의 작은 `send_data` item을 초당 10개 같은 낮은 고정 batch에 묶어두지 않습니다.

### 3-5. 과부하는 성공처럼 숨기지 않고 명시적인 상태가 된다

`spool_and_replay`의 목표는 모든 입력을 무조건 성공으로 받는 것이 아닙니다. Redis pending list도 한계가 있으므로 `maxPayloadBytes`, `maxPendingItems`, `maxPendingBytes`를 넘으면 ingress는 `rejected` outcome과 `spool_full` reason을 남깁니다.

Upstream이 내려가 있거나 느리면 replay item은 retry되거나 retry 한도를 넘은 뒤 `dead_letter`가 됩니다. Spool write 실패, invalid payload, replay retryable failure, dead letter는 서로 다른 의미로 남습니다. 이 구분이 있어야 운영자가 "입력이 너무 많았는지", "Redis가 실패했는지", "upstream 연결이 실패했는지", "payload 자체가 invalid인지"를 분리해서 볼 수 있습니다.

정리하면 아래와 같습니다.

| upstream 메모리 압력 지점 | spool_and_replay가 바꾸는 점 |
|---|---|
| VRecorder burst가 upstream Socket.IO queue로 바로 들어감 | `send_data` direct relay를 제거하고 Redis pending list에 먼저 저장 |
| payload가 즉시 inflate/string/object/room buffer로 확장됨 | ingest 단계에서는 원본 compressed payload를 replay item으로 보존 |
| room별 UI broadcast와 Redis write가 burst 속도로 생성됨 | replay worker가 VitalServer memory guard를 보고 upstream으로 보내는 byte/item budget을 제한 |
| backlog가 Node heap, Redis client queue, Socket.IO queue에 섞임 | `pendingItems`, `pendingBytes`, lag, failure counter로 읽히는 명시적 queue로 이동 |
| 과부하가 OOM이나 502로 늦게 드러남 | `spool_full`, `rejected`, retry, dead letter로 조기에 드러남 |

단, `spool_and_replay`가 upstream 내부 처리 비용을 없애는 것은 아닙니다. Replay된 item은 결국 upstream에서 section 2의 inflate/parse/Redis/UI/filter 경로를 탑니다. 이 해결책의 본질은 비용 제거가 아니라 burst 흡수, 유입 속도 제한, backlog 가시화, 과부하의 명시적 실패화입니다.

### 3-6. replay 속도를 운영자가 조절할 수 있게 한다

`spool_and_replay`를 적용하면 `send_data`는 더 이상 VRecorder에서 upstream으로 바로 들어가지 않습니다. 중간에 recorder ingress가 있고, 이 ingress가 "먼저 받아서 안전하게 쌓아두고, upstream이 감당할 수 있는 속도로 다시 보내는" 역할을 합니다.

그래서 recorder ingress는 단순한 proxy가 아닙니다. 기존에는 upstream이 한 번에 떠안던 일을 아래처럼 나눠 맡습니다.

- VRecorder가 보낸 원본 `send_data` payload를 upstream으로 즉시 넘기지 않고 Redis spool item으로 저장합니다.
- 아직 upstream으로 보내지 않은 payload를 `pending` queue로 관리합니다.
- replay worker가 `pending` item을 하나씩 꺼내 upstream Socket.IO `send_data`로 다시 보냅니다.
- worker가 한 번에 claim할 수 있는 내부 item 수와, 초당 upstream으로 replay할 수 있는 payload byte 상한을 함께 제한합니다.
- queue가 얼마나 쌓였는지, 가장 오래된 item이 얼마나 오래 기다렸는지, retry/dead letter가 있는지를 status로 보여줍니다.

이 구조의 핵심은 `send_data` 입력 속도와 upstream 처리 속도를 분리하는 것입니다. VRecorder가 순간적으로 많이 보내더라도 upstream은 replay worker가 허용한 만큼만 받습니다. 대신 그 차이만큼 Redis pending queue가 늘어납니다.

여기서 중요한 균형이 생깁니다. Replay 속도가 너무 낮으면 upstream은 편하지만 pending queue가 계속 쌓이고, UI가 보는 데이터는 늦어집니다. Replay 속도가 너무 높으면 pending은 빨리 줄지만 upstream은 다시 section 2에서 설명한 inflate, JSON parse, Redis 갱신, UI broadcast, filter/trend 처리를 한꺼번에 많이 수행하게 됩니다. 그래서 replay 속도는 "높을수록 좋은 값"이 아니라, upstream이 지속적으로 버틸 수 있는 속도에 맞춰 조절해야 하는 값입니다.

현재 Helper Settings는 이 균형점을 최대한 단순하게 드러냅니다. 운영자가 평소에 만지는 것은 `Recorder load control`과 `Max replay throughput`입니다. 내부적으로는 worker tick, item budget, retry limit 같은 값도 있지만, 일반 운영 UI에서 모두 노출하면 "무엇을 조절해야 하는지"가 흐려집니다. 그래서 기본 운영 판단은 "load control을 켤 것인가"와 "켜져 있을 때 upstream으로 초당 몇 MiB까지 replay할 수 있게 할 것인가"로 줄입니다.

| 설정 | 쉽게 말하면 | 너무 낮으면 | 너무 높으면 |
|---|---|---|---|
| `Recorder load control` | `send_data`를 바로 upstream으로 보내지 않고 spool 후 replay할지 | Off면 기존처럼 burst가 upstream에 바로 들어갑니다. | On 자체가 문제는 아니지만 current replay throughput이 낮으면 queue가 쌓입니다. |
| `Max replay throughput` | adaptive controller가 올릴 수 있는 초당 replay byte 상한 | 입력 throughput보다 낮으면 pending과 replay lag가 계속 증가합니다. | upstream 내부 queue와 heap pressure가 다시 커질 수 있습니다. |
| `Container memory limits` | `app`, `recorder-ingress`, `redis` container에 Docker hard memory limit을 걸지 | Off면 각 container의 명시 limit이 없고 Status에는 `unknown limit`으로 보입니다. | 너무 낮으면 정상 처리 중에도 해당 container가 OOM kill될 수 있습니다. |

기본 `Max replay throughput`은 `20 MiB/s`입니다. 이 값은 "항상 안전한 최대치"가 아니라, `10 MiB/s`처럼 너무 보수적인 시작값 때문에 정상적인 입력에서도 queue가 불필요하게 쌓이는 상황을 피하기 위한 기본 상한입니다. 실제 운영값은 recorder 수, payload 크기, upstream CPU/memory, UI client 수, Redis 상태를 보면서 조정해야 합니다. Pending과 replay lag가 계속 증가하는데 upstream memory와 retry/dead letter가 안정적이면 이 값을 더 올릴 수 있고, upstream memory pressure나 timeout이 보이면 낮춰야 합니다.

Helper Settings에서 이 값을 바꾸면 `runtime-settings.json`에 MiB/s 단위로 저장되고, guest compose runner가 bytes/sec로 변환해 recorder ingress 환경변수로 전달합니다. 즉 replay 처리량 상한은 코드에 박힌 숨은 값이 아니라 운영자가 명시적으로 조절하는 runtime 설정입니다. Item budget, retry count, timeout 같은 값은 내부 안전장치와 진단용 설정으로 남아 있지만, 일반 Status/Settings 흐름에서는 `Max replay throughput`이 주 조절점입니다.

`Container memory limits`는 replay throughput과 다른 종류의 설정입니다. Replay throughput은 upstream으로 들어가는 byte 속도를 조절합니다. Container memory limit은 처리 속도를 높이지 않고, 각 container가 사용할 수 있는 memory 상한을 Docker `mem_limit`으로 제한합니다. 따라서 이 값은 queue를 drain 하는 knob이 아니라 과부하가 생겼을 때 upstream `app`, recorder ingress, Redis 중 어느 container가 얼마나 커질 수 있는지를 명시하는 hard guard입니다. 이 기능은 기본적으로 켜져 있습니다. 그래야 guest runtime collector가 VitalServer container의 명시 memory limit을 runtime-state에 기록할 수 있고, recorder ingress adaptive controller가 `healthy/warm/hot/critical`을 추측 없이 계산할 수 있습니다.

Helper Settings는 container limit을 VM memory 대비 percentage slider로 보여줍니다. 세 container의 합계는 VM memory의 `70%`를 넘지 않게 제한합니다. 나머지 약 30%는 guest OS, Docker overhead, filesystem cache, 기타 runtime 여유로 남깁니다.

기본 배분은 Redis를 가장 크게 잡습니다. 8 GiB VM 기준으로 `VitalServer 25%`, `recorder-ingress 5%`, `Redis 40%`이며, MiB로는 대략 `app 2048 MiB + recorder-ingress 410 MiB + redis 3277 MiB`입니다. 이유는 Redis가 spool queue와 replay 대기 데이터를 실제로 들고 있는 container이기 때문입니다. VitalServer는 replay throughput으로 유입 속도를 제한받고, recorder-ingress는 HTTP/WebSocket edge와 replay worker를 실행하지만 backlog 자체를 오래 들고 있지 않습니다. 반대로 Redis가 너무 작으면 upstream을 보호하기 전에 spool 저장소가 먼저 OOM 압박을 받습니다.

UI는 percentage로 보여주지만 Helper는 값을 MiB 단위로 저장하고, guest compose runner는 `compose.runtime-limits.yaml` override를 생성해 `app`, `recorder-ingress`, `redis` service에 적용합니다. 설정을 끄면 override 파일을 제거하며, Status는 VM 전체 메모리를 container limit처럼 추정해서 표시하지 않습니다.

| 경계 | 필드/값 | 단위 | 이유 |
|---|---|---|---|
| Helper Settings | `Max replay throughput` | `MiB/s` | 사람이 조절하는 운영값이므로 binary storage 단위로 표시합니다. |
| Runtime settings document | `recorderIngressSendDataReplayMaxMiBPerSecond` | `MiB/s` 정수 | Helper가 저장하고 CLI/configure가 전달하는 명시 설정입니다. |
| Guest compose env | `RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND` | bytes/sec | recorder ingress process가 바로 계산에 사용할 수 있는 단위입니다. |
| Recorder ingress status/API | `maxBytesPerSecond`, `configuredMaxBytesPerSecond`, `adaptive.currentMaxBytesPerSecond` | bytes/sec | machine-readable contract에서는 단위를 이름에 포함해 오해를 줄입니다. |

Recorder ingress는 이 값을 고정 replay throughput으로만 쓰지 않고 adaptive controller의 byte 상한으로도 사용합니다. 기본 adaptive byte range는 `1 MiB/s..Max replay throughput`입니다. Item budget과 concurrency budget은 별도 사용자 설정이 아니라 controller 내부 출력입니다. VitalServer memory guard가 `healthy`이고 pending queue가 늘면 다음 tick의 effective replay byte throughput, item budget, concurrency budget을 올립니다. VitalServer memory guard가 `warm`이면 급격한 증가를 막고, `hot`이면 낮추며, `critical`이면 최소 budget으로 줄입니다. Memory guard를 읽지 못하거나 stale이면 healthy로 추정하지 않고 보수적인 budget을 사용합니다.

```text
VitalServer memory hot/critical or replay failure observed
  -> lower effective replay byte throughput, item budget, and concurrency within min/max

queue growing, no replay failure, memory guard healthy
  -> raise effective replay byte throughput, item budget, and concurrency within min/max
```

이 controller는 recorder ingress가 직접 관측한 queue/failure 신호와, guest runtime collector가 명시적으로 작성한 runtime-state memory guard를 함께 사용합니다. VitalServer memory는 recorder-ingress가 Docker를 직접 추측해서 읽는 값이 아닙니다. Guest runtime collector가 `docker stats`와 `docker inspect`로 app container memory를 수집해 `/mnt/tirosh/run/runtime-state.json`에 쓰고, compose는 이 파일을 recorder-ingress에 read-only로 mount합니다. Recorder-ingress는 이 explicit document가 loaded이고 stale이 아닐 때만 memory guard input으로 사용합니다. missing, stale, invalid, failed, unavailable은 healthy로 추정하지 않습니다.

Replay target은 upstream Socket.IO connection을 유지합니다. 이 부분은 OOM의 직접 원인을 제거하는 기능은 아닙니다. OOM의 핵심 원인은 upstream이 payload를 압축 해제하고, JSON으로 만들고, Redis를 갱신하고, UI로 broadcast하고, filter/trend 처리를 하면서 같은 데이터를 여러 형태로 확장하는 데 있습니다. Persistent connection은 이 upstream 내부 비용을 없애지 않습니다.

그럼에도 persistent connection은 중요합니다. Replay worker가 item 하나를 보낼 때마다 `connect -> emit -> close`를 반복하면, 실제 payload를 보내는 일 외에 Socket.IO handshake, transport negotiation, connection object 생성과 정리 비용을 매번 냅니다. 이 비용이 커지면 설정상 `20 MiB/s`까지 보낼 수 있어도 worker가 그 byte throughput에 도달하지 못할 수 있습니다. 그러면 upstream이 아직 처리할 여유가 있어도 Redis pending이 남습니다.

같은 upstream으로 계속 replay하는 구조에서는 connection을 유지하고 그 위로 여러 `send_data`를 emit하는 편이 더 자연스럽습니다. 이것은 upstream 내부 처리 비용을 줄이는 것이 아니라, recorder ingress의 replay 단계에서 불필요한 연결 비용을 줄여 pending queue가 더 잘 drain 되도록 돕는 역할입니다.

정리하면 이 설계가 해결하는 문제는 두 가지입니다. 첫째, `spool_and_replay`로 upstream의 즉시 burst 처리를 끊고 backlog를 명시적인 Redis queue로 옮깁니다. 둘째, replay 속도를 설정과 persistent connection으로 조절 가능하게 만들어 upstream 보호와 pending drain 사이의 균형을 운영자가 맞출 수 있게 합니다.

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

기본 운영값은 `spool_and_replay`입니다. Helper Settings는 내부 mode 이름을 그대로 노출하지 않고 `Recorder load control` On/Off로 표현합니다.

- Off: `passthrough`
- On: `spool_and_replay`

`mirror_spool`과 `spool_only`는 내부/CLI/테스트/진단용 mode로 유지하지만, 일반 Settings 화면에서는 선택지로 노출하지 않습니다. 운영자가 기본적으로 판단해야 하는 것은 "Recorder 부하 제어를 켤 것인가"와 "켜져 있을 때 replay 속도를 얼마로 제한할 것인가"입니다.

Helper Settings의 값은 `runtime-settings.json`에 저장되고, guest compose runner가 `RECORDER_INGRESS_SEND_DATA_MODE`와 replay byte throughput 환경변수로 recorder ingress에 전달합니다. 이 설정은 VM restart가 아니라 container service reconcile로 적용됩니다.

`mirror_spool`에서 Redis pending이 늘어나는 것은 "replay worker가 밀려서 소비하지 못하는 backlog"가 아닙니다. 이 mode는 upstream direct relay를 그대로 유지하면서 Redis에 관측용 사본을 남기고, replay를 명시적으로 켜지 않으면 소비자가 없습니다. 따라서 status에서는 이런 상태를 `draining`이 아니라 `mirroring, replay disabled`로 해석해야 합니다. Upstream 메모리 압력을 구조적으로 줄이려면 `mirror_spool`이 아니라 `spool_and_replay`를 사용해야 합니다.

| Mode | Direct upstream relay | Spool write | Replay worker | 용도 |
|---|---:|---:|---:|---|
| `passthrough` | 예 | 아니오 | 아니오 | spool 기능 비활성화. 기존 동작에 가깝습니다. |
| `mirror_spool` | 예 | 예 | 설정에 따름 | 안전한 관측/증거 수집용입니다. Upstream OOM을 구조적으로 막지는 않습니다. |
| `spool_only` | 아니오 | 예 | 아니오 | upstream direct 유입 차단 검증과 cutover 준비용입니다. |
| `spool_and_replay` | 아니오 | 예 | 예 | 목표 운영 mode입니다. |

`spool_only`와 `spool_and_replay`에서는 recorder ingress가 client WebSocket frame을 frame-level로 검사합니다. Socket.IO `send_data` text event와 관련 binary attachment는 upstream direct relay에서 제거하고, `join_vr`, `req_cmd`, control frame 등 다른 frame은 계속 전달합니다.

현재 구현에서 중요한 점은 client frame relay와 spool write가 같은 synchronous transaction이 아니라는 것입니다. Socket.IO audit service가 `send_data`를 관측하면 spool 기록을 비동기로 요청하고, WebSocket relay는 mode에 따라 `send_data` frame을 제거합니다. 따라서 `spool_and_replay`에서 spool write가 실패해도 해당 client frame이 upstream으로 fallback relay되지 않습니다. 실패는 client ack가 아니라 `/recorder-ingress/status`의 spool failure evidence와 send_data failure JSONL로 확인해야 합니다.

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

`invalid_payload`, `rejected`, `spool_write_failed`, `dead_lettered`는 send_data failure JSONL에도 append됩니다. 이 파일은 Redis spool 자체에 쓰지 못한 사건을 보존하기 위한 진단 sink이며, replay source of truth가 아닙니다. 기본 위치는 container 내부 `/var/log/vitalserver-recorder-ingress/failures/send-data-failures.jsonl`입니다. Local Compose는 이를 `./data/recorder-ingress-failures`에 bind mount하고, macOS runtime guest compose는 `/mnt/tirosh/run/recorder-ingress-failures`에 bind mount합니다.

Failure JSONL은 원본 payload를 기본 저장하지 않습니다. 각 line은 `schemaVersion`, `observedAt`, `kind`, `reason`, `message`, `vrcode`, correlation id, payload byte 수, `payloadSha256`, replay attempt 정보를 담습니다. invalid spool document의 경우 raw document 내용 대신 `rawDocumentBytes`와 `rawDocumentSha256`만 남깁니다. 파일 append 자체가 실패하면 `/recorder-ingress/status`의 `failureLogWriteFailures`가 증가하며, 원래 spool/replay failure를 성공으로 바꾸지 않습니다.

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

Replay worker는 tick마다 adaptive item budget, byte budget, concurrency budget을 함께 적용합니다. 과거처럼 낮은 고정 `batchSize`가 남아 있으면 작은 payload가 많은 20대 recorder 환경에서 `20 MiB/s` 상한을 설정해도 실제 replay가 `10 items/sec` 수준에 묶일 수 있습니다. 반대로 item budget만 높이고 upstream emit을 한 번에 하나씩만 보내면 `In flight`가 계속 1에 머물러 connection/emit latency가 병목이 됩니다. 현재 기본 internal batch guard는 `1000 items/tick`, 기본 concurrency guard는 `1..8`입니다. 실제 current item budget과 current concurrency는 memory guard와 queue 상태에 따라 내려가거나 올라갑니다. 기본 byte 상한은 `20 MiB/s`입니다.

Upstream replay target은 upstream VitalServer로 가는 Socket.IO client connection을 유지하고, replay item마다 같은 connection에 `send_data` event를 emit합니다. Connection이 없거나 끊긴 상태면 다음 replay 시점에 새 connection을 만들고, 연결 실패나 timeout은 `upstream_unavailable` 또는 `upstream_timeout` retryable failure로 남깁니다.

이 persistent replay connection은 replay 처리량에 직접적인 영향을 줍니다. 매 item마다 `connect -> emit -> close`를 반복하면 handshake 비용 때문에 byte throughput 상한을 높여도 실제 소비 속도가 낮아질 수 있습니다. Persistent connection은 그 비용을 제거해 worker가 adaptive item budget과 byte budget에 더 가깝게 동작하게 만듭니다.

단, upstream handler가 ack를 제공하지 않으므로 replay 성공은 "Socket.IO emit 완료"입니다. Upstream 내부의 inflate, JSON parse, Redis 갱신, UI broadcast, filter/trend 처리가 끝났다는 뜻은 아닙니다.

### 10-1. 실시간 replay와 `.vital` 원본 복구의 경계

실시간 replay는 VitalServer app을 최신 상태에 가깝게 유지하기 위한 hot path입니다. 이 경로는
VitalServer app의 Socket.IO `send_data` handler가 현재 시점의 live stream을 처리한다는 전제에 묶여
있습니다. VitalServer app이 과거 timestamp payload를 받아 이미 지난 recording 구간의 `.vital` 파일에
정확히 병합한다고 가정하면 안 됩니다.

따라서 heavy 입력에서 실시간성을 유지하기 위해 pending item을 sampling, coalescing, drop-head 같은
정책으로 줄이더라도, 그 item을 원본 데이터에서 버렸다는 뜻이 되면 안 됩니다. 목표 계약은 hot path와
cold path를 분리하는 것입니다.

```text
VRecorder send_data
  -> recorder ingress
     -> cold path: raw append-only archive
     -> hot path: realtime pending projection
        -> sampling/coalescing/drop-head
        -> upstream Socket.IO replay

idle/recovery
  -> raw archive
  -> generated .vital file
  -> VitalServer /upload
  -> VitalServer storage + My Files Redis index
```

Cold path는 recorder ingress가 수신한 원본 compressed payload와 explicit metadata를 append-only로
보존합니다. Raw archive write가 성공한 뒤에만 hot path의 sampling이나 drop을 성공 상태로 볼 수 있습니다.
Raw archive write 실패, permission failure, disk full, decode failure는 실시간 drop과 다른 failure로
남겨야 합니다.

Hot path는 bounded realtime projection입니다. 이 projection은 VitalServer app OOM을 피하기 위해 최신성
위주로 운영합니다. 현재 구현은 Redis pending list의 최신 window를 남기고 replay worker가 최신 item부터
upstream으로 보냅니다. 추가로 최신 window 안에 없는 recorder가 있으면, 버려질 구간에서 그 recorder의
가장 최신 payload 하나를 realtime representative sample로 tail에 보존합니다. 따라서 realtime은 "원본 전체
구간 보존"이 아니라 "active recorder의 최신 상태를 계속 갱신하는 표본 stream"입니다. Heavy 조건에서 replay
처리량보다 입력량이 크면 어떤 원본 payload들은 realtime으로 가지 않습니다. 이때 특정 과거 구간의 원본
완전성은 realtime이 아니라 raw archive와 `.vital` export/upload가 책임집니다.

제품 운영 기준에서는 realtime projection도 무작위 손실처럼 보이면 안 됩니다. 현재 hot path는 최신 window와
recorder representative sample 기반이며, queue가 명시적으로 비었을 때 recorder별 pending metric도 함께 drain
처리합니다. 이 representative sample 때문에 `pendingItems`는 설정한 latest-window 크기보다 recorder 수만큼
조금 커질 수 있습니다. 다음 단계의
정교한 policy는 recorder/track 단위 latest-value coalescing, 시간 bucket별 `first/last/min/max/count`
요약, signal type별 priority sampling을 적용할 수 있습니다. 이때 status 이름도 원본 손실을 뜻하는
`dropped`가 아니라, cold path에 원본이 남아 있는 경우에는 `skippedRealtimeEvents`처럼 실시간 전송
후보에서 제외되었다는 의미를 드러내야 합니다.

Idle/recovery path는 raw archive를 읽어 별도 `.vital` 파일을 생성한 뒤 VitalServer `/upload` 또는
`/upload_vital.php`로 업로드합니다. My Files 목록은 storage directory를 직접 스캔한 결과만으로 결정되지
않고 upload endpoint가 Redis에 생성한 filelist index에 의존하므로, 생성된 `.vital` 파일을 storage
directory에 직접 복사하는 방식은 복구 계약이 아닙니다.

현재 구현은 raw archive JSONL, Redis pending list에 대한 realtime trim, failure log, testkit 기반
수동 `.vital` export/upload 명령, 그리고 recorder ingress auto export worker를 제공합니다. 따라서 현재의
`skippedRealtimeEvents`는 "VitalServer로 realtime replay되지 않은 pending item"을 뜻하며,
`rawArchive.autoExport.status = uploaded`와 checkpoint가 남기 전까지는 운영자가 자동 복구 완료 상태로
해석하면 안 됩니다.

Recorder가 종료되었음을 뜻하는 명시 event는 현재 recorder ingress 계약에 없습니다. 따라서 socket
disconnect, `activeConnections = 0`, 또는 `send_data` silence를 `stopped`, `sleep`, `idle` 같은 recorder
상태로 승격하지 않습니다. 자동화 trigger는 recorder lifecycle 추론이 아니라 raw archive 구간의
`finalizable_by_inactivity` 정책입니다. 기본 정책은 같은 `vrcode`에 대해 join과 raw archive append가
관측되었고, active connection이 없으며, 마지막 raw archive append 이후 5분(`300000ms`) 동안 archive cursor가
안정적이고 realtime replay가 drain되었으며 같은 cursor가 아직 export/upload되지 않은 경우에만 export/upload
후보로 봅니다. 5분이 지나기 전에는 `inactive_candidate`이며, 이 상태도 "종료됨"을 뜻하지 않습니다.

제품화 결정은 다음과 같습니다.

1. recorder ingress process는 raw archive auto export worker를 소유합니다. Worker는 raw archive cursor를
   관측하고, `finalizable_by_inactivity`가 참이면 job document를 만든 뒤 testkit recovery API를 호출합니다.
   Job state, retry state, upload result, checkpoint는
   `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_STATE_PATH` JSON 문서에 남깁니다.
2. 수동 운영 명령도 유지합니다. `recover-raw-archive-vital`은 raw archive JSONL을
   `.vital` 파일로 export한 뒤 VitalServer upload endpoint로 반영합니다. 이 명령은 VitalServer storage를
   직접 쓰지 않고 `/upload` 계약을 사용합니다.
3. 디스크 사용량은 raw archive 운영의 필수 알람 대상입니다. `rawArchive.writeFailures > 0`,
   `rawArchive.status = failed`, 또는 raw archive volume free space가 운영 임계치 아래로 내려가면
   realtime skip을 복구 가능 사건으로 보면 안 됩니다. 먼저 TS-092 runbook 기준으로 archive path,
   filesystem free space, permission, rotation/retention 설정을 확인합니다.
4. Realtime fairness는 현재 SLO 후보를 status로 관측합니다. 제품 SLO 문장은
   "active observed recorder는 최근 60초 안에 최소 1회 realtime replay되어야 한다"입니다.
   현재 구현은 `realtimeCoverage.activeRecordersMissingRecentReplay`로 위반 후보를 노출하지만,
   SLO 위반 시 자동 알람/정책 조치까지는 아직 수행하지 않습니다. 다음 단계에서 이 필드를 Helper/API
   alert로 승격하고, 위반 시 replay budget 또는 recorder별 representative preservation을 조정할지 결정합니다.

### 10-2. 레퍼런스 기준으로 결정한 사항

이 방향은 단순히 오래된 데이터를 버리는 구현 편의가 아니라, stream/backpressure/time-series system에서
반복적으로 쓰이는 경계 분리 패턴을 recorder ingress 상황에 맞춘 것입니다.

| 레퍼런스 | 관련 원칙 | 이 문서의 결정 |
|---|---|---|
| [Akka Streams buffer overflow strategies](https://doc.akka.io/libraries/akka-core/current/stream/operators/Source-or-Flow/buffer.html) | bounded buffer는 `backpressure`, `dropHead`, `dropTail`, `dropNew`, `dropBuffer`, `fail`처럼 overflow 의미를 명시적으로 구분합니다. | Redis pending trim은 암묵적 성공이 아니라 명시적 realtime overflow 정책입니다. 현재 `skippedRealtimeEvents`는 hot path에서 replay 후보가 제거된 사건으로 기록합니다. |
| [Akka Streams conflate/rate transformation](https://doc.akka.io/libraries/akka-core/current/stream/stream-rate.html) | producer가 너무 빠르고 consumer를 backpressure할 수 없을 때 `conflate`로 여러 element를 summary로 합쳐 downstream rate와 분리합니다. | 다음 단계의 hot path는 무조건 drop이 아니라 recorder/track 최신값 coalescing, window summary, priority sampling을 정책으로 선택할 수 있어야 합니다. |
| [Apache Flink back pressure monitoring](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/monitoring/back_pressure/) | downstream이 source보다 느리면 back pressure가 upstream 방향으로 전파되며, idle/busy/backpressured time을 분리해 봅니다. | recorder ingress status는 live input, realtime pending, replay throughput, idle/recovery 가능 상태를 서로 다른 상태로 노출해야 합니다. |
| [InfluxDB downsampling tasks](https://docs.influxdata.com/influxdb/v2/process-data/common-tasks/downsample-data/) | downsampling은 시간 window aggregate를 별도 bucket에 저장해 전체 disk/query 비용을 줄입니다. | hot path sampling은 raw 원본을 대체하지 않습니다. raw archive와 realtime projection은 별도 저장/처리 경로여야 합니다. |
| [TimescaleDB continuous aggregates and real-time aggregates](https://docs2.tigerdata.com/docs/learn/continuous-aggregates) | raw hypertable 위에 continuous aggregate를 만들고, 필요하면 최근 raw와 materialized aggregate를 결합합니다. | `.vital` 복구는 raw archive에서 별도로 산출하고, realtime view는 최신 상태 표시용 projection으로 둡니다. |
| [OpenTelemetry sampling](https://opentelemetry.io/docs/concepts/sampling/) | high-volume telemetry는 head/tail/probabilistic sampling을 조합하되, sampling decision 기준과 운영 비용을 명시합니다. | 생체 데이터도 signal type, 오류/알람 여부, recorder별 volume에 따라 sampling priority를 explicit policy로 둬야 하며 무작위 drop을 기본으로 두지 않습니다. |
| [Signal downsampling and anti-aliasing](https://en.wikipedia.org/wiki/Downsampling_%28signal_processing%29) | 단순 decimation은 aliasing을 만들 수 있고, sample-rate reduction 전에는 저역통과/anti-aliasing 관점이 필요합니다. | waveform을 줄일 때 단순 N번째 sample 유지가 아니라 min/max/last 또는 signal별 downsampling policy를 검토해야 합니다. |

이 레퍼런스들을 기준으로 현재 결론은 다음과 같습니다.

1. 원본 보존과 실시간 전송은 같은 queue에 맡기지 않습니다.
2. Hot path는 bounded realtime projection이며, 최신성/latency를 위해 sampling이나 coalescing을 허용합니다.
3. Cold path는 append-only raw archive이며, `.vital` 복구의 source of truth입니다.
4. Idle/recovery path는 cold path에서 별도 `.vital` 파일을 생성하고 VitalServer `/upload` 계약으로 반영합니다.
5. Raw archive가 없는 상태에서 realtime skip은 복구 가능한 사건이 아니라 replay 손실 사건입니다.
   Raw archive가 있는 상태에서도 `.vital` export worker가 완료되기 전까지는 replay 후보 제외 사건입니다.

수동 proof 명령은 다음 순서입니다.

```bash
uv run vitalserver-testkit export-raw-archive-vital \
  data/recorder-ingress-raw/send-data-raw.jsonl \
  --output-dir /private/tmp/recorder-ingress-vital-export

uv run vitalserver-testkit upload-vital \
  /private/tmp/recorder-ingress-vital-export \
  --vitalserver-url http://127.0.0.1:8080 \
  --endpoint /upload
```

운영자가 한 번에 실행할 때는 아래 명령을 사용합니다.

```bash
uv run vitalserver-testkit recover-raw-archive-vital \
  data/recorder-ingress-raw/send-data-raw.jsonl \
  --output-dir /private/tmp/recorder-ingress-vital-export \
  --vitalserver-url http://127.0.0.1:8080 \
  --endpoint /upload
```

`export-raw-archive-vital`은 raw archive JSONL의 `payloadBase64`를 inflate하고 vrcode별 `.vital` 파일을
생성합니다. 이 명령은 VitalServer storage를 직접 쓰지 않습니다. 반영은 `upload-vital`이 `/upload`
응답 body `success`를 확인하는 방식으로 수행합니다.

## 11. Runtime 설정

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `RECORDER_INGRESS_SEND_DATA_MODE` | `spool_and_replay` | `passthrough`, `mirror_spool`, `spool_only`, `spool_and_replay` 중 하나 |
| `RECORDER_INGRESS_SEND_DATA_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:pending` | durable `send_data` spool Redis List key |
| `RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:in_flight` | replay worker가 claim한 item의 in-flight Redis List key |
| `RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:replayed` | replay 완료 item Redis List key |
| `RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST` | `vitalserver:recorder_ingress:send_data:dead_letter` | retry하지 않는 dead-letter item Redis List key |
| `RECORDER_INGRESS_SEND_DATA_REPLAYED_MAX_ITEMS` | `10000` | 성공한 replay evidence를 최근 N개만 보존합니다. `pending`, `in_flight`, `dead_letter`에는 적용하지 않습니다. |
| `RECORDER_INGRESS_SEND_DATA_REALTIME_MAX_PENDING_ITEMS` | `2000` | 실시간성을 위해 최신 pending N개를 기본 window로 보존합니다. Window에서 빠지는 recorder의 최신 representative sample은 추가 보존될 수 있고, 실제 제거된 오래된 pending만 `skippedRealtimeEvents`로 집계합니다. 실패나 dead-letter가 아닙니다. |
| `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS` | `100000` | pending spool item limit. 작은 payload가 많은 20대 recorder 환경에서 byte 여유가 있는데 item count만으로 조기 reject되는 것을 피하기 위한 기본값입니다. |
| `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES` | `536870912` | pending spool byte limit |
| `RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES` | `10485760` | 단일 `send_data` payload spool limit |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED` | mode 기반 | 빈 값이면 `spool_and_replay`에서 활성화, 그 외 mode에서 비활성화 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS` | `1000` | replay worker tick interval |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE` | `1000` | worker tick마다 claim할 수 있는 내부 item guard. 일반 운영 knob이 아니라 adaptive item budget의 상한 guard입니다. 기존 settings document에 더 낮은 legacy 값이 남아 있어도 guest compose runner는 이 guard minimum 아래로 낮추지 않습니다. |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS` | `3` | retry 후 dead-letter로 전환할 최대 replay 시도 수 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND` | `20971520` | worker tick에서 적용하는 replay byte throughput 상한. 기본값은 `20 MiB/s`입니다. |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS` | `5000` | upstream Socket.IO replay 연결 timeout |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_ENABLED` | `true` | replay failure와 queue growth에 따라 effective replay byte throughput을 조절할지 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_BYTES_PER_SECOND` | `1048576` | adaptive replay throughput 하한. 기본값은 `1 MiB/s`입니다. |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_CONCURRENCY` | `1` | adaptive replay가 동시에 upstream으로 보낼 수 있는 send_data item 수의 하한 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_CONCURRENCY` | `8` | adaptive replay가 동시에 upstream으로 보낼 수 있는 send_data item 수의 상한 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_BYTES_PER_SECOND` | replay max bytes/sec | adaptive replay throughput 상한 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_ITEMS_PER_TICK` | `50` | adaptive item budget 하한 |
| `RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_ITEMS_PER_TICK` | `1000` | adaptive item budget 상한 |
| `RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILE_BYTES` | `536870912` | raw archive active JSONL 파일 회전 크기. `0` 이하면 회전을 비활성화합니다. |
| `RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILES` | `24` | active 파일을 포함한 raw archive 보존 파일 수. 초과한 rotated archive는 오래된 것부터 삭제합니다. |
| `RECORDER_INGRESS_REDIS_TIMEOUT_MS` | `1500` | Redis command/connection timeout. 최종 실패는 spool/audit/IP sync failure evidence로 남습니다. |
| `RECORDER_INGRESS_REDIS_MAX_QUEUE_LENGTH` | `50000` | persistent Redis connection 앞의 in-process command queue 상한. 초과하면 `redis command queue full`로 실패합니다. |
| `RECORDER_INGRESS_REDIS_RETRY_MAX_ATTEMPTS` | `3` | Redis transport timeout/connection failure를 재시도할 최대 횟수 |
| `RECORDER_INGRESS_REDIS_RETRY_BASE_DELAY_MS` | `25` | Redis retry exponential backoff 시작 지연 |
| `RECORDER_INGRESS_REDIS_RETRY_MAX_DELAY_MS` | `500` | Redis retry backoff 상한 |
| `RECORDER_INGRESS_REDIS_RETRY_JITTER_RATIO` | `0.2` | Redis retry가 동시에 몰리지 않도록 적용하는 jitter 비율 |
| `RECORDER_INGRESS_RUNTIME_STATE_PATH` | `/run/tirosh/runtime/runtime-state.json` | VitalServer memory guard를 읽는 explicit runtime-state contract path |
| `RECORDER_INGRESS_RUNTIME_STATE_MAX_AGE_MS` | `15000` | runtime-state가 이보다 오래되면 memory guard를 stale로 보고 healthy로 추정하지 않음 |
| `RECORDER_INGRESS_FAILURE_LOG_ENABLED` | `1` | send_data failure JSONL append 여부 |
| `RECORDER_INGRESS_FAILURE_LOG_PATH` | `/var/log/vitalserver-recorder-ingress/failures/send-data-failures.jsonl` | append-only send_data failure JSONL path |
| `RECORDER_INGRESS_RAW_ARCHIVE_ENABLED` | `1` | `.vital` recovery source가 되는 원본 `send_data` raw archive JSONL append 여부 |
| `RECORDER_INGRESS_RAW_ARCHIVE_PATH` | `/var/lib/vitalserver-recorder-ingress/raw/send-data-raw.jsonl` | append-only raw archive JSONL path. Local Compose는 `./data/recorder-ingress-raw`, macOS runtime은 `vm/data/run/recorder-ingress-raw`에 bind mount합니다. |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_ENABLED` | `0` | raw archive `.vital` export/upload worker enable flag. 현재 product default는 disabled이며, worker가 활성화될 때도 아래 quiet window와 checkpoint 정책을 따라야 합니다. |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_QUIET_MS` | `300000` | 자동 export/upload 후보가 되기 전 필요한 raw archive inactivity window. 이 값은 recorder stopped 추론이 아니라 `finalizable_by_inactivity` 판단에만 사용합니다. |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS` | `60000` | auto export worker scan interval |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_CURSOR_STABLE_MS` | `60000` | 같은 archive cursor가 이 시간 이상 유지되어야 export 후보가 됩니다. |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_RETRY_DELAY_MS` | `60000` | retryable failure 후 다음 시도까지 대기 시간 |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_MAX_ATTEMPTS` | `3` | 한 cursor export/upload job의 최대 시도 횟수 |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_REQUEST_TIMEOUT_MS` | `300000` | testkit recovery API 호출 timeout |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_RECOVER_URL` | `http://testkit:18322/raw-archive/recover-vital` | raw archive `.vital` 생성과 upload를 수행하는 testkit API endpoint |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_VITALSERVER_URL` | `http://app:80` | testkit이 `.vital`을 upload할 VitalServer URL |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_UPLOAD_ENDPOINT` | `/upload` | VitalServer `.vital` upload endpoint |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_OUTPUT_DIR` | `/var/lib/vitalserver-recorder-ingress/recovery/vital-export` | 생성된 `.vital` artifact directory. recorder-ingress와 testkit이 같은 path로 봐야 합니다. |
| `RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_STATE_PATH` | `/var/lib/vitalserver-recorder-ingress/recovery/raw-archive-auto-export-state.json` | job/checkpoint/retry/upload result persistence document |

현재 recorder ingress process의 env parser는 mode와 numeric env에 documented default/fallback을 사용합니다. 즉 invalid mode나 invalid number가 process startup failure가 되지는 않습니다. 단, Helper `runtime-settings.json`에서 guest compose env로 전달되는 `send_data` mode와 replay throughput은 guest compose runner가 먼저 검증합니다. runtime-settings 값이 invalid이면 compose env 생성이 실패하고 recorder ingress를 잘못된 값으로 기동하지 않습니다.

## 12. Status 읽는 법

Recorder ingress `/recorder-ingress/status`는 전체 상태와 recorder별 상태를 함께 제공합니다.

- `spool`: 전체 spool 상태
- `rawArchive`: `.vital` recovery source raw archive 상태
- `replay`: 전체 replay 상태
- `throughput`: 최근 window 기준 `send_data` byte throughput
- `realtimeCoverage`: active recorder가 최근 realtime replay window에서 빠졌는지 보는 coverage 상태
- `recorders[].spool`: recorder별 spool 상태
- `recorders[].replay`: recorder별 replay 상태

중요한 필드는 아래처럼 읽습니다.

| Field | 정상 해석 | 주의해야 할 해석 |
|---|---|---|
| `spool.status` | `ready`면 spool write가 가능한 상태 | `degraded`는 reject가 있었거나 일부 실패가 있었다는 뜻입니다. `failed`는 write failure가 있었다는 뜻입니다. |
| `spool.pendingItems` / `pendingBytes` | replay 대기 중인 backlog | 계속 증가하면 replay 처리량이 입력보다 낮거나 upstream 장애가 있을 수 있습니다. |
| `spool.oldestPendingAgeSeconds` | 가장 오래된 pending item age | 증가하면 replay lag가 쌓이는 중입니다. |
| `spool.skippedRealtimeEvents` | latency 보존을 위해 realtime replay 후보에서 제외한 pending item 수 | raw archive와 `.vital` export 완료를 뜻하지 않습니다. |
| `spool.rejectedEvents` | backpressure reject count | overload를 숨기지 않고 드러낸 evidence입니다. |
| `spool.writeFailures` | Redis append/move 실패 count | upstream 장애가 아니라 spool 저장소 문제입니다. |
| `rawArchive.status` | `ready`면 raw archive append가 가능한 상태 | `failed`면 원본 복구 source write가 실패한 상태라 hot path drop/sampling을 복구 가능으로 보면 안 됩니다. |
| `rawArchive.persistedEvents` / `persistedBytes` | raw archive에 보존한 원본 `send_data` count/bytes | `.vital` 파일 생성이나 upload 완료를 뜻하지 않습니다. |
| `rawArchive.writeFailures` | raw archive append 실패 count | disk full, permission failure, path 문제를 확인해야 합니다. |
| `rawArchive.autoExport.status` | `disabled`, `idle`, `inactive_candidate`, `finalizable_by_inactivity`, `running`, `uploaded`, `retryable_failed`, `failed` 중 하나 | `uploaded`만 해당 cursor의 export/upload 완료를 뜻합니다. |
| `rawArchive.autoExport.activeJob` | 현재 export/upload job document 요약 | `attempts`, `nextAttemptAt`, `lastFailure`로 retry 상태를 확인합니다. |
| `rawArchive.autoExport.lastResult` | 마지막 testkit recovery API response | upload result persistence evidence입니다. |
| `throughput.observedBytesPerSecond` | VRecorder에서 ingress가 관측한 입력 byte rate | item/sec보다 payload 크기를 더 잘 반영합니다. |
| `throughput.replayedBytesPerSecond` | replay worker가 upstream으로 emit한 byte rate | upstream 내부 처리 완료를 뜻하지 않습니다. emit 기준입니다. |
| `throughput.queueGrowthBytesPerSecond` | `spooledBytesPerSecond - replayedBytesPerSecond` | 양수면 backlog가 늘고, 음수면 drain 중입니다. |
| `replay.status` | `idle` 또는 `replaying`이면 worker가 동작 중 | `degraded`는 retry/dead-letter가 있었다는 뜻입니다. `failed`는 claim/store command 실패가 있었다는 뜻입니다. |
| `replay.maxBytesPerSecond` | 현재 effective replay throughput | adaptive가 켜져 있으면 설정값보다 낮아질 수 있습니다. |
| `replay.configuredMaxBytesPerSecond` | 설정으로 들어온 replay throughput 상한 | adaptive 상한의 기준입니다. |
| `replay.adaptive.currentMaxBytesPerSecond` | adaptive controller가 현재 적용 중인 replay throughput | Helper의 `Replay throughput` 행은 이 값을 MiB/s로 표시합니다. |
| `replay.adaptive.currentItemsPerTick` | adaptive controller가 현재 적용 중인 tick당 item claim budget | 작은 payload가 많은 workload에서 실제 replay item/sec 병목을 확인할 수 있습니다. |
| `replay.adaptive.currentConcurrency` | adaptive controller가 현재 적용 중인 upstream send_data 동시 처리 상한 | queue가 늘고 replay throughput이 낮은데 이 값이 낮으면 concurrency budget이 병목입니다. 이 값이 이미 높거나 max인데도 queue가 늘면 upstream 처리 latency나 VitalServer memory guard 상태를 함께 봐야 합니다. |
| `replay.adaptive.memoryGuardStatus` | app container memory guard 상태 | 명시 입력이 없으면 `unavailable`입니다. 추정해서 쓰지 않습니다. |
| `replay.pendingItems` | replay 관점의 pending count | spool pending과 함께 봐야 합니다. |
| `replay.inFlightItems` | claim 후 처리 중인 item 수 | 오래 유지되면 worker crash나 store move 실패를 의심해야 합니다. |
| `realtimeCoverage.activeRecordersMissingRecentReplay` | 빈 배열이면 현재 연결된 observed recorder가 coverage window 안에서 최소 한 번 replay됐습니다. | 값이 있으면 해당 recorder는 live input은 있지만 최근 realtime replay가 없습니다. raw archive 보존과 별개로 realtime SLO 위반 후보입니다. |
| `realtimeCoverage.minReplayedEventsPerRecorder` / `maxReplayedEventsPerRecorder` | recorder별 realtime replay 분포 | min이 0이면 특정 recorder가 process 시작 이후 realtime replay를 받지 못했습니다. 분포가 크게 벌어지면 fair sampling 정책이 필요합니다. |
| `replay.retryableFailures` | retry 대상 실패 count | upstream unavailable/timeout이 반복될 때 증가합니다. |
| `replay.deadLetteredEvents` | terminal failure count | invalid spool document나 retry 한도 초과를 확인해야 합니다. |
| `replay.replayLagSeconds` | replay 완료 또는 실패 item의 lag | 부하 종료 뒤 감소해야 합니다. 계속 증가하면 replay 처리량이 부족합니다. |
| `lastFailure` | 마지막 실패 reason/message/time | 실패 종류를 operator가 판단하는 1차 evidence입니다. |

macOS Helper의 Status 탭은 Redis나 raw archive 파일을 직접 읽지 않습니다. Host UI는 Guest 내부 Redis key 구조나 파일 layout을 추측하지 않고, recorder ingress가 `/recorder-ingress/status`로 제공한 `spool`/`rawArchive`/`replay` read model만 표시합니다. 이 경계가 있어야 Redis key 이름, list layout, archive layout이 바뀌어도 Host UI가 Guest 내부 저장소 구현에 묶이지 않습니다.

Guest runtime state는 container별 memory 관측값도 제공합니다. Helper Status의 Resource usage 섹션은 VM 전체 메모리와 별도로 upstream `app` container, `recorder-ingress` container, `redis` container의 memory 사용량을 표시합니다. 여기서 중요한 대상은 upstream `app` container입니다. OOM 위험은 VM 전체 free memory만으로 판단하기 어렵고, 실제로 section 2의 무거운 `send_data` 처리를 수행하는 Node process가 들어 있는 container의 `memoryUsedBytes / memoryLimitBytes`를 같이 봐야 합니다.

`memoryLimitBytes`는 `docker inspect HostConfig.Memory`에서 읽은 명시 container hard limit입니다. `docker stats`가 표시하는 limit은 container limit이 없을 때 VM 또는 cgroup 전체 상한처럼 보일 수 있으므로, Helper는 그 값을 container hard limit으로 승격하지 않습니다. `memoryLimitBytes`가 없거나 `memoryUsedBytes`를 읽지 못한 경우 Helper는 이 값을 추정해서 채우지 않습니다. Status에는 해당 container memory가 `Not checked` 또는 `unknown limit`으로 남아야 합니다. Adaptive replay를 도입할 때도 같은 원칙을 지켜야 합니다. memory guard는 명시적으로 읽은 container memory만 기준으로 삼고, 누락된 값을 VM 메모리나 오래된 관측값으로 대신하면 안 됩니다.

Status 탭의 `Recorder ingress queue` 항목은 전체 queue 상태를 요약합니다.

| Helper 표시 | 의미 |
|---|---|
| `healthy, 0 pending` | status 계약에 queue field가 있고 현재 replay backlog가 없습니다. |
| `draining, N pending, oldest ..., replay lag ...` | backlog가 있으며 replay worker가 따라잡는 중입니다. pending이 있다는 사실만으로 upstream 장애는 아닙니다. |
| `degraded, ... rejected/retryable failures ...` | backpressure reject 또는 upstream retryable failure evidence가 있습니다. 입력 throughput, replay throughput, upstream 상태를 함께 봐야 합니다. |
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

이 proof는 Issue #68의 최소 운영 목표에 맞춰 `spool_and_replay`에서 20 recorder x 100 `send_data`를 보내고, observed/spooled/replayed delta, Redis `dead_letter` 부재, replay lag, app container `oomKilled=false`, restart count 불변을 확인합니다. replay interval, byte throughput, batch guard를 함께 명시해 load 종료 후 pending spool이 drain 되는지도 확인합니다. 이때 replay throughput 설정은 legacy item/sec env가 아니라 `RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND`로 전달되어야 합니다.

Local Compose proof는 recorder-ingress replay path와 app stability를 확인하는 proof입니다. VitalServer memory-driven adaptive proof는 VM runtime에서 따로 확인해야 합니다. VM proof에서는 guest runtime collector가 `/mnt/tirosh/run/runtime-state.json`에 `app` container의 `memoryUsedBytes`와 명시 `memoryLimitBytes`를 쓰고, recorder-ingress status가 `replay.adaptive.memoryGuardStatus`를 `unavailable`이나 `stale`이 아닌 실제 pressure state로 보고해야 합니다.

runtime-state가 recorder-ingress에 mount된 VM/runtime 환경에서는 status-only proof target으로 memory guard assertion을 함께 확인합니다.

```sh
make testkit/recorder-ingress/runtime-load
```

이 target은 Docker Compose를 직접 재시작하거나 Redis list를 reset하지 않고, recorder-ingress HTTP status를 기준으로 pending drain과 `replay.adaptive.memoryGuardStatus`를 확인합니다. 그래서 시작 baseline의 `spool.pendingItems`, `spool.pendingBytes`, `replay.pendingItems`, `replay.inFlightItems`가 모두 0이어야 합니다. 기존 backlog가 있으면 proof가 애매해지므로 status-only proof는 시작 전에 실패합니다. Status-only proof는 Docker inspect를 사용하지 않으므로 app container restart/OOM stability를 직접 주장하지 않습니다. 성공 JSON의 `proofScope`는 `status-only`, `appStabilityAsserted`는 `false`로 남습니다. Compose container inspect가 가능한 local proof에서는 아래처럼 e2e script를 직접 실행해 app container stability까지 함께 확인할 수 있습니다.

```sh
.venv/bin/python scripts/recorder_ingress_compose_e2e.py \
  --recorders 20 \
  --max-messages 100 \
  --interval 0.02 \
  --replay-batch-size 1000 \
  --replay-max-mib-per-second 20 \
  --replay-timeout 90 \
  --max-replay-lag-seconds 30 \
  --assert-app-stable \
  --require-memory-guard
```

`--require-memory-guard`는 `replay.adaptive.memoryGuardStatus`가 `healthy`, `warm`, `hot`, `critical` 중 하나일 때만 성공합니다. `missing`, `stale`, `invalid`, `failed`, `unavailable`, field 누락은 memory-driven proof가 아닙니다.

### Backpressure proof

```sh
make testkit/recorder-ingress/backpressure
```

이 proof는 의도적으로 `RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS=1`과 낮은 replay throughput을 사용해 `rejectedEvents` delta가 증가하는지 확인합니다. 성공은 모든 event가 replay된다는 뜻이 아닙니다. overload를 숨기지 않고 `spool_full` 계열 rejection evidence로 노출한다는 뜻입니다.

## 14. 현재 한계와 후속 작업

현재 구현과 목표 계약 사이에는 의도적으로 남겨둔 경계가 있습니다.

- Client-visible reject가 없습니다. `spool_only`/`spool_and_replay`에서 spool write나 backpressure reject가 발생해도 client에게 Socket.IO ack/error를 돌려주지 않습니다. 운영자는 status evidence로 확인해야 합니다.
- Spool write와 frame suppression은 같은 transaction이 아닙니다. `spool_and_replay`에서 spool write 실패가 발생해도 upstream direct fallback relay를 하지 않습니다.
- Config parser는 documented default/fallback을 사용합니다. strict invalid config failure는 별도 작업입니다.
- `dead_letter_oldest` 같은 backlog pruning policy는 현재 구현되어 있지 않습니다. 기본은 reject evidence를 남기는 것입니다.
- Replay 성공은 upstream emit 완료입니다. Upstream 내부 Redis write/domain success를 보장하지 않습니다.

이 한계는 fallback으로 상태를 숨기기 위한 것이 아닙니다. 현재 구현이 소유하는 상태와 아직 소유하지 않는 상태를 구분하기 위한 경계입니다.
