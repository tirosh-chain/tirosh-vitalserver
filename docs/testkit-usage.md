# Testkit 사용법

`tirosh-vitalserver-testkit`은 VitalServer에 데이터를 반복 전송하고 처리량과 실패율을
측정하기 위한 Python 패키지입니다. 저장소 전체의 목적은 테스트 자체가 아니라 upstream
VitalServer를 제품으로 사용할 수 있는 수준으로 끌어올리는 것이고, testkit은 그 과정에서
실시간 수집, 업로드, relay 경로를 검증하는 도구입니다.

현재 주요 역할은 simulated Vital Recorder data 또는 외부 payload를 Socket.IO `send_data`
event로 보내고, VitalServer와 Redis가 운영에 필요한 형태로 반응하는지 확인하는 것입니다.

upstream VitalServer `2.3.4` 코드 기준 API 목록은 [OpenAPI 문서](openapi.yaml)에
정리되어 있습니다. 실시간 monitor data는 HTTP `POST /api/send`가 아니라 Socket.IO
`send_data` event로 들어갑니다.

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

내부적으로는 `scripts/test_vitalserver.py`가 `config/testkit.toml`을 읽고 testkit CLI를
호출합니다. 기본값은 파일을 읽지 않고 simulated recorder data를 생성합니다. 기본 config는
recorder 5대와 총 500개 `send_data` event 기준의 load scenario를 바로 실행할 수 있게 잡아
둡니다. stream scenario는 Ctrl+C 전까지 계속 전송합니다. 더 강한 검증이 필요하면 config
파일을 복사해 조정합니다.

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

기본값은 내부 simulated recorder data를 만들어 Socket.IO `send_data` event로 반복 전송합니다.
testkit은 room map payload를 upstream VitalServer가 기대하는 `{vrcode, ver, rooms}` 형태로
감싼 뒤 zlib으로 압축해 보냅니다. 실제 장비에서 캡처한 payload를 재현해야 하면 command의
첫 positional argument나 `config/testkit.toml`의 `[recorder].payload`에 JSON 파일 경로를
지정합니다.

제품화 관점에서는 먼저 `verify-recorder`로 “전송된 payload가 VitalServer에서 보이는 상태”까지
확인합니다. 이 명령은 payload를 한 번 전송한 뒤, VitalServer의 UI용 endpoint인 `/vr_devs`에서
bed device metadata가 조회되는지 확인합니다.

```sh
uv run vitalserver-testkit verify-recorder \
  --vitalserver-url http://localhost
```

성공하면 아래처럼 room과 bed id가 출력됩니다.

```text
visible_rooms: 1
visible: room=mnw4anvs4 bed_id=de8d5733096db32506a924ac566c903c343e2338 bytes=...
```

여러 recorder machine이 동시에 붙는 상황은 `--recorders`로 재현합니다. testkit은 payload를
복제하되 recorder code와 room name을 `-001`, `-002`처럼 분리해서 VitalServer가
서로 다른 bed로 등록하게 만듭니다.

```sh
uv run vitalserver-testkit verify-recorder \
  --vitalserver-url http://localhost \
  --recorders 5
```

반복 전송량과 처리량을 보고 싶을 때는 `send-recorder`를 사용합니다.

```sh
uv run vitalserver-testkit send-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --concurrency 10 \
  --repeat 100
```

실제 recorder처럼 `join_vr`를 보내고 계속 흘려보내는 상황은 `stream-recorder`를 사용합니다.
기본값은 Ctrl+C로 중단할 때까지 streaming하며, 검증 자동화에서는 `--duration` 또는
`--max-messages`로 종료 조건을 둡니다. `send-recorder`와 `verify-recorder`는 one-shot
`send_data` 확인용이며 VRecorder lifecycle 검증에는 사용하지 않습니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --interval 1
```

10초 동안만 streaming하려면:

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
  --interval 1 \
  --duration 10
```

Python 코드에서 직접 호출할 수도 있습니다.

```python
from tirosh_vitalserver.testkit import (
    build_simulated_recorder_payload,
    send_realtime_payloads,
)
from tirosh_vitalserver.testkit.adapters.outbound.recorder import emit_send_data
from tirosh_vitalserver.testkit.application.metrics import (
    transfer_failed_requests,
    transfer_successful_requests,
    transfer_total_bytes_sent,
    transfer_total_requests,
)

payload = build_simulated_recorder_payload()
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
- `interval`: streaming mode에서 recorder별 전송 간격
- `duration`: streaming mode 실행 시간; `0`이면 Ctrl+C까지 계속 전송
- `max_messages`: streaming mode에서 recorder별 최대 전송 횟수
- `vrcode`: recorder code; 생략하면 payload의 단일 최상위 key를 사용
- `version`: `ver` field 값; 기본값은 `testkit`
- `shift_time`: 기본값은 `True`; `dt*` timestamp field를 현재 시간 근처로 shift
- `--http`: Socket.IO 대신 HTTP JSON endpoint를 probe할 때 사용

## TestKit API server

Runtime Helper의 Test 탭과 PWA가 TestKit을 제어할 수 있도록 TestKit은 FastAPI server를
제공한다. macOS runtime dev bundle에서는 TestKit을 guest Docker Compose의 `testkit`
container로 포함하고, Helper는 VM IP의 `http://<vm-ip>:18322` API를 호출한다. 이 server는
virtual VRecorder session의 시작/중지/상태 조회를 담당한다.

```sh
uv run vitalserver-testkit serve \
  --host 127.0.0.1 \
  --port 18322
```

위 명령은 local 개발용이다. 제품 runtime에서는 `vitalserver-testkit:0.1.1` container가
`0.0.0.0:18322`로 API를 열고, 생성된 virtual VRecorder는 guest compose network 안에서
`http://edge/`를 대상으로 접속한다.

초기 API는 session lifecycle에 집중한다.

```text
GET  /health
GET  /sessions
POST /sessions
GET  /sessions/{id}
POST /sessions/{id}/stop
```

Helper Test 탭의 기본 모델은 “virtual VRecorder 1대 = TestKit session 1개”이다. 여러 대를
동시에 실행할 때는 session을 여러 개 생성한다. Bulk 생성은 이후 API에서 여러 session을 한 번에
생성하는 얇은 편의 기능으로 추가한다.

예시 요청:

```json
{
  "targetUrl": "http://edge/",
  "recorders": 1,
  "vrcode": "TEST_VR",
  "intervalSeconds": 1,
  "durationSeconds": 0,
  "defaultScenario": "normal"
}
```

TestKit API의 SoT는 “시뮬레이터가 무엇을 실행 중인지”이다. VitalServer가 실제로 recorder를
인식했는지는 기존 `vitaldb-observer`와 Runtime Control API `/vitaldb/recorders` 결과를
기준으로 판단한다.

## `.vital` 파일 업로드 검증

파일 업로드 경로를 확인할 때 사용합니다. upstream 코드 기준 upload endpoint는
`/upload` 또는 `/upload_vital.php`입니다. testkit 기본값은 `/upload`입니다.

```sh
uv run vitalserver-testkit upload-vital path/to/vital-files \
  --vitalserver-url http://localhost \
  --endpoint /upload \
  --concurrency 4 \
  --repeat 10
```

Python 코드에서 직접 호출할 수도 있습니다.

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
