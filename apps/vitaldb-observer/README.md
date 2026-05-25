# vitaldb-observer

`vitaldb-observer` is a local collector container for VitalServer operational state.
It does not modify upstream VitalServer code and does not own the final observation
database.

## Responsibility

- Read VitalServer Redis keys in read-only mode.
- Parse optional proxy/access JSONL logs.
- Build recorder, bed, device, filter, proxy, and anomaly snapshots.
- Serve stateless JSON APIs for the guest runtime-state collector.
- Write structured diagnostic JSONL events to container stdout.

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
| `VITALDB_OBSERVER_ACCESS_LOG_PATH` | empty |
| `VITALDB_OBSERVER_ACCESS_LOG_LIMIT` | `200` |

## Local checks

```sh
.venv/bin/python -m pytest apps/vitaldb-observer/tests
.venv/bin/ruff check apps/vitaldb-observer
.venv/bin/python -m mypy apps/vitaldb-observer
```

The container is included in the default service stack and in VM packaging via
`apps/vitalserver-macos-runtime/Support/Build/vm-build.toml`.
