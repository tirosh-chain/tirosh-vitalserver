# vitaldb-observer

`vitaldb-observer` is a local collector container for VitalServer operational state.
It does not modify upstream VitalServer code and does not own the final observation
database.

## Responsibility

- Read VitalServer Redis keys in read-only mode.
- Export allowlisted Redis key snapshots for off-host relay consumers without
  publishing raw Redis.
- Parse optional proxy/access JSONL logs as diagnostic evidence.
- Build recorder, bed, device, filter, proxy, and anomaly snapshots.
- Serve stateless JSON APIs for the guest runtime-state collector.
- Write structured diagnostic JSONL events to container stdout.

Proxy/access log entries are not the owner of current backend availability state.
They remain in `proxyConnections` for inspection, but the observer must not turn
historical 502/504 log rows into current `backend-unavailable` anomalies. Current
service availability is provided by explicit runtime HTTP probes and runtime
status contracts.

`readIssues` in the observation document records source-level read or parse
problems, such as malformed audit events, invalid access log encoding, missing
configured access logs, or malformed bed JSON. Empty `recorders`, `beds`,
`proxyConnections`, or activity summaries mean observed empty data only when no
related `readIssues` are present.

The final read model SoT is the macOS runtime observability SQLite file. The guest
`tirosh-runtime-state` service writes `runtime-state.json` through
`tirosh-write-runtime-state`, and watchdog stores the embedded observation in
`runtime-observability.sqlite`.

Observer stdout logs are raw diagnostics, not the product observation history SoT.
The guest container log collector can capture them in `container-logs.log`, while
watchdog/runtime stores the canonical observation history in
`runtime-observability.sqlite`.

Diagnostic events:

| Event | Meaning |
|---|---|
| `server_started` | HTTP server started |
| `readiness_failed` | Redis readiness check failed with an exception |
| `observation_collected` | `/api/v1/observations` returned a snapshot |
| `observation_failed` | `/api/v1/observations` returned an unhealthy snapshot |

## API

| Method | Path | Meaning |
|---|---|---|
| `GET` | `/health` | process liveness |
| `GET` | `/ready` | Redis readiness |
| `GET` | `/api/v1/observations` | latest computed VitalDB observation snapshot |
| `GET` | `/api/v1/redis/snapshots` | bearer-token protected, allowlisted Redis snapshot page for external relay |

`/api/v1/redis/snapshots` is disabled by default. It is intended for deployments
where external consumers run on another host or Kubernetes cluster and cannot
join the VitalServer Docker network. The endpoint does not expose arbitrary Redis
commands. It scans source Redis and returns only allowlisted numeric/trend and
waveform keys with `TYPE`, `PTTL`, and Redis `DUMP` payload encoded as base64.

Example:

```sh
curl \
  -H "Authorization: Bearer ${VITALDB_OBSERVER_REDIS_SNAPSHOT_EXPORT_TOKEN}" \
  "http://127.0.0.1:18083/api/v1/redis/snapshots?cursor=0&count=1000&limit=250"
```

The response includes `nextCursor`; clients continue requesting pages until
`complete` is `true`. Downstream relays must restore `dumpBase64` into their
target Redis namespace and must not write to VitalServer source Redis.

The public runtime-facing API is not this container API. Runtime clients should
use Runtime Control API:

| Method | Path | Meaning |
|---|---|---|
| `GET` | `/vitaldb/observations/latest` | latest observation stored by watchdog/runtime |
| `GET` | `/vitaldb/observations/stream` | long-lived SSE stream of the runtime read model |

OpenAPI for this container is maintained at
`docs/openapi/vitaldb-observer.openapi.yaml`. Runtime Control API OpenAPI is
maintained separately at `docs/macos-runtime/runtime-control.openapi.json`.

## Configuration

| Environment | Default |
|---|---|
| `VITALDB_OBSERVER_HOST` | `127.0.0.1` |
| `VITALDB_OBSERVER_PORT` | `8080` |
| `VITALDB_OBSERVER_REDIS_HOST` | `redis` |
| `VITALDB_OBSERVER_REDIS_PORT` | `6379` |
| `VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS` | `2.0` |
| `VITALDB_OBSERVER_RECORDER_ONLINE_THRESHOLD_SECONDS` | `120` |
| `VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS` | `300` |
| `VITALDB_OBSERVER_AUDIT_REDIS_LIST` | `vitalserver:audit_events` |
| `VITALDB_OBSERVER_AUDIT_EVENT_LIMIT` | `1000` |
| `VITALDB_OBSERVER_ACCESS_LOG_PATH` | empty |
| `VITALDB_OBSERVER_ACCESS_LOG_LIMIT` | `200` |
| `VITALDB_OBSERVER_REDIS_SNAPSHOT_EXPORT_ENABLED` | `false` |
| `VITALDB_OBSERVER_REDIS_SNAPSHOT_EXPORT_TOKEN` | empty |

## Local checks

```sh
.venv/bin/python -m pytest apps/vitaldb-observer/tests
.venv/bin/ruff check apps/vitaldb-observer
.venv/bin/python -m mypy apps/vitaldb-observer
```

The container is included in the default service stack and in VM packaging via
`config/vm-build.toml`.
