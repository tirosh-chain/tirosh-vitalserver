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
uv run vitalserver-testkit stream-recorder \
  --vitalserver-url http://localhost \
  --recorders 5 \
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
GET  /sessions
POST /sessions
GET  /sessions/{id}
POST /sessions/{id}/stop
DELETE /sessions/{id}
DELETE /sessions
```

TestKit API는 시뮬레이터 실행 상태의 SoT이고, VitalServer가 실제로 인식한 recorder 상태의
SoT는 `vitaldb-observer`와 Runtime Control API의 recorder 관측 결과입니다.
생성했던 virtual VRecorder 목록은 `[sessions].state_path`에 저장합니다. 따라서 TestKit API
process가 재시작되어도 이전 session의 target URL과 vrcode를 기준으로 삭제/reset을 다시
요청할 수 있습니다. 실행 중이던 streaming thread 자체는 복구하지 않고, 재시작 이후에는
남은 VitalServer recorder 등록을 정리하는 registry로 사용합니다.

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

기본은 `normal`로 두고, 특정 bed만 override할 수 있습니다. `index`는 `--recorders`로 만들어지는
1-based virtual recorder 번호입니다.

```toml
[recorder]
recorders = 5
default_scenario = "normal"

[[recorder.beds]]
index = 2
scenario = "tachycardia"

[[recorder.beds]]
index = 4
scenario = "desaturation"
```

## Python API

Python에서 VRecorder 접속 lifecycle까지 검증하려면 `stream_vrecorder_session`을 사용합니다.

```python
from tirosh_vitalserver.testkit import (
    build_simulated_recorder_payload,
    build_virtual_recorder_payloads,
    connect_socketio,
    stream_total_bytes_sent,
    stream_total_messages_sent,
    stream_vrecorder_session,
)

payload = build_simulated_recorder_payload()
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
- [Testkit 사용법](../../docs/testkit-usage.md): CLI 사용법과 결과 해석
- [VitalServer 제품화 전략](../../docs/vitalserver-productization.md): 제품화 맥락
- [Redis 데이터 구조](../../docs/redis-data-model.md): Redis key 구조와 relay 설계 메모
- [Runtime observability model](../../docs/macos-runtime/observability.md): 관측 SoT와 Runtime Control API 노출 기준
