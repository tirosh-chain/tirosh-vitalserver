# Product Lab send succeeds but VitalDB tracks are empty

## Symptom

Product Lab shows Lab recorders with `sent 1`, but the VitalServer Helper
Recorders tab still shows no Vital Recorder data or no recorder activity detail.
VitalServer Web Monitoring may show the Lab bed row as `N/A`, with no visible
vital-sign tracks.

## Cause

Product Lab recorder send state is Lab-owned execution state. It only means the
Lab service emitted a Socket.IO `send_data` payload to the configured target.
It does not prove that upstream VitalServer accepted the payload as a VitalDB
recorder observation.

A Product Lab session must also be a running data producer. If `Start` emits
only one frame and then disconnects, the Lab read model may show a send attempt
while VitalServer never observes a durable bed/recorder stream through
recorder-ingress replay.

VitalServer's upstream `monitor.send_data` expects recorder tracks to carry
Vital Recorder-compatible `montype` values and meaningful record timestamps.
Payloads that only contain display names such as `HR`, `SPO2`, or `ECG_II`
without `montype` can be emitted successfully but remain unusable for
VitalServer monitoring detail, trend, and observer read-model projection.

## Fix Direction

Generate Product Lab payloads with the same explicit track contract used by
the recorder testkit:

- numeric tracks include VitalServer-compatible `name`, `montype`, `unit`, and
  current `recs[].dt`;
- waveform tracks include `name`, `montype`, `srate`, display bounds, and
  current `recs[].dt`;
- Lab session start keeps sending frames until the session is explicitly
  stopped;
- Lab start/replay refreshes the VitalDB recorder read model after refreshing
  the Product Lab read model.

## Prevention

Do not treat an outbound Socket.IO emit as product observation success. Keep
Lab execution state and VitalDB observation state separate in UI and tests.
When adding synthetic Product Lab signals, verify both the Lab recorder send
result and the downstream VitalDB recorder/bed observation. Session lifecycle
tests must assert that `Start` creates a continuing stream and `Stop` ends it.
