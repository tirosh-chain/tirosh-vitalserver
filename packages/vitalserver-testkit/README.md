# tirosh-vitalserver-testkit

VitalServer 제품화 과정에서 실시간 수집, `.vital` 업로드, UI-visible 상태를 검증하기 위한
Python 패키지입니다. upstream VitalServer를 직접 수정하지 않고, simulated recorder data나
외부 payload를 흘려보내고 처리량과 실패율을 확인하는 데 집중합니다.

## 빠른 실행

저장소 root에서 VitalServer를 먼저 실행합니다.

```sh
make up
```

CLI는 workspace 환경에서 실행합니다.

```sh
uv run vitalserver-testkit --help
```

파일 없이 simulated recorder data를 VitalServer Socket.IO `send_data` event로 보내고
UI-visible 상태까지 확인합니다.

```sh
uv run vitalserver-testkit verify-recorder \
  --base-url http://localhost:8080
```

여러 recorder machine을 동시에 흉내내려면 `--recorders`를 사용합니다.

```sh
uv run vitalserver-testkit stream-recorder \
  --base-url http://localhost:8080 \
  --recorders 5 \
  --interval 1
```

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

```python
from tirosh_vitalserver.testkit import (
    build_simulated_recorder_payload,
    build_virtual_recorder_payloads,
    stream_virtual_recorder_payloads,
)
from tirosh_vitalserver.testkit.adapters.outbound.recorder import connect_socketio
from tirosh_vitalserver.testkit.application.metrics import (
    stream_total_bytes_sent,
    stream_total_messages_sent,
)

payload = build_simulated_recorder_payload()
virtual_payloads = build_virtual_recorder_payloads(payload, count=5)

summary = stream_virtual_recorder_payloads(
    "http://localhost:8080",
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
  domain/
    recorder/       # Recorder value object, montype, payload 변환
      payloads/     # wire type, encoding, time, virtual, realtime helpers
      simulator/    # simulator frame/template 조립
    signal/         # SignalProfile, scenario preset, waveform/variation
    vital_file/     # .vital 파일 value object, 탐색, 파일명 policy

  application/
    ports.py        # usecase가 요구하는 외부 시스템 계약
    results.py      # usecase 실행 결과 value object
    metrics.py      # result/summary 계산 함수
    assertions.py   # 실패율 검증
    usecases/
      recorder/     # Socket.IO realtime collection workflow
      server/       # VitalServer 상태 확인 workflow
      vital_file/   # .vital 업로드 workflow

  adapters/
    inbound/cli/    # argparse CLI
      recorder/     # recorder command/parser/scenario adapter
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

## 관련 문서

- [문서 지도](../../docs/index.md): 문서 지도와 작성 기준
- [Testkit 사용법](../../docs/testkit-usage.md): CLI 사용법과 결과 해석
- [VitalServer 제품화 전략](../../docs/vitalserver-productization.md): 제품화 맥락
- [Redis 데이터 구조](../../docs/redis-data-model.md): Redis key 구조와 relay 설계 메모
