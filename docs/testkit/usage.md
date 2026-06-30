# Testkit 사용법

`tirosh-vitalserver-testkit`은 VitalServer에 데이터를 반복 전송하고 처리량과 실패율을 측정하기 위한 Python 패키지입니다. 저장소 전체의 목적은 테스트 자체가 아니라 upstream VitalServer를 제품으로 사용할 수 있는 수준으로 끌어올리는 것이고, testkit은 그 과정에서 실시간 수집, 업로드, relay 경로를 검증하는 도구입니다.

현재 주요 역할은 simulated Vital Recorder data 또는 외부 payload를 Socket.IO `send_data` event로 보내고, VitalServer와 Redis가 운영에 필요한 형태로 반응하는지 확인하는 것입니다.

upstream VitalServer `2.3.4` 코드 기준 API 목록은 [OpenAPI 문서](../api/vitalserver.openapi.yaml)에 정리되어 있습니다. 실시간 monitor data는 HTTP `POST /api/send`가 아니라 Socket.IO `send_data` event로 들어갑니다.

## 준비

VitalServer를 먼저 실행합니다.

```sh
make up
```

포트 충돌이 있다면 `.env`를 사용합니다.

```env
VITALSERVER_PROXY_PORT=8080
VITALSERVER_HTTP_PORT=28080
REDIS_UI_PORT=28081
VITALSERVER_ADMIN_PASSWORD=admin
```

testkit CLI는 `uv run vitalserver-testkit`으로 실행합니다.

```sh
uv run vitalserver-testkit --help
```

반복해서 쓰는 검증 시나리오는 저장소 root의 script와 Makefile target으로 실행할 수 있습니다.

```sh
make testkit-smoke
make testkit-verify
make testkit-load
make testkit-stream
```

내부적으로는 `scripts/test_vitalserver.py`가 `config/testkit.toml`을 읽고 testkit CLI를 호출합니다. 기본값은 파일을 읽지 않고 simulated recorder data를 생성합니다. 기본 config는 recorder 5대와 총 500개 `send_data` event 기준의 load scenario를 바로 실행할 수 있게 잡아 둡니다. stream scenario는 Ctrl+C 전까지 계속 전송합니다. 더 강한 검증이 필요하면 config 파일을 복사해 조정합니다.

```sh
cp config/testkit.toml config/load-test.toml
```

예를 들어 `config/load-test.toml`에서 아래 값을 조정합니다.

```toml
[scenario]
name = "load"

[server]
wait_seconds = 30
poll_interval_seconds = 1

[bed_registry]
state_path = "/var/lib/vitalserver-testkit/bed-registry.json"

[beds]
count = 5

[recorder]
recorders = 5
# 실제 payload를 재현해야 할 때만 지정합니다.
# payload = "path/to/recorder-payload.json"

[transfer]
concurrency = 10
repeat = 100

[stream]
interval_seconds = 1
duration_seconds = 0
```

그리고 해당 config로 실행합니다.

```sh
TESTKIT_CONFIG=config/load-test.toml make testkit-load
```

## 실시간 수집 검증

기본값은 내부 simulated recorder data를 만들어 Socket.IO `send_data` event로 반복 전송합니다. testkit은 room map payload를 upstream VitalServer가 기대하는 `{vrcode, ver, rooms}` 형태로 감싼 뒤 zlib으로 압축해 보냅니다. 실제 장비에서 캡처한 payload를 재현해야 하면 command의 첫 positional argument나 `config/testkit.toml`의 `[recorder].payload`에 JSON 파일 경로를 지정합니다.

TestKit API와 Test 탭에서 쓰는 recorder session 입력은 세 축으로 분리합니다.

| 축 | 의미 | 예 |
| --- | --- | --- |
| `scenario` | 임상적으로 의미 있는 생리 상태 | `normal_monitoring`, `tachycardia`, `hypotension`, `apnea`, `hct_decreasing` |
| `signalQuality` | 생성된 신호 위에 적용하는 품질 filter | `clean`, `noise`, `baseline_wander`, `motion_artifact`, `dropout`, `flatline`, `low_amplitude`, `clipping` |
| `recorderCondition` | 환자 상태가 아닌 recorder/장비 운영 조건 | `normal`, `device_disconnect` |

즉 artifact와 disconnect는 clinical scenario가 아닙니다. 신호 품질은 기존 임상 신호에 filter로 적용하고, recorder disconnect는 별도 operational condition으로 지정합니다.

