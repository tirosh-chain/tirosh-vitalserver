# 031 Recorder activity 그래프가 rolling window만 표시함

> ID: TS-031
> Category: Runtime Control PWA / Observability
> Owner: macOS runtime / Remote Console
> Status: resolved

## Symptoms

Remote Console의 Recorders > Activity에서 Period를 `Last 6 hours`로 선택해도 그래프가 최근 몇 분 구간에만 몰려 보입니다.

대표 증상:

- 오래 실행했는데 packet bar가 우측 끝 최근 구간에만 표시됩니다.
- `Total packets`가 장시간 누적값이 아니라 최근 observer rolling window 합계처럼 작게 표시됩니다.
- `Last sample`은 최신 시간으로 갱신되지만, 과거 bucket이 충분히 쌓이지 않습니다.

## Impact

Recorder activity가 실제 장시간 트래픽 추세를 보여주지 못합니다.

- 운영자는 장시간 패킷 유입이 없었던 것처럼 오해할 수 있습니다.
- `Total packets`가 선택한 period의 합계인지, latest rolling window의 합계인지 구분하기 어렵습니다.
- SQLite observation history가 비어 있거나 읽히지 않는 상황이 UI에서 명확히 드러나지 않습니다.

## Cause

현재 activity chart는 `/vitaldb/recorders`가 제공하는 `activityTimeline[].buckets`를 합쳐 표시합니다.

이 값은 두 계층의 조합입니다.

1. `vitaldb-observer`는 Redis audit list에서 최근 `recorderActivityWindowSeconds` 구간을 읽어 rolling activity bucket을 만듭니다.
2. macOS runtime은 여러 observer snapshot을 SQLite observation history에 저장하고, Remote Console은 이 history를 합쳐 장시간 chart를 구성합니다.

따라서 장시간 그래프가 나오려면 SQLite observation history가 지속적으로 쌓이고 조회되어야 합니다. SQLite history가 비어 있거나, read/decode 실패가 빈 목록으로 숨겨지거나, 최신 status observation만 fallback으로 붙으면 UI는 최신 rolling window만 보게 됩니다.

2026-05-30 코드 검토에서 확인한 구체 흐름:

1. `audit-proxy`가 recorder의 Socket.IO `send_data`를 감지해 Redis list `vitalserver:audit_events`에 audit event를 기록합니다.
2. `vitaldb-observer`는 Redis list의 최근 event를 읽고 `VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS` 기본값인 300초 rolling activity를 계산합니다.
3. Guest의 `tirosh-runtime-state` systemd service가 기본 5초마다 `vitaldb-observer`의 `/api/v1/observations`를 호출하고, 결과를 `runtime-state.json`의 `vitalDBObservation`에 포함합니다.
4. Host watchdog은 기본 60초마다 `runtime-state.json`을 읽어 `RuntimeHealthSnapshot`을 만들고, status/event 기록 시 `vitalDBObservation`을 함께 전달합니다.
5. `RuntimeObservationRecorder`가 event를 JSONL/SQLite event store에 기록한 뒤, event에 포함된 `vitalDBObservation`을 `SQLiteRuntimeObservabilityStore.append`로 `vitaldb_observation_snapshots`에 저장합니다.
6. Runtime Control API의 `/vitaldb/recorders`는 `vitaldb_observation_snapshots`를 읽어 `RuntimeVitalRecorderHistory`를 구성합니다.

현재 구조상 SQLite observation history는 독립적인 projection loop가 아니라 watchdog event recording의 부수효과입니다. 따라서 watchdog이 돌지 않거나, guest state가 stale 처리되거나, event recording은 성공했지만 observation append가 실패하면 장시간 history가 끊깁니다.

또한 두 failure가 명시적으로 드러나지 않습니다.

- `SQLiteRuntimeObservabilityStore.vitalDBObservations()`는 read/init/decode 실패를 `[]`로 숨깁니다.
- `RuntimeObservationRecorder.recordEvent()`는 `vitalDBObservationStore.append` 실패를 로그만 남기고 event 기록 성공으로 처리합니다.

이 때문에 SQLite가 비어 있는 상태와 SQLite를 읽지 못하는 상태, 그리고 최신 status observation만 있는 상태가 API/UI에서 구분되지 않습니다.

## Checks

Remote Console이 받은 recorder history의 시간 범위를 먼저 확인합니다.

```sh
curl -s http://<remote-console-host>:18321/vitaldb/recorders \
  | jq '.recorders[] | {vrcode, samples: (.activityTimeline // [] | length), first: (.activityTimeline // [] | first?.observedAt), last: (.activityTimeline // [] | last?.observedAt)}'
```

특정 recorder의 bucket 범위를 봅니다.

```sh
curl -s http://<remote-console-host>:18321/vitaldb/recorders \
  | jq '.recorders[] | select(.vrcode=="<VRCODE>") | [.activityTimeline[]?.buckets[]?.bucketStartedAt] | {count: length, first: min, last: max}'
```

Host에서 SQLite observation snapshot 수를 확인합니다.

