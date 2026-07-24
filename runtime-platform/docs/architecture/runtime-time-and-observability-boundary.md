# Runtime time and observability boundary

## Intent

Time quality and telemetry are diagnostic resources. They help an operator
understand a Recorder, Guest, or Host, but they never advance Recorder packet
delivery, Lab stop, Archive export, upstream lifecycle, or update state.

The resource owner stores a typed observation and a typed operation receipt.
The UI and CLI only read and display those documents. A missing provider, an
unavailable endpoint, malformed evidence, and an unknown delivery outcome are
not interchangeable.

## Guest clock quality

The Guest Runtime owns `TimeAuthority` and `ClockQuality` in Guest SQLite.
Its product adapter is `chrony-tracking`:

1. C37 declares the absolute `chronyExecutablePath` and timeout.
2. The adapter invokes that exact executable with `tracking -n`.
3. It parses leap state, stratum, offset, root dispersion, and reference UTC
   time as one evidence set.
4. Only a complete normal evidence set becomes `synchronized`.

No source is inferred from the wall clock, command logs, `PATH`, or a Host
read. Host time has a separate owner and uses the explicitly configured,
cross-platform `ntp-udp-quality-probe` adapter; it measures quality but does
not configure an operating-system time daemon.

## Guest OpenTelemetry export

C37 selects either the test-only outcome profile or the live `otlp-http`
adapter. The live form explicitly declares the Collector base endpoint and a
timeout. `TelemetryPipeline` still declares the Collector resource reference,
allowed attributes, length and cardinality limits, and the exact log/metric/
trace signal set.

```
Recorder/Lab/Guest event
  -> Guest TelemetryPipeline policy (allowlist, redaction, cardinality)
  -> OTLP/HTTP adapter
       -> /v1/logs
       -> /v1/metrics
       -> /v1/traces
  -> immutable TelemetryEmissionReceipt in Guest SQLite
```

An empty valid logs request is the Collector probe. It proves OTLP route
acceptance, not backend delivery. During a three-signal emission, failure of
the first route becomes `unavailable` or `failed`; failure after any accepted
route becomes `unknown`. This prevents a false complete-export claim.

Attribute values never enter the receipt database. The adapter receives only
the sanitized result, and the Collector profile removes known sensitive keys as
defence in depth.

## Recorder self-observability

Vital Recorder information enters through the Guest-owned immutable
`CatalogObservation` ingestion contract. A source envelope preserves recorder
ID, boot ID, sequence, recorder-local occurrence time, time-quality evidence,
and recorder runtime evidence. The Guest records its own receive time
separately. It does not treat a Gateway socket connection, Lab Runner process,
or a packet counter as a substituted Recorder observation.

The Lab virtual Recorder now uses the same C19 publisher contract as a real
Vital Recorder: after it establishes its explicit Gateway effect, the Runner
submits a Recorder-owned self-observation to its declared Guest catalog
endpoint. Its `time` is deliberately `not-reported` because the Runner does
not own an independent recorder NTP authority. A physical Vital Recorder must
use this same contract with its own boot ID, sequence, clock facts, and runtime
facts; neither Gateway, Host, nor UI may synthesize them.

The current Guest SQLite `CatalogObservation` repository is a foundation
implementation, not the target product persistence model. The next capability
replaces it with the Guest-owned PostgreSQL `recorder_catalog` schema. It keeps
immutable admission evidence, a current projection, explicit expectation
events, and bounded timeline/incident reads without dual-writing the SQLite
table. Support, expectation, report freshness, and owner read state remain
separate axes; absence of a report never proves that a Recorder is unsupported.

The detailed schema, routes, cutover rule, artifact lineage boundary, and
acceptance sequence are defined by the
[Helper 0.2 Capability Adoption Plan](helper-0.2-capability-adoption-plan.md).