패키지에 포함된 120초 fixture-backed scenario는 TestKit API의 `/real-recorder-samples`에서 조회하고, session 시작 시 내부적으로 `realSampleKey`로 선택합니다. 화면에서는 데이터 출처나 장비명이 아니라 아래 시나리오 이름으로 노출합니다. TestKit은 `data/`를 자동 탐색하지 않으며, 패키지 fixture 또는 명시 manifest만 사용합니다.

TestKit stream은 source 종류를 직접 분기하지 않고 recorder frame source policy를 거칩니다.

- generated source는 signal profile을 seed로 현재 tick frame을 생성합니다.
- recorded source는 fixture나 `.vital` window의 source timestamp 구간에서 현재 tick에 해당하는 record만 잘라 현재 시간으로 투영합니다.
- static source는 legacy payload replay처럼 명시 payload를 그대로 보내되, 요청한 경우 timestamp shift만 적용합니다.

Bed identity는 source가 소유하지 않습니다. 세션 request의 `bedRoomNames`가 최종 room key와 `roomname`을 정하고, recorded fixture 안의 원본 room name은 playback source metadata일 뿐 VitalServer에 보낼 bed state가 아닙니다. Recorder condition 같은 후처리도 source와 무관한 frame post policy로 적용합니다.

기본 포함 fixture-backed scenario는 아래 6개입니다.

| Scenario | 목적 |
| --- | --- |
| `comprehensive_monitoring` | 넓은 multi-parameter monitoring baseline |
| `high_density_monitoring` | high track count와 export completeness 검증 |
| `hemoglobin_oxygenation` | hemoglobin/oxygenation monitoring 검증 |
| `intermittent_monitoring` | sparse-but-valid monitoring window 검증 |
| `short_recording_review` | 짧은 recording/export edge case |
| `startup_monitoring` | stream startup 구간 sparse data 검증 |

로컬 real sample 묶음을 testkit 기준 데이터로 쓸 때는 dataset manifest와 key를 명시합니다. testkit은 `data/`를 자동 탐색하지 않습니다. 어떤 payload를 쓰는지는 호출자가 `--dataset-manifest`와 `--dataset-key`로 제공해야 하며, 이 선택은 positional payload와 동시에 사용할 수 없습니다.

```sh
uv run vitalserver-testkit list-recorder-dataset \
  data/real-vital-recorder-samples/testkit-dataset-manifest-120s.json
```

```sh
uv run vitalserver-testkit verify-recorder \
  --vitalserver-url http://localhost \
  --dataset-manifest data/real-vital-recorder-samples/testkit-dataset-manifest-120s.json \
  --dataset-key baseline_bx50_primus_high_track
```

120초 real sample payload는 이미 window 안에 여러 record를 담고 있으므로, lifecycle 검증에서 그대로 재생할 때는 `--replay-sample`과 종료 조건을 함께 둡니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --dataset-manifest data/real-vital-recorder-samples/testkit-dataset-manifest-120s.json \
  --dataset-key root_primus_high_track_sphb \
  --replay-sample \
  --max-messages 3
```

제품화 관점에서는 먼저 `verify-recorder`로 “전송된 payload가 VitalServer에서 보이는 상태”까지 확인합니다. 이 명령은 payload를 한 번 전송한 뒤, VitalServer의 UI용 endpoint인 `/vr_devs`에서 bed device metadata가 조회되는지 확인합니다.

```sh
uv run vitalserver-testkit verify-recorder \
  --vitalserver-url http://localhost
```

성공하면 아래처럼 room과 bed id가 출력됩니다.

```text
visible_rooms: 1
visible: room=mnw4anvs4 bed_id=de8d5733096db32506a924ac566c903c343e2338 bytes=...
```

여러 recorder machine이 동시에 붙는 상황은 bed room을 먼저 정한 뒤 `--bed-room-name`으로 명시해서 재현합니다. Bed는 recorder보다 먼저 존재하는 도메인이고, VRecorder payload는 선택된 bed room에만 연결됩니다.

```sh
uv run vitalserver-testkit create-beds --count 5
```

```sh
uv run vitalserver-testkit verify-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --bed-room-name OR-A \
  --bed-room-name OR-B \
  --bed-room-name OR-C \
  --bed-room-name OR-D \
  --bed-room-name OR-E
