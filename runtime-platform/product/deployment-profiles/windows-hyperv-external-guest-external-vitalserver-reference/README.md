# Windows Hyper-V external Guest / external VitalServer reference

This profile names a Windows Host that observes and controls an
**externally provisioned** Hyper-V Guest. It does not give the Runtime
Platform authority to create, replace, or delete that Guest. The Guest's
Runtime Control and Recorder Gateway endpoints are explicit placeholders
(`192.0.2.10`) and must be replaced by the deployment administrator before
operation.

The time and telemetry configuration deliberately report `outcome-unknown`.
A clinical deployment must select its own reachable NTP authority and OTLP
collector (or an explicit unavailable policy) in C33; this reference never
pretends that a public default is an enterprise time or observability
dependency.

This is desired deployment input, not evidence that Hyper-V, SCM, the Guest,
VitalServer, NTP, or telemetry are available. C24 release proof remains the
owner of that observation.
