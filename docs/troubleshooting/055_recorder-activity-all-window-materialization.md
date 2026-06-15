# TS-055: Recorder Activity All Window Materializes Full History

> ID: TS-055  
> Category: macOS Helper / Observability  
> Owner: macOS runtime Helper UI  
> Status: resolved

## Symptoms

In the macOS Helper app, opening a VRecorder activity graph and selecting `All` can make the Swift app stop responding or exit.

The shorter windows such as `Last hour` can still render normally. The failure appears when the selected recorder has activity buckets spanning a long calendar range.

## Impact

The runtime and recorder data path are not changed by this failure. The impact is limited to the macOS Helper UI process while rendering activity history.

Users cannot inspect long recorder activity histories from the Helper app until the UI is restarted or updated.

## Cause

The `All` activity window filled every missing 1-minute or 5-minute bucket between the first observed activity bucket and the latest observed bucket before selecting the displayed page.

Sparse history over many days can therefore allocate and render a large intermediate bucket array even though the UI only shows a 12-hour page.

## Fix Direction

Compute the total page count from the explicit first/latest bucket timestamps, then fill only the selected 12-hour page.

Do not infer activity for missing history outside the selected page. Missing buckets inside the selected page remain zero-count display buckets only.

The macOS Helper should load recorder lists without embedded activity timelines, then read chart data through the explicit activity window contract:

```text
GET /vitaldb/recorders/{vrcode}/activity?bucketSeconds=60&period=all&pageIndex=<page>
```

The PWA should migrate to the same endpoint instead of deriving `All` pages from `/vitaldb/recorders[].activityTimeline`.

## Prevention

Display pagination must bound materialized presentation data before filling gaps. UI code may add display buckets for the current chart window, but must not convert an entire long history gap into in-memory state.

Recorder activity chart state belongs to the Runtime Control activity window response. SwiftUI and PWA presentation code should use `state`, `page`, and `buckets` from that response instead of reconstructing durable history state from absence or old embedded timeline data.

## Related Cases

- TS-031
- TS-052
