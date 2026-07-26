# Observability deployment

VitalServer uses OpenTelemetry for logs, metrics, and traces. The product
uses an Apache-2.0-only custom OpenTelemetry Collector distribution; it does
not require a commercial telemetry license or silently select a SaaS backend.

## Guest-local diagnostic pipeline

The Guest product declares a concrete Collector process in C37 and installs
its binary, configuration, and separate state directory through C39:

- `guest-telemetry-collector-builder.yaml` is the selected distribution build
  recipe. It includes only the OTLP receiver, memory limiter, batch and
  attributes processors, and file exporter.
- `guest-telemetry-collector.yaml` is the Guest runtime configuration. It
  accepts OTLP/HTTP at `127.0.0.1:4318` only and stores bounded, rotated
  diagnostic evidence under `/var/lib/vitalserver/telemetry/otlp.jsonl`.
- `make guest-telemetry-collector-artifact-build
  GUEST_TELEMETRY_COLLECTOR_OUTPUT_ARTIFACT=/absolute/new/path
  GUEST_TELEMETRY_COLLECTOR_GO=/absolute/go
  GUEST_TELEMETRY_COLLECTOR_GUEST_ARCHITECTURE=arm64|amd64` builds the selected
  Linux Guest executable, proves its matching ELF architecture, and validates
  the actual runtime configuration with a temporary Host-built verifier before
  publishing the output.

C35 must identify both Collector artifacts by size and SHA-256. C39 must
install both artifacts and its `0700` state directory, and C40 must carry the
same bytes and installation plan in its final Guest-visible NoCloud volume.
Those bindings prevent a configuration-only declaration from looking like an
operational telemetry pipeline.

The local file store is diagnostic evidence, not a Vital Recorder archive or
a delivery receipt. It cannot advance Lab, Archive, RuntimeTopology, clock,
or packet-delivery state.

Application-side C20 policy remains the authority for allowlists, value
length, and cardinality. Collector-side removal of patient identifiers,
packet/waveform bytes, and credential-like attributes is defense in depth;
it cannot repair an unsafe application signal after it was emitted.

## External telemetry backend

`otel-collector.yaml` is a separately deployed external-backend profile. Its
operator must set `VITALSERVER_OTLP_BACKEND_ENDPOINT`; an absent variable or
unavailable endpoint remains a visible deployment failure. It is not included
in the Guest product and is not a fallback for the local diagnostic pipeline.

The Host and Guest `otlp-http` adapters require an exact collector endpoint
and request timeout. They probe and emit logs, metrics, and traces through
typed outcomes. A profile-backed `unsupported` or an unaccepted request stays
`unsupported`, `unavailable`, or `failed`; it is never formatted as a
successful local export. A future remote export from the Guest must add its
endpoint, credentials, retention policy, and delivery semantics as an
explicit deployment contract.
