# Lab replay succeeds but VitalServer graph stays empty

> ID: TS-174
> Category: Product Lab / Runtime Control PWA / macOS Helper / Upstream integration
> Owner: Product Lab
> Status: active

## Symptoms

A Vital File replay session reports that recorder messages are being sent, and VitalServer shows
the replay bed as online, but no waveform or numeric graph appears. The source file can still be a
structurally valid `.vital` file.

Inspection shows that every replayable track has an unknown monitor type:

```text
SNUADC/PLETH type=1 srate=500 montype=0
Solar8000/PLETH_HR type=2 srate=0 montype=0
Solar8000/PLETH_SPO2 type=2 srate=0 montype=0
```

An affected macOS Helper version can instead show `Sessions 0` and the generic error below after
the upload succeeds:

```text
guest control API response decode failed: The data couldn't be read because it isn't in the
correct format.
```

## Impact

VitalServer accepts the recorder connection but cannot place any track into a Web Monitoring graph
group. Older Lab replay adapters continued sending these tracks and reported the session as
successful, so transport success hid the file-to-VitalServer compatibility failure.

The first Helper implementation modeled Lab failure codes as a closed Swift enum even though the
Runtime Control OpenAPI contract defines a provider-owned, non-empty string. When Lab introduced
`noVitalServerGraphTracks`, one failed session made the complete session-list decode fail. The
Helper then replaced the explicit failed session with an unavailable read and displayed zero
sessions.

## Cause

Vital File `montype` is the VitalServer realtime track classification contract. The Web Monitoring
path indexes known monitor types such as `PLETH_WAV`, `PLETH_HR`, and `PLETH_SPO2`. Numeric
`srate=0` is valid and unrelated to this failure; changing it to `1` can incorrectly turn a numeric
track into waveform data.

The replay adapter previously converted an unknown `montype` to the string `"0"` and allowed the
session to advance. VitalServer could therefore observe the bed without having any graph-compatible
track. The Python monitor-type table was also duplicated and had drifted from the vendored
VitalServer contract.

The authoritative repository snapshot is now
`packages/vitalserver-core/.../vital_file/monitor_type.py`, aligned with
`vendor/vitalserver/vitalserver-old/service/include/vitaldb.js` `montypes`. Lab and TestKit consume
that single Core contract.

## Checks

Inspect `type`, `srate`, and `montype` independently. A file is graph-compatible only when at least
one non-string replay track has a monitor type known by VitalServer:

```python
from vitaldb import VitalFile

source = VitalFile("case.vital")
for track in source.trks.values():
    print(track.dtname, track.type, track.srate, track.montype)
```

In Runtime Control, inspect the selected Lab session. Validation now persists and exposes:

```text
state=failed
failure.stage=fileValidation
failure.code=noVitalServerGraphTracks
recorder.lastSendState=notAttempted
recorder.messagesSent=0
```

The failure message lists the rejected track names and their monitor type IDs.

## Actions

Regenerate the source with correct VitalServer `montype` IDs for the intended signals, then retry
the failed session. Do not rewrite numeric sample rates. A mixed file remains replayable when at
least one track has a known monitor type; custom `montype=0` tracks remain non-renderable and are
not treated as graph evidence.

Update the Guest stack and Runtime Control PWA together. Product Lab returns a structured failed
session for `noVitalServerGraphTracks`; Guest Control preserves that provider-owned failure from
the Lab `422` response, and the PWA displays its stage, code, message, and timestamp.

Update the macOS Helper contract with the Guest stack as well. The Helper preserves every
non-empty provider failure code as its original string, while known values remain available as
typed constants. Empty failure codes remain invalid. Decode failures now include the exact coding
path, such as `sessions[0].failure.code`, rather than only Foundation's generic format message.

## Prevention

Replay validates graph compatibility before the first recorder payload and before a streaming
spool is committed. Both streaming and non-streaming paths test the all-unknown-monitor-type case.
The monitor type ID/name mapping has one Core owner and regression assertions cover IDs that had
drifted from the vendored upstream table.

The Helper gateway tests cover `noVitalServerGraphTracks`, a future provider-defined code, and an
invalid empty code. Adding a new provider failure must not make unrelated sessions disappear from
the session list.

## Operational Notes

This validation deliberately does not require every track to be recognized. Files may contain
custom or metadata tracks, but at least one replayable track must be renderable by VitalServer.
Validation failure does not modify or delete the source file.

## Related Cases

- `TS-167`: valid numeric `srate=0` is rejected during Lab replay.
- `TS-144`: an uploaded Vital file is absent from the Replay catalog.

## Follow-up

- 2026-07-22: reproduced with an online replay bed whose waveform and numeric tracks all had
  `montype=0`; VitalServer showed no graph despite successful recorder delivery.
- 2026-07-22: reproduced the follow-on Helper failure with a persisted
  `noVitalServerGraphTracks` session. Upload succeeded, but the closed Swift failure-code enum
  rejected the list response and the UI displayed zero sessions. Replaced it with an extensible
  non-empty string value and added coding-path diagnostics.
