# Lab replay rejects valid VitalDB numeric tracks with zero sample rate

> ID: TS-167
> Category: Product Lab / Guest containers / Runtime Control PWA
> Owner: Product Lab
> Status: active

## Symptoms

A `.vital` file appears in the Runtime Control Replay catalog, but starting replay stops the
new session immediately. The session recorder reports no attempted delivery:

```text
session.state=stopped
recorder.lastSendState=notAttempted
recorder.messagesSent=0
```

The start response can contain the following error, but older Lab versions do not retain it in
later session reads:

```text
Vital File track has an invalid sample rate: Solar8000/PLETH_HR
```

Gzip integrity and `vitaldb.VitalFile` decoding can both succeed. This symptom does not prove that
the generated file is damaged.

## Impact

Valid VitalDB files containing numeric tracks cannot be replayed by affected Lab versions. The
uploaded file and existing runtime data do not need to be deleted. Reinstalling the same affected
Lab image does not resolve the failure.

## Cause

VitalDB uses the track `type` as the signal-kind contract:

- `type=1` is waveform and requires a positive `srate`.
- `type=2` is numeric and normally uses `srate=0` with timestamped scalar records.
- `type=5` is string data.

The affected Lab replay adapter classified tracks from `srate` and rejected every track whose
sample rate was not positive. It therefore rejected a valid numeric track before the first
recorder payload was built. Setting numeric `srate=1` in the generator is not a valid workaround;
the VitalDB writer classifies every positive-rate track as waveform and expects array records.

The start workflow first persisted `running`, then converted the file-open failure to `stopped`.
Only the command response retained the error, so later GET/list responses lost the failure stage
and reason.

## Checks

Inspect the file with VitalDB and compare `type`, `srate`, and record count. Numeric `srate=0` is
valid and must not be normalized to a positive value:

```python
from vitaldb import VitalFile

source = VitalFile("case.vital")
for track in source.trks.values():
    print(track.dtname, track.type, track.srate, len(track.recs))
```

Read numeric samples with an explicit one-second interval:

```python
samples = source.get_track_samples("Solar8000/PLETH_HR", 1.0)
print(len(samples))
```

In the Runtime Control API, compare session state with recorder delivery state. A file-validation
failure occurs before sending and should preserve `lastSendState=notAttempted` rather than inventing
a recorder send failure.

## Actions

Update to a Runtime bundle containing the corrected Product Lab image. The replay adapter now
branches on the explicit VitalDB track type, accepts zero-rate numeric tracks, and rejects
unsupported types with a typed error. It accepts declared Vital File versions 1, 2, and 3,
derives the packet offset from `headerLength`, and rejects unknown future versions before track
decoding. Retry the failed session after the updated Guest stack is active; a successful retry
clears the previous session failure.

For affected older versions, keep the original file unchanged. Do not set numeric track rates to
`1`, rewrite scalar records as waveform arrays, or delete runtime data as a repair attempt.

## Prevention

The Lab test suite includes a zero-rate numeric fixture, invalid waveform-rate coverage, explicit
unsupported-type coverage, v1/v2/v3 header coverage, explicit string/gap policies, and a full
start-failure persistence/retry test. Numeric gaps are not filled from stale values. Session
failures are owned by the session aggregate and retain stage, code, message, and timestamp across
GET/list reads. Recorder delivery remains `notAttempted` when validation fails before transport.

## Operational Notes

The source file is not modified during replay or retry. Deployment of the code fix still requires
a new Guest image/update bundle; a source checkout change alone does not alter an installed VM.

## Related Cases

- `TS-144`: uploaded Vital file is absent from the Replay catalog.

## Follow-up

- 2026-07-21: reproduced with `Solar8000/PLETH_HR type=2 srate=0`; both 600-second source files
  generated every replay frame successfully after type-based parsing.
