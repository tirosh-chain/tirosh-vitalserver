# tirosh-vitalserver-testkit

VitalServer 제품화 과정에서 실시간 수집, `.vital` 업로드, UI-visible 상태를 검증하기 위한
Python 패키지입니다. upstream VitalServer를 직접 수정하지 않고, simulated recorder data나
외부 payload를 흘려보내고 처리량과 실패율을 확인하는 데 집중합니다.

## 빠른 실행

```sh
# 저장소 root에서 VitalServer를 먼저 실행
make up
```

```sh
# CLI는 workspace 환경에서 실행
uv run vitalserver-testkit --help

# 서버 준비가 끝났는지 먼저 확인
uv run vitalserver-testkit health \
  --vitalserver-url http://localhost
```

VRecorder처럼 Socket.IO에 접속해 `join_vr`를 보내고, simulated recorder data를 계속 흘립니다.
VRecorder 접속 lifecycle, `dt` 수신, 관리 이벤트 수신은 `stream-recorder` 기준으로 검증합니다.
`send-recorder`와 `verify-recorder`는 one-shot `send_data` 확인용이며 `join_vr`를 보내지 않습니다.

```sh
uv run vitalserver-testkit create-beds \
  --room-name OR-A \
  --room-name OR-B
```

생성된 room name을 recorder 명령에 명시해서 연결합니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --recorders 2 \
  --bed-room-name OR-A \
  --bed-room-name OR-B \
  --interval 1
```

`stream-recorder`는 VitalServer가 보내는 `dt`와 관리 이벤트를 수신합니다. Network Settings
대상 확인용 상태 페이지가 필요하면 `--status-page`를 켭니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://<vitalserver-host> \
  --vrcode VR_TEST \
  --status-page \
  --status-port 80
```

VitalServer Web Monitoring의 Network Settings는 `http://<vr-ip>`처럼 port 없이 열기 때문에
end-to-end 검증에는 port `80`이 필요합니다. 일반 사용자 권한으로 실행해야 하는 환경에서는
아래처럼 대체 port를 사용할 수 있지만, 이 경우 Network Settings 버튼이 자동으로 여는 URL과는
다르므로 브라우저에서 `http://<vr-ip>:8080`을 직접 확인해야 합니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://<vitalserver-host> \
  --vrcode VR_TEST \
  --status-page \
  --status-port 8080
```

상태 페이지는 `join_vr` 전송 여부, 서버 `dt`, local IP, 마지막 `send_data` 시각, 전송 횟수,
관리 이벤트 수신 이력을 보여줍니다. JSON으로는 `/status.json`을 조회합니다.

Runtime Helper의 Test 탭 또는 PWA에서 TestKit을 제어할 때는 macOS runtime guest compose
안의 `testkit` container가 제공하는 FastAPI server를 사용합니다. Helper는 VM IP를 기준으로
`http://<vm-ip>:18322`에 붙고, container 안의 virtual VRecorder는 compose 내부 edge proxy인
`http://edge/`로 접속합니다.

```sh
vitalserver-testkit serve --host 0.0.0.0 --port 18322
```

local 개발 중에 TestKit API만 단독 확인할 때는 같은 command를 host loopback으로 실행할 수
있지만, 제품 runtime에서는 container가 SoT입니다. 초기 API는 virtual VRecorder session의
시작/중지/상태 조회를 제공합니다.

```text
GET  /health
POST /beds
GET  /sessions
GET  /scenarios
POST /sessions
GET  /sessions/{id}
POST /sessions/{id}/stop
POST /sessions/{id}/upload-vital
DELETE /sessions/{id}
DELETE /sessions
```

`POST /beds`는 `{"roomNames":["OR-A"]}`처럼 명시적인 room name을 받거나,
`{"count":2,"prefix":"OR"}`로 fresh bed identity를 만든다. `GET /scenarios`는
Test 탭에서 선택할 목적 중심 scenario catalog를 제공한다. scenario document는
`scenario`, `title`, `situation`, `purpose`, `defaultBedroomName`, `defaultWindow`,
`tracks`를 포함하며, source file path나 generator 종류는 API 표면에 노출하지 않는다.

`POST /sessions`는 legacy `bedRoomNames`, `defaultScenario`, `hctPercent`를 받지 않는다.
하나의 `bedroomName`과 하나의 목적 중심 `scenario`를 명시하고, `.vital` artifact 생성/업로드는
`output` 객체로 요청한다.

```json
{
  "targetUrl": "http://recorder-ingress:8080",
  "recorderCount": 20,
  "bedroomName": "TestBedroom",
  "scenario": "bloodbag_transfusion",
  "window": {
    "durationSeconds": 20
  },
  "output": {
    "exportVital": true,
    "uploadVital": true,
    "vitalUploadEndpoint": "/upload"
  }
}
```