```

반복 전송량과 처리량을 보고 싶을 때는 `send-recorder`를 사용합니다.

```sh
uv run vitalserver-testkit send-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --bed-room-name OR-A \
  --bed-room-name OR-B \
  --bed-room-name OR-C \
  --bed-room-name OR-D \
  --bed-room-name OR-E \
  --concurrency 10 \
  --repeat 100
```

실제 recorder처럼 `join_vr`를 보내고 계속 흘려보내는 상황은 `stream-recorder`를 사용합니다. 기본값은 Ctrl+C로 중단할 때까지 streaming하며, 검증 자동화에서는 `--duration` 또는 `--max-messages`로 종료 조건을 둡니다. `send-recorder`와 `verify-recorder`는 one-shot `send_data` 확인용이며 VRecorder lifecycle 검증에는 사용하지 않습니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --bed-room-name OR-A \
  --bed-room-name OR-B \
  --bed-room-name OR-C \
  --bed-room-name OR-D \
  --bed-room-name OR-E \
  --interval 1
```

10초 동안만 streaming하려면:

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --bed-room-name OR-A \
  --bed-room-name OR-B \
  --bed-room-name OR-C \
  --bed-room-name OR-D \
  --bed-room-name OR-E \
  --interval 1 \
  --duration 10
```

장시간 soak test는 `elapsed_seconds`, `messages_sent`, `bytes_sent`만으로 성공/실패를 판단하지 않습니다. 같은 run에서 아래 runtime evidence를 함께 보존해야 합니다.

- guest `runtime-state.json`의 app container `oomKilled`, `restartCount`, `finishedAt`, `memoryLimitBytes`
- `/recorder-ingress/status`의 `sendDataEventsObserved`, `sendDataBytesObserved`, `lastSendDataObservedAt`
- Redis memory와 guest HTTP status
- `guest-runtime-state-stale`, `guestHTTP: 502`, recorder-ingress upstream failure 같은 연쇄 증상

Recorder ingress 자체의 spool/replay load proof는 아래 target으로 분리해 실행합니다.

```sh
make testkit/recorder-ingress/load
make testkit/recorder-ingress/runtime-load
make testkit/recorder-ingress/backpressure
```

`load`는 local Docker Compose에서 20 recorder 기준 replay lag와 app container `oomKilled`/restart count를 함께 확인합니다. `runtime-load`는 이미 떠 있는 runtime endpoint를 대상으로 Compose 직접 접근 없이 HTTP status만 사용하고, `--require-memory-guard`로 `replay.adaptive.memoryGuardStatus`가 `healthy`, `warm`, `hot`, `critical` 중 하나인지 확인합니다. `runtime-load`는 Redis list를 reset하지 않으므로 시작 baseline의 `spool.pendingItems`, `spool.pendingBytes`, `replay.pendingItems`, `replay.inFlightItems`가 모두 0이어야 합니다. `backpressure`는 낮은 pending limit에서 `rejectedEvents` delta가 증가하는지 확인합니다. 성공 출력의 `proofScope`, `appStabilityAsserted`, `adaptive.currentMaxBytesPerSecond`, `adaptive.currentItemsPerTick`, `adaptive.currentConcurrency`, `adaptive.memoryGuardStatus`를 함께 보면 proof 범위와 replay 병목을 확인할 수 있습니다.

Python 코드에서 직접 호출할 수도 있습니다.

```python
from tirosh_vitalserver.testkit import (
    build_simulated_recorder_payload,
    create_beds,
    send_realtime_payloads,
)
from tirosh_vitalserver.testkit.adapters.outbound.recorder import emit_send_data
from tirosh_vitalserver.testkit.application.metrics import (
    transfer_failed_requests,
    transfer_successful_requests,
    transfer_total_bytes_sent,
    transfer_total_requests,
)

beds = create_beds(count=1)
payload = build_simulated_recorder_payload(
    room_names=tuple(bed.room_name for bed in beds),
)
summary = send_realtime_payloads(
    "http://localhost",
    payload,
    concurrency=10,
    repeat=100,
    emitter=emit_send_data,
)

