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
POST /lab/sessions/{sessionId}/finish
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

## Vital File Replay Contracts

Replay probes the decompressed `VITA` header and declared header length before
opening track data. Versions 1, 2, and 3 are accepted as input; an unknown future
version fails with `unsupportedFormatVersion`. Packet data never starts at a
hard-coded offset.

Replay reads the explicit VitalDB track type before interpreting sample rate.
Waveform tracks (`type=1`) require a positive rate; numeric tracks (`type=2`)
accept the VitalDB-standard zero rate and are sampled on the Lab one-second
tick. A valid string track (`type=5`) follows the explicitly selected reject or
skip policy. Other types fail with `unsupportedTrackType`.

Missing or non-finite frame data is not filled from an older value. The runtime
composition explicitly selects `omitTrack`; tests can select `failFrame` when a
strict complete-frame contract is required.

The product replay composition scans gzip packets with reads bounded to 64 KiB
and writes waveform chunks and numeric records to an operation-owned SQLite
spool. It does not call `vitaldb.get_track_samples()` to allocate a dense array
for the full recording. Each one-second replay frame is read from the spool and
is limited to 100,000 waveform samples. Session pause, completion, replacement,
and startup failure explicitly close and remove the spool. Packet truncation,
spool read/write failure, and an oversized frame remain distinct failures.

File-open failures transition the session to `failed` and persist a structured
`failure` document containing `stage`, `code`, `message`, and `failedAt`.
Recorder delivery remains `notAttempted` when validation fails before the first
payload. Retrying a failed session clears the previous failure only after the
explicit `failed -> running` transition is accepted.

Replay also requires at least one non-string track whose `.vital` `montype` is
known by VitalServer. An all-unknown file fails before delivery with
`noVitalServerGraphTracks`; mixed files may retain custom tracks, but only known
monitor types are graph-compatible. Monitor type IDs and realtime names use the
single Core contract aligned with the vendored VitalServer `vitaldb.js` table.

See [TS-167](../../docs/troubleshooting/167_lab-vital-numeric-zero-srate-replay-failure.md)
and [TS-174](../../docs/troubleshooting/174_lab-vital-replay-no-graph-compatible-tracks.md)
for diagnosis and operational guidance.