session 종료 시 명시적인 playback window(start/end, pause/resume events, interval, sent
message count, recorder payload, scenario)를 기준으로 `.vital` artifact를 생성한다. streaming
frame 전체를 memory에 누적하지 않으며, `output.uploadVital`은 `output.exportVital` 없이는
유효하지 않다.

Generated bed는 같은 prefix를 반복해도 구분되도록 짧은 random suffix를 붙인다. 기본 prefix
`testbed`와 suffix `5f83`은 `testbed5f83`으로 생성되며, 이 이름이 TestKit status,
recorder payload `roomname`, Web Monitoring title, `.vital` filename prefix에 동일하게 사용된다.

`.vital` export/upload session은 아래 상태를 API 계약으로 제공한다.

```text
running
stopping
finalizing-vital
vital-ready
uploading
uploaded
upload-failed
```

`vital` 문서는 `exportStatus`, `uploadStatus`, `artifact`, `uploadResult`,
`exportError`, `uploadError`를 분리해서 제공한다. upload 실패 시 artifact path는 보존되고
`POST /sessions/{id}/upload-vital`로 수동 retry할 수 있다. Session delete는 generated
`.vital` artifact를 삭제하지 않으며, API artifact 문서의 `retentionPolicy`는
`preserve-on-delete`로 표시된다.

TestKit API는 시뮬레이터 실행 상태의 SoT이고, VitalServer가 실제로 인식한 recorder 상태의
SoT는 `vitaldb-observer`와 Runtime Control API의 recorder 관측 결과입니다.
생성했던 bed registry는 `[bed_registry].state_path`에, virtual VRecorder 목록은
`[sessions].state_path`에, generated `.vital` artifacts는 `[sessions].artifact_dir`에
저장합니다. 따라서 TestKit API process가 재시작되어도 이전 bed
room name을 다시 선택하거나 session의 target URL과 vrcode를 기준으로 삭제/reset을 다시
요청할 수 있습니다. 실행 중이던 streaming thread 자체는 복구하지 않고, 재시작 이후에는
남은 VitalServer recorder 등록을 정리하는 registry로 사용합니다.

Persisted state files are versioned contracts. `sessions.json` writes
`schema_version: 2`; `bed-registry.json` writes `schema_version: 1`. Missing
`schema_version` is treated as a legacy v1 document only at the store boundary.
After a legacy session is loaded and saved again, the store writes the current
schema and materializes `.vital` state explicitly. Newer schema versions,
invalid schema values, corrupt JSON, and missing fields in the current schema
must fail visibly rather than becoming an empty registry or default success.

Troubleshooting: update 직후 `testkit` container가 반복 재시작하고 로그에
`session_store.load_record.failed`와 `KeyError: 'vital_state'`가 보이면, 이전 버전의
`sessions.json`이 `.vital` export 상태 필드가 추가되기 전 schema로 남아 있는 것입니다.
수정 방향은 저장소 로더에서 `vital_state`가 없는 legacy session document만 명시적으로 migrate해
`not-requested` 상태를 채우는 것입니다. `vital_state: null`이나 다른 필수 session/recorder 필드
누락은 invalid contract로 실패해야 합니다. 예방 원칙은 optional migration을 필드 단위로 한정하고,
missing, invalid, failed state를 같은 empty/default success로 합치지 않는 것입니다.

Troubleshooting: 여러 virtual VRecorder session을 오래 실행할 때 TestKit API의 session은
`running`이지만 `vitaldb-observer`가 일부 recorder를 `stale-recorder`로 보고하면, 먼저
각 session의 recorder `connected`, `lastSendDataAt`, `messagesSent`와 VitalServer의
`utime_<vrcode>` 갱신을 함께 비교합니다. 이 증상은 Socket.IO 관리 연결이 끊긴 뒤
TestKit이 reconnect/`join_vr` 재등록을 하지 않거나, 끊긴 상태의 `send_data` emit 시도를
성공처럼 세면 발생합니다. 수정 방향은 장기 streaming client에서 reconnect를 활성화하고
reconnect 후 `join_vr`를 다시 보내며, disconnected 상태의 emit은 전송 성공으로 기록하지
않는 것입니다. 예방 원칙은 TestKit 실행 상태와 VitalServer 관측 상태를 별도 SoT로 두고,
연결 끊김을 messagesSent 증가나 empty error로 숨기지 않는 것입니다.

## Simulated Signal Scenario

testkit은 simulated recorder data를 만들 때 시나리오 이름을 `RecorderSignalScenario`로
관리합니다. 각 시나리오는 `SignalProfile` preset으로 변환되고, streaming 중 numeric value와
waveform 생성에 반영됩니다.