```sh
sqlite3 "/Library/Application Support/TiroshVitalServer/vm/logs/runtime-observability.sqlite3" \
  'select count(*), min(observed_at), max(observed_at) from vitaldb_observation_snapshots;'
```

Runtime log에서 projection 실패를 확인합니다.

```sh
rg -n "vitaldb observation recording failed|runtime-observability|SQLite|observability" \
  "/Library/Application Support/TiroshVitalServer/vm/logs"
```

Observer rolling window 설정도 확인합니다.

```sh
docker exec vitalserver-vitaldb-observer env \
  | rg "VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS|VITALDB_OBSERVER_AUDIT_EVENT_LIMIT"
```

## Actions

수정 방향:

1. Recorder packet activity의 durable SoT는 SQLite의 1-minute bucket projection이어야 합니다.
2. Packet collection부터 SQLite insert까지의 흐름은 명시적인 pipeline이어야 합니다.
3. `/vitaldb/recorders`와 Remote Console은 rolling snapshot을 재해석하지 말고 SQLite bucket projection을 조회해야 합니다.
4. Runtime status/event recording은 activity history persistence의 부수효과가 되면 안 됩니다.
5. SQLite bucket projection append/read 실패는 best-effort 로그로만 끝내지 말고 runtime status/event/API에서 확인 가능한 projection failure로 남겨야 합니다.
6. `Total packets`는 선택한 visible buckets 합계로 계산하고, history coverage가 부족하면 장시간 합계처럼 표시하지 않아야 합니다.

목표 구조:

```text
Recorder send_data
  -> audit-proxy raw audit event
  -> vitaldb-observer 1-minute RecorderActivityBucket observation
  -> guest runtime-state transfer
  -> host observability projection
  -> SQLite vitaldb_recorder_activity_buckets
  -> Runtime Control API /vitaldb/recorders
  -> Remote Console chart
```

허용하지 않는 구조:

- latest rolling activity를 장시간 history처럼 재사용
- watchdog/status/event 기록의 부수효과로 activity history를 저장
- SQLite read/write 실패를 빈 배열, fallback observation, 최신 snapshot으로 숨김
- Host/UI가 activity history를 추정하거나 보정

## Implementation Notes

2026-05-30 구현:

- `vitaldb_recorder_activity_buckets` SQLite projection table을 추가했습니다.
- `VitalDBObservationDocument`에 포함된 recorder activity bucket을 projection 단계에서 `vrcode + bucketStartedAt + bucketSeconds` 기준으로 upsert합니다.
- 같은 1분 bucket이 여러 observer snapshot에 반복 포함되면 message/byte/room count는 가장 큰 aggregate를 유지하고, first/last observed time을 갱신합니다.
- `RuntimeVitalRecorderHistory`는 projection bucket이 제공되면 snapshot 안의 rolling activity를 사용하지 않고 SQLite projection bucket만 activity timeline으로 변환합니다.
- `RuntimeObservationRecorder`는 event 기록만 담당하도록 정리했습니다. VitalDB observation persistence는 status writer의 명시적 projection 경로로 이동했습니다.
- Remote Console의 `Packets` 지표는 chart y-axis 최대값이 아니라 최신 non-zero bucket 값을 보여주도록 수정했습니다.

- `/vitaldb/recorders` response에 `activityHistory` metadata를 추가해 SQLite projection source, bucket coverage, read error를 명시했습니다.
- Remote Console은 `activityHistory.readError`가 있으면 activity chart 영역에서 history가 불완전하다는 오류를 표시합니다.

## Prevention

Recorder activity는 세 값을 분리해서 다뤄야 합니다.

- latest activity: observer가 방금 본 rolling window
- activity history: runtime이 SQLite에 누적한 durable snapshots
- visible total: 사용자가 선택한 period 안에서 화면에 표시된 bucket 합계

latest rolling window를 장시간 history처럼 보이게 만들면 안 됩니다. History source를 읽지 못하면 빈 chart가 아니라 history read failure로 드러내야 합니다.

## Related Cases

- `TS-030`: Runtime 상태를 Host/UI가 추정하거나 암묵 보정함

## Follow-up

- 2026-05-30: iPhone Remote Console에서 `Last 6 hours` 선택 후에도 bar가 최근 구간에만 몰리고 `Total packets`가 rolling window 수준으로 표시되는 증상을 등록했습니다.
- 2026-05-30: 패킷 수집부터 SQLite 조회까지의 흐름을 확인했습니다. SQLite 삽입은 존재하지만 watchdog event recording에 종속되어 있고, append/read 실패가 명시 상태로 드러나지 않는 구조를 추가 원인으로 등록했습니다.
- 2026-05-30: recorder activity 1-minute bucket projection을 SQLite에 명시적으로 추가하고, `/vitaldb/recorders` read model이 projection bucket을 activity timeline으로 사용하도록 전환했습니다.
- 2026-05-30: SQLite activity projection read failure를 `/vitaldb/recorders.activityHistory.readError`로 노출하고, Remote Console에서 불완전한 activity history를 표시하도록 수정했습니다.
