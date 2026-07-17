# Observability profile

The runtime platform uses the OpenTelemetry protocol and the open-source OpenTelemetry Collector. It does not require a commercial tracing, logging, or metrics license. An operator selects an OTLP-compatible backend by setting `VITALSERVER_OTLP_BACKEND_ENDPOINT`; the collector has no implicit endpoint or local-success fallback.

`otel-collector.yaml` accepts OTLP/gRPC and OTLP/HTTP and forwards logs, metrics, and traces through one explicit diagnostic pipeline. The application-side C20 `TelemetryPipeline` remains the authority for allowlists, value length, and cardinality. Collector-side removal is a second boundary only; it cannot make an unsafe application signal safe after the fact.

The executable acceptance topology uses named deterministic provider profiles to prove contract state. Those profiles are not a physical collector probe and are intentionally unsupported by default in the product executable. A deployment that enables live diagnostic export must install a concrete `TelemetryExporter` adapter and declare its collector resource/reference; absent or unreadable adapter configuration is reported as `unsupported`/`unavailable`, never as `ready`.

Collector health, sampling, or backend delivery is diagnostic evidence only. It must not change a Vital Recorder delivery receipt, RuntimeTopology, Lab/Archive operation, or ClockQuality.