| Scenario | 의미 | 주로 확인할 것 |
| --- | --- | --- |
| `normal` | 일반적인 adult baseline vital sign | 기본 처리량, Web Monitoring 표시, Redis 저장 |
| `tachycardia` | 빠른 심박 | ECG/PLETH/ART waveform 밀도, HR numeric 표시 |
| `bradycardia` | 느린 심박 | sparse beat rendering, 낮은 HR 표시 |
| `hypotension` | 낮은 arterial pressure | BP numeric, ART waveform scale |
| `hypertension` | 높은 arterial pressure | BP numeric, ART waveform scale, UI 표시 범위 |
| `desaturation` | 낮은 SpO2 | SpO2 numeric과 trend 표시 |
| `apnea` | 호흡 정지 또는 심한 저호흡 | CO2 waveform, RR numeric, stale-like 상태 |
| `arrhythmia` | 불규칙한 beat timing | waveform continuity, renderer 안정성 |
| `artifact` | noise나 왜곡이 섞인 신호 | renderer/transport resilience |
| `device_disconnect` | 장비 연결 해제 또는 신호 없음 | stale data, disconnect 상태, Redis key 갱신 |
| `hct_decreasing` | HCT가 점진적으로 감소하는 lab numeric | PLETH + HCT 기반 bloodbag inference context |

기본은 `normal`로 두고, 특정 bed만 override할 수 있습니다. `index`는 생성된 bed 목록의
1-based 번호입니다. HCT는 `Lab/HCT` numeric track으로 생성되며, Test 탭/API에서는
`hct_decreasing` 또는 `bloodbag_transfusion` 같은 목적 중심 scenario로 노출됩니다.

```toml
[bed_registry]
state_path = "/var/lib/vitalserver-testkit/bed-registry.json"

[sessions]
state_path = "/var/lib/vitalserver-testkit/sessions.json"
artifact_dir = "/var/lib/vitalserver-testkit/artifacts"

[beds]
count = 5

[recorder]
recorders = 5
default_scenario = "normal"

[[recorder.bed_scenarios]]
index = 2
scenario = "tachycardia"

[[recorder.bed_scenarios]]
index = 4
scenario = "desaturation"
```

## Real Vital Recorder Samples

실제 `.vital` 파일에서 recorder payload JSON을 생성할 수 있습니다. 이 경로는 source
track header와 sample 값을 읽어 payload를 만들며, 값이 없는 source track은 payload event에
명시하고 제외합니다.

```bash
uv run vitalserver-testkit export-real-vital-recorder \
  data/MORC03_230102/MORC03_230102_133133.vital \
  --scenario bloodbag \
  --start-offset 70 \
  --duration 20 \
  --room-name MORC03_SPHB_SAMPLE \
  --output .tmp/real-vital-recorder-samples/morc03_bloodbag.json
```

생성된 JSON은 `send-recorder` 또는 `stream-recorder --replay-sample` 입력으로 사용할 수
있습니다.

```bash
uv run vitalserver-testkit send-recorder \
  .tmp/real-vital-recorder-samples/morc03_bloodbag.json
```

지원하는 real sample scenario는 다음과 같습니다.

| Scenario | Track selection |
| --- | --- |
| `basic_monitor` | Bx50/Primus 주요 ECG, PLETH, ART, CO2, HR, SpO2, BP, BT, CVP, PPV |
| `periop_full` | Source file의 `Bx50/*`, `Primus/*` track |
| `bloodbag` | `Root/PLETH`, `Root/SPHB`, Root pulse oximetry context, Primus CO2 context, derived `LabDerived/HCT` |
| `root_sedation` | Source file의 `Root/*` track |
| `full_real` | Source file의 모든 track 중 선택 window에 finite sample이 있는 track |

`bloodbag` scenario의 HCT는 source file의 직접 HCT track이 아니라 `Root/SPHB`에서
`HCT percent = SPHB g/dL * 3.0` 공식으로 파생합니다. 이 사실은 payload event와 metadata
sidecar에 기록됩니다.

## Python API

Python에서 VRecorder 접속 lifecycle까지 검증하려면 `stream_vrecorder_session`을 사용합니다.

```python
from tirosh_vitalserver.testkit import (
    build_simulated_recorder_payload,
    build_virtual_recorder_payloads,
    connect_socketio,
    create_beds,
    stream_total_bytes_sent,
    stream_total_messages_sent,
    stream_vrecorder_session,
)

beds = create_beds(count=5)
payload = build_simulated_recorder_payload(
    room_names=tuple(bed.room_name for bed in beds),
)
virtual_payloads = build_virtual_recorder_payloads(payload, count=5)

summary = stream_vrecorder_session(
    "http://localhost",
    virtual_payloads,
    interval_seconds=1,
    max_messages=10,
    connector=connect_socketio,
)

print(stream_total_messages_sent(summary))
print(stream_total_bytes_sent(summary))
```

