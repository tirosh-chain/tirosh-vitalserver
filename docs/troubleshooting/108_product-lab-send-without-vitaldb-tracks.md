# Product Lab send succeeds but VitalDB tracks are empty

## Symptom

Product Lab shows Lab recorders with `sent 1`, but the VitalServer Helper
Recorders tab still shows no Vital Recorder data or no recorder activity detail.
VitalServer Web Monitoring may show the Lab bed row as `N/A`, with no visible
vital-sign tracks.

Another form of the same failure shows the Web Monitoring connection age
repeatedly returning to `0s` or `1s`. ECG appears as one narrow spike per second,
PLETH as isolated dots, and CO2 as a repeated short sawtooth. Product Lab can
report a growing `sent` count while packet history is still absent from the
VitalDB recorder observation.

The native Helper can also show
`Could not connect to the server url=http://127.0.0.1:18330/runtime/vitaldb/recorders`.
This is a provider connection failure, not a successfully loaded empty packet
history.

In Product Lab, a selected session can appear as `accepted` while its recorder
rows already report `running`. The per-recorder Start and Stop buttons are then
both disabled because recorder control requires an explicitly running session.

## Cause

Product Lab recorder send state is Lab-owned execution state. It only means the
Lab service emitted a Socket.IO `send_data` payload to the configured target.
It does not prove that upstream VitalServer accepted the payload as a VitalDB
recorder observation.

A Product Lab session must also be a running data producer. If `Start` emits
only one frame and then disconnects, the Lab read model may show a send attempt
while VitalServer never observes a durable bed/recorder stream through
recorder-ingress replay.

The Lab sender previously opened a new Socket.IO client for every one-second
frame, emitted `join_vr` and one `send_data`, then disconnected. This made the
Lab `running` state disagree with the actual connection lifetime. It also added
connection and settle latency to every frame, so `messagesSent` advanced more
slowly than the configured frame interval.

The generated waveform tracks also declared sample rates of 125 Hz, 62.5 Hz,
and 25 Hz while providing only 5, 5, and 7 values in each one-second record.
PLETH declared display bounds of 0 to 1 but sent values as large as 78. Those
payloads cannot render as continuous one-second physiological waveforms.

The native VitalDB read providers previously used the fixed loopback endpoint
`127.0.0.1:18330`. Guest Control API is owned by the VM and listens at the
explicit Guest address on port `18330`; no Host loopback forward owns that
port. The fixed address therefore made recorder history and activity reads
unavailable even while Lab commands correctly used the current Guest address.

The Product Lab selected-session presentation also read state only from the
session list. A newer explicit selected-session detail response could report
`running` while the list still contained an older `accepted` record, leaving
both recorder actions disabled by the UI guard.

The macOS Guest Control gateway also decoded `/runtime/vitaldb/recorders` and
`/runtime/vitaldb/beds` as an obsolete latest-observation collection. Those
endpoints are owned by the Guest Postgres read model and return
`RuntimeVitalRecorderHistory` and `RuntimeVitalBedHistory`, including summaries,
activity history, and ingress status. Requiring the old `observedAt`, `ready`,
and `recorderOnlineThresholdSeconds` fields caused a decode failure reported as
`The data couldn’t be read because it is missing`, even though the Guest history
document was loaded.

The persisted `accepted` session with `running` children had a separate cause.
`SQLAlchemyLabSessionStore.start()` loaded the transaction state and called the
in-memory domain transition. That transition called the overridable
`list_beds()` method, which reloaded committed database state before the outer
transaction persisted. The nested read restored the old `accepted` session
while the same operation changed its beds and recorders to `running`.

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
- each Lab recorder owns one Socket.IO connection for its running lifetime,
  reuses it for every frame, and closes it only on recorder/session stop;
- generated waveform records contain one second of samples matching the
  declared sample rate and display bounds;
- Lab start/replay refreshes the VitalDB recorder read model after refreshing
  the Product Lab read model.

`messagesSent` remains Lab-owned execution state. Packet history remains owned
by the VitalDB observation/activity projection. The Recorder Details UI may
display both only when a provider-owned VitalDB recorder with the same explicit
`vrcode` is available; it reports observation read failure and not-yet-observed
state separately.

All native VitalDB product readers resolve Guest Control API from the explicit
Guest address owner on every read and use `http://<vm-ip>:18330`. The selected
Product Lab session uses its matching detail response when available, so the
session state that guards recorder commands is the state returned by the
selected-session contract rather than an older list item.

The native gateway consumes the Guest-owned recorder and bed history documents
directly. It does not reconstruct them from an obsolete observation DTO or
merge Lab state into VitalDB state. SQL-backed Lab mutations use the already
loaded domain collections throughout one transition and never call a
persistence-wrapped read method from inside that transition.

Recorder Start and Stop have different explicit guards. Start requires a
running session and a non-running recorder. Stop requires an explicitly running
recorder owned by the selected session and remains available when the persisted
session state is inconsistent, so an active stream can be shut down safely.

## Prevention

Do not treat an outbound Socket.IO emit as product observation success. Keep
Lab execution state and VitalDB observation state separate in UI and tests.
When adding synthetic Product Lab signals, verify both the Lab recorder send
result and the downstream VitalDB recorder/bed observation. Session lifecycle
tests must assert that multiple sends reuse one connection, `Start` creates a
continuing stream, and `Stop` ends and disconnects it. Waveform tests must assert
that each one-second record's sample count matches its declared sample rate and
that values remain inside declared display bounds.

Do not hardcode a Host loopback address for a Guest-owned API unless an explicit
Host port-forward contract exists. Read the Guest address owner and preserve
missing, invalid, stale, and failed address states as read failures. When a UI
loads both a collection and selected-item detail, define which explicit
provider result owns the selected state and test list/detail skew.

Repository adapters must not dispatch back through persistence-wrapped public
read methods while applying an uncommitted domain transition. Regression tests
must reopen the SQL store and assert that session, bed, and recorder states were
committed together. Gateway decode tests must use the exact Guest history
contract, including required nullable fields, summary, activity history, and
ingress status.