print(f"requests={transfer_total_requests(summary)}")
print(f"success={transfer_successful_requests(summary)}")
print(f"failed={transfer_failed_requests(summary)}")
print(f"bytes={transfer_total_bytes_sent(summary)}")
```

주요 인자:

- `concurrency`: 동시에 보내는 요청 수
- `repeat`: 같은 payload를 반복 전송하는 횟수
- `recorders`: payload에서 만들 가상 recorder machine 수
- `bed_room_name`: 연결할 기존/명시적 bed room name. payload 생략 시 필수
- `interval`: streaming mode에서 recorder별 전송 간격
- `duration`: streaming mode 실행 시간; `0`이면 Ctrl+C까지 계속 전송
- `max_messages`: streaming mode에서 recorder별 최대 전송 횟수
- `vrcode`: recorder code; 생략하면 payload의 단일 최상위 key를 사용
- `version`: `ver` field 값; 기본값은 `testkit`
- `shift_time`: 기본값은 `True`; `dt*` timestamp field를 현재 시간 근처로 shift
- `--http`: Socket.IO 대신 HTTP JSON endpoint를 probe할 때 사용

## TestKit API server

Runtime Helper의 Test 탭과 PWA가 TestKit을 제어할 수 있도록 TestKit은 FastAPI server를 제공한다. macOS runtime dev bundle에서는 TestKit을 guest Docker Compose의 `testkit` container로 포함하고, Helper는 VM IP의 `http://<vm-ip>:18322` API를 호출한다. Stable release runtime에서는 TestKit container와 deploy source를 제외한다. 이 server는 virtual VRecorder session의 시작/중지/상태 조회를 담당한다.

```sh
uv run vitalserver-testkit serve \
  --host 127.0.0.1 \
  --port 18322
```

위 명령은 local 개발용이다. Dev runtime에서는 `vitalserver-testkit:0.1.1` container가 `0.0.0.0:18322`로 API를 열고, 생성된 virtual VRecorder는 guest compose network 안에서 `http://edge/`를 대상으로 접속한다.

API는 bed registry와 session lifecycle을 분리한다.

```text
GET  /health
POST /beds
GET  /beds
DELETE /beds
GET  /sessions
POST /sessions
GET  /sessions/{id}
POST /sessions/{id}/stop
DELETE /sessions/{id}
DELETE /sessions
```

Helper Test 탭의 기본 모델은 “virtual VRecorder 1대 = TestKit session 1개”이다. 여러 대를 동시에 실행할 때는 session을 여러 개 생성한다. Bulk 생성은 이후 API에서 여러 session을 한 번에 생성하는 얇은 편의 기능으로 추가한다.

예시 요청:

```json
{
  "roomNames": ["OR-A"]
}
```

```json
{
  "targetUrl": "http://edge/",
  "recorderCount": 1,
  "bedroomName": "OR-A",
  "scenario": "normal_monitoring",
  "window": {
    "durationSeconds": 20
  },
  "output": {
    "exportVital": true,
    "uploadVital": true
  },
  "vrcode": "TEST_VR",
  "intervalSeconds": 1
}
```

TestKit API의 SoT는 “시뮬레이터가 무엇을 실행 중인지”이다. VitalServer가 실제로 recorder를 인식했는지는 기존 `vitaldb-observer`와 Runtime Control API `/vitaldb/recorders` 결과를 기준으로 판단한다.

## `.vital` 파일 업로드 검증

파일 업로드 경로를 확인할 때 사용합니다. upstream 코드 기준 upload endpoint는 `/upload` 또는 `/upload_vital.php`입니다. testkit 기본값은 `/upload`입니다. `.vital` 파일 저장 위치는 VitalServer Helper Settings의 `Vital files directory`가 SoT입니다. My Files 표시 여부는 별도 Redis 조회 index에 의해 결정되며, 이 index는 upload endpoint가 파일 저장과 함께 생성합니다. 따라서 파일을 storage directory에 직접 복사하는 것만으로는 My Files에 표시되지 않을 수 있습니다.

Helper Test 탭의 `Manual .vital upload`는 로컬 `.vital` 파일 여러 개를 선택하고, 파일명 `bedname_yymmdd_hhmmss.vital`에서 bed room name을 추출해 TestKit bed registry에 등록한 뒤, 각 파일을 VitalServer `/upload`로 multipart streaming upload합니다. 이 경로는 파일 저장 위치와 My Files 조회 index를 같은 VitalServer upload 계약으로 갱신하기 위한 기능입니다.

Recorder ingress raw archive JSONL을 `.vital` 파일로 변환한 뒤 같은 upload 계약으로 반영할 수도 있습니다.
이 기능의 제품 소유자는 `apps/vitalserver-recorder-recovery`이며, TestKit CLI는 제품 CLI를 호출하는
검증 wrapper입니다. TestKit은 recorder-recovery Python 내부 모듈을 import하지 않습니다.
단독 설치된 TestKit CLI에서 raw archive 명령을 사용하려면 `tirosh-vitalserver-recorder-recovery`가
별도로 설치되어 있어야 합니다. 그 외 TestKit 명령은 recorder-recovery 없이 동작해야 합니다.

