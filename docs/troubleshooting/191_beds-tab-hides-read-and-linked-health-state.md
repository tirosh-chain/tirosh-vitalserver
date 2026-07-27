# Beds tab hides Bed read and linked Recorder health state

> ID: TS-191
> Category: macOS Helper / VitalDB Beds / Recorder observability
> Owner: Bed read model and macOS presentation
> Status: implemented; package verification pending

## Symptoms

The macOS Helper Beds tab can show `0` metrics or "no Bed data" when the Bed
read failed. A selected Bed shows linked Recorder identity and network fields,
but not the Recorder health state available in the Recorders tab. Visibility
actions also remain embedded in every table row instead of following the
current detail workflow.

## Cause

The Beds presentation predates the explicit Bed history and Recorder
observability contracts. It recomputes Bed summary values from local arrays,
does not render `RuntimeVitalBedHistory.state` or `readError`, and has no shared
Recorder health component. Guest emits `linkedRecorderVersion`, but the common
OpenAPI and PWA Bed contracts did not document that field.

## Fix direction

- Render the provider-owned Bed history state, summary, and read issue.
- Keep an empty loaded Bed collection distinct from partial and failed reads.
- Extract the Recorder health detail and incident presentation for reuse.
- Request Recorder health only from the non-blank `vrcode` explicitly reported
  by the selected Bed.
- Keep Recorder health failures inside the linked Recorder health section.
- Move Bed hide, unhide, and confirmed delete actions to the selected detail
  workflow.
- Align Bed search, sort, visibility, refresh, status-first rows, row sizing,
  selection, and detail-card structure with the Recorder presentation.
- Keep History Recorder-only until the Bed owner provides an explicit current
  observation field equivalent to `presentInLatestObservation`.
- Document `linkedRecorderVersion` as a legacy-optional wire field while
  requiring current providers to emit it explicitly.

## Prevention

Bed and Recorder reads are separate owner contracts. Presentation may compose
explicit Bed identity with a separate Recorder health read, but it must not
derive Bed state from Recorder history, infer a Recorder from an absent link,
or convert dependency failure into an empty list. Shared presentation for a
shared contract should have one implementation so Recorder and Bed surfaces do
not drift again.

## Related cases

- [TS-176: Swift Beds tab becomes slow after remaining open](176_swift_beds_tab_relationship_history_growth.md)
- [TS-190: Recorder without observer reports a detail decode failure](190_recorder-without-observer-detail-decode-failure.md)
