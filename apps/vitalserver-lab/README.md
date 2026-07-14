# VitalServer Lab

`vitalserver-lab` is the Runtime v2 product service for virtual recorder
scenarios, Lab sessions, Lab read models, and `.vital` replay requests.

The service runs inside the Guest container stack. Runtime Control API, PWA,
Swift Helper, and CLI consume Lab through Guest Control `/runtime/lab/*` or
Runtime Control `/runtime/lab/*`; they must not call a TestKit container or
`/dev/testkit` product route.

## Runtime Ownership

The Lab service owns:

- scenario catalog reads
- Lab session collection, creation, start, stop, and readback
- running-session recorder start and stop after explicit ownership validation
- Lab bed and recorder read models
- `.vital` replay request validation and session creation
- Postgres-backed session/read-model state

The Lab service does not own Host VM lifecycle, host nginx proxy state, install
or update orchestration, native shell actions, or debug-only TestKit APIs.

## API

The container exposes a small HTTP API:

```text
GET  /health
GET  /ready
GET  /lab/scenarios
GET  /lab/beds
GET  /lab/recorders
GET  /lab/sessions
POST /lab/sessions
GET  /lab/sessions/{sessionId}
POST /lab/sessions/{sessionId}/start
POST /lab/sessions/{sessionId}/stop
POST /lab/sessions/{sessionId}/recorders/{recorderId}/start
POST /lab/sessions/{sessionId}/recorders/{recorderId}/stop
POST /lab/vital-files/replay
```

Read failures remain explicit. Missing sessions, invalid request bodies,
unavailable Postgres state, and paths outside `VITALSERVER_LAB_VITAL_FILES_MOUNT`
are returned as errors rather than defaulting to empty success.

## State

Runtime v2 uses Postgres as the default Lab session store:

```text
VITALSERVER_LAB_SESSION_STORE=postgres
VITALSERVER_LAB_DATABASE_URL=postgresql://vitalserver@postgres:5432/vitalserver
```

The production repository uses SQLAlchemy ORM records and explicit domain
mappers. The same repository contract is exercised with a SQLite URL in tests;
switching dialects is a composition/configuration decision, not a domain or UI
branch.

The in-memory store is a local development override only and must be enabled
explicitly with `VITALSERVER_LAB_ALLOW_MEMORY_STORE`.