```sh
uv run vitalserver-recorder-recovery export-raw-archive-vital \
  data/recorder-ingress-raw/send-data-raw.jsonl \
  --output-dir /private/tmp/recorder-ingress-vital-export
```

```sh
uv run vitalserver-testkit upload-vital path/to/vital-files \
  --vitalserver-url http://localhost \
  --endpoint /upload \
  --concurrency 4 \
  --repeat 10
```

운영 명령 하나로 export와 upload를 묶을 때는 `recover-raw-archive-vital`을 사용합니다. 이 명령은
raw archive를 읽어 output directory에 `.vital` 파일을 만든 뒤, 생성된 파일들을 VitalServer upload
endpoint로 전송합니다. VitalServer storage directory에 직접 복사하지 않습니다.

```sh
uv run vitalserver-recorder-recovery recover-raw-archive-vital \
  data/recorder-ingress-raw/send-data-raw.jsonl \
  --output-dir /private/tmp/recorder-ingress-vital-export \
  --vitalserver-url http://localhost \
  --endpoint /upload \
  --concurrency 4
```

제품 `recorder-recovery` server는 같은 기능을 HTTP API로도 제공합니다. Recorder ingress auto export worker는
기본적으로 이 endpoint를 호출합니다. TestKit server는 이 recovery endpoint를 제공하지 않습니다.
`rawArchivePath`와 `outputDir`은 recorder-ingress와 recorder-recovery container가 같은 mount path로
볼 수 있어야 합니다.

```sh
curl -X POST http://recorder-recovery:8080/raw-archive/recover-vital \
  -H 'content-type: application/json' \
  -d '{
    "rawArchivePath": "/var/lib/vitalserver-recorder-ingress/raw/send-data-raw.jsonl",
    "outputDir": "/var/lib/vitalserver-recorder-ingress/recovery/vital-export",
    "vitalserverUrl": "http://app:80",
    "endpoint": "/upload",
    "skipFilenameCheck": true
  }'
```

TestKit의 `.vital` upload 검증 경로는 Python 코드에서 직접 호출할 수도 있습니다.

```python
from tirosh_vitalserver.testkit import (
    VitalServerClient,
    assert_vital_filenames,
    iter_vital_files,
    upload_vital_files,
    wait_for_server,
)
from tirosh_vitalserver.testkit.application.metrics import (
    transfer_total_bytes_sent,
    transfer_total_requests,
)

client = VitalServerClient("http://localhost", timeout=60)
wait_for_server(client)

payloads = iter_vital_files("path/to/vital-files")
assert_vital_filenames(payloads)

summary = upload_vital_files(
    client,
    payloads,
    concurrency=4,
    repeat=10,
    endpoint="/upload",
)

print(f"requests={transfer_total_requests(summary)}")
print(f"bytes={transfer_total_bytes_sent(summary)}")
```

`.vital` 파일명은 아래 형식을 따르는 것이 좋습니다.

```text
bedname_yymmdd_hhmmss.vital
```

## 결과 해석

`send_realtime_payloads()`와 `upload_vital_files()`는 모두 `TransferSummary`를 반환합니다.

자주 보는 값은 `application.metrics` 함수로 계산합니다.

- `transfer_total_requests(summary)`: 전체 요청 수
- `transfer_successful_requests(summary)`: 성공 요청 수
- `transfer_failed_requests(summary)`: 실패 요청 수
- `transfer_total_bytes_sent(summary)`: 전송한 총 bytes
- `transfer_bytes_per_second(summary)`: 전체 실행 시간 기준 bytes/sec
- `summary.elapsed_seconds`: 전체 실행 시간

개별 요청 결과는 `summary.results`에서 볼 수 있습니다.

```python
for result in summary.results:
    print(result.bytes_sent, result.elapsed_seconds, result.error)
```

## 서버 상태 확인

검증 중에는 다른 터미널에서 container 상태와 log를 같이 봅니다.

```sh
make ps
make logs
```

검증이 끝난 뒤 중지합니다.

```sh
make down
```

testkit에서 health check만 확인할 수도 있습니다.

```sh
uv run vitalserver-testkit health --vitalserver-url http://localhost
```