## Layer 구조

```text
src/tirosh_vitalserver/testkit/
  cli.py            # CLI composition root

  domain/
    recorder/       # Recorder value object, montype, payload 변환
      payloads/     # wire type, encoding, time, virtual, realtime helpers
      simulator/    # simulator frame/template 조립
    signal/         # SignalProfile, scenario preset, waveform/variation
    vital_file/     # .vital 파일 value object, 탐색, 파일명 policy

  application/
    ports.py        # usecase가 요구하는 외부 시스템 계약
    recorder_lifecycle.py  # VRecorder Socket.IO lifecycle wiring
    recorder_runtime.py    # stream 상태와 status page snapshot
    recorder_session/      # virtual VRecorder API session 상태/manager/document
    results.py      # usecase 실행 결과 value object
    metrics.py      # result/summary 계산 함수
    assertions.py   # 실패율 검증
    usecases/
      recorder/     # Socket.IO realtime collection workflow
      server/       # VitalServer 상태 확인 workflow
      vital_file/   # .vital 업로드 workflow

  adapters/
    inbound/cli/    # argparse CLI
      recorder.py   # recorder command/parser adapter
      server.py     # health, TestKit API server command
    inbound/api/    # FastAPI app factory와 route wiring
      app.py
    inbound/http/   # local HTTP endpoints exposed by the testkit
      recorder_status.py
    outbound/       # VitalServer HTTP, Socket.IO 구현체

  schemas/          # 외부 입력 Pydantic schema와 document loader
  types/            # JsonValue 같은 낮은 수준의 type alias
```

의존 방향은 아래처럼 유지합니다.

```text
adapters -> application -> domain
schemas  -> types
domain   -> types
```

`domain`은 `application`이나 `adapters`를 import하지 않습니다. Socket.IO, HTTP 같은 외부 구현체는
`adapters/outbound`에 두고, `application/usecases`는 `ports.py`의 Protocol에만 의존합니다.
FastAPI는 `adapters/inbound/api`에서 얇게 wiring하고, long-lived virtual VRecorder session
상태는 `application/recorder_session`이 소유합니다.

## 테스트

테스트는 패키지 내부에 둡니다.

```text
tests/
  unit/
    application/
    domain/
    schemas/
  integration/
    adapters/
    cli/
```

실행:

```sh
uv run pytest packages/vitalserver-testkit/tests
uv run ruff check packages/vitalserver-testkit/src packages/vitalserver-testkit/tests
uv run mypy
```

현재 integration test는 실제 VitalServer container를 띄우지 않고, 로컬 HTTP server와 CLI entrypoint로
adapter 경계를 검증합니다. 실제 VitalServer와 Redis까지 붙는 end-to-end 검증은 별도 시나리오로
추가할 예정입니다.

## 검증 시나리오

저장소 root의 `scripts/test_vitalserver.py`는 `config/testkit.toml`을 읽어서 scenario와
각 관심사별 설정을 조합한 뒤 testkit CLI를 호출합니다. 반복 검증에는 Makefile target을
사용합니다.

```sh
make testkit-smoke
make testkit-load
make testkit-stream
```

`make testkit-stream`은 Web Monitoring 확인용으로 Ctrl+C 전까지 계속 데이터를 보냅니다.

다른 설정 파일을 쓰려면 `TESTKIT_CONFIG`를 지정합니다.

```sh
TESTKIT_CONFIG=config/load-test.toml make testkit-load
```

`scripts/test_vitalserver.py`는 설치된 `vitalserver-testkit` command를 우선 사용하고, 없으면
현재 Python interpreter의 module 실행으로 fallback합니다. 필요하면 `TESTKIT_CLI`로 명시적인 command
prefix를 지정할 수 있습니다.

```sh
TESTKIT_CLI="uv run vitalserver-testkit" make testkit-smoke
```

dev profile macOS Helper의 Test 탭은 Runtime Control browser console과 Testkit API 상태를 확인하는
용도입니다. Testkit 컨테이너/API가 package에 포함될지는 release manifest의 optional container service
정책으로 결정하고, Test 탭의 route와 API contract는 Test 탭/API 구현이 소유합니다.

## 관련 문서

- [문서 지도](../../docs/index.md): 문서 지도와 작성 기준
- [Testkit 사용법](../../docs/testkit/usage.md): CLI 사용법과 결과 해석
- [VitalServer 제품화 전략](../../docs/product/productization.md): 제품화 맥락
- [VitalServer recorder Redis key model](../../docs/recorder/redis-key-model.md): Redis key 구조와 relay 설계 메모
- [Runtime observability model](../../docs/runtime/macos/observability.md): 관측 SoT와 Runtime Control API 노출 기준
