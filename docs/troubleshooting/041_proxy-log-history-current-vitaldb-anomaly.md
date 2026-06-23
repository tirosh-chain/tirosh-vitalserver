# Proxy log history shown as current VitalDB anomaly

> ID: TS-041  
> Category: Runtime health  
> Owner: macOS runtime observability / VitalDB observer  
> Status: resolved

## Symptoms

- Helper app status or observability history shows failure reasons such as:
  - `VitalDB anomaly Backend Unavailable on _ready_`
  - `VitalDB anomaly Backend Unavailable on _redis-ui_`
  - `VitalDB anomaly Backend Unavailable on _swagger_`
- Current `runtime-status.json` may already be `healthy` with empty `failureReasons`.
- Runtime probes for `/ready`, `/redis-ui/`, and `/swagger/` may already return HTTP `200`.

## Impact

- The runtime can appear unhealthy after it has recovered.
- Watchdog/event history may contain a critical VitalDB anomaly even though the latest explicit runtime probes are healthy.
- This is a status boundary issue, not evidence of data loss.

## Cause

VitalDB observer parsed proxy/access JSONL logs and turned historical 502/504 rows into current `backend-unavailable` anomalies. During VM boot, update, or container restart windows, those rows can be valid historical evidence, but they do not own current backend availability state.

Current backend availability is owned by explicit runtime HTTP probes and guest runtime state. Proxy/access logs are diagnostic history.

## Checks

```sh
python3 -m json.tool \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"

sqlite3 -header -column \
  "/Library/Application Support/TiroshVitalServer/status/runtime-observability.sqlite" \
  "select observed_at, ready, recorder_count, anomaly_count from vitaldb_observation_snapshots order by observed_at desc limit 12;"

tail -n 50 \
  "/Library/Application Support/TiroshVitalServer/logs/runtime/proxy-nginx.error.log"

tail -n 50 \
  "/Library/Application Support/TiroshVitalServer/logs/runtime/watchdog.out.log"
```

## Actions

- If latest `runtime-status.json` is healthy and latest VitalDB observation has `anomalies: []`, treat older backend-unavailable rows as history.
- Use the observability history timestamp to separate previous failure evidence from current runtime state.
- Update to a build where VitalDB observer preserves proxy failures in `proxyConnections` but does not promote them to current anomalies.

## Prevention

- VitalDB observer keeps proxy/access log rows as diagnostic evidence only.
- Runtime failure reasons must come from explicit current-state contracts owned by watchdog/runtime and guest runtime state.
- Historical log rows must not create, infer, or hide current product state.

## Operational Notes

- A VM or container restart can legitimately produce a short proxy `connection refused` window.
- The important distinction is whether the latest explicit status still reports the failure.

## Related Cases

- TS-030
- TS-040

## Follow-up

- 2026-06-02: VitalDB observer stopped promoting proxy 502/504 history into current `backend-unavailable` anomalies. Proxy rows remain available in `proxyConnections`.
