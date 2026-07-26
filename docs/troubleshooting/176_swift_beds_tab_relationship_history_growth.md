# Swift Beds tab becomes slow after remaining open

> ID: TS-176
> Category: macOS Helper / VitalDB relationships / Performance
> Owner: Guest VitalDB relationship read model and Swift presentation
> Status: resolved

## Symptoms

After the macOS Helper remains on the Beds tab, selecting another tab can react slowly. The delay
increases with runtime uptime. Guest Control's `GET /runtime/vitaldb/relationships` response also
grows continuously even when the same bed/recorder anomaly has not changed.

## Cause

The Guest relationship projection emitted `duplicateAssignment`, `unlinkedBed`,
`unlinkedRecorder`, and `staleLink` events on every five-second observation. Since `observedAt` was
part of every event ID, merge-by-ID could not remove the repeats. One captured runtime had 3,360
events in a 1.66 MB response and added three more events in sixteen seconds without a relationship
transition.

Swift requested and decoded the complete document every five seconds. `RuntimeBedsPanel` and
`RuntimeRecordersPanel` then filtered the complete assignment/event arrays inside each SwiftUI body
evaluation even though each section displayed at most eight rows. The shared `ObservableObject`
also invalidated these panels for unrelated status publications. A selected-section task canceled
while a synchronous Guest read was running could still publish its completed result after the tab
changed.

## Fix

- Guest projection v2 owns current condition state as explicit `activeIssueIDs`.
- Condition events are appended only when an issue becomes active; resolving and later reappearing
  produces a new event.
- Legacy projection documents are explicitly migrated by compacting repeated condition events.
- Relationship reads return the newest explicit event page with `eventTotalCount` and `eventLimit`;
  the product default is 100 events.
- Swift uses a cancellation-aware asynchronous Guest relationship read for selected-section
  polling. Leaving Beds cancels the underlying URL session task and discards any canceled result.
- Swift builds a bounded bed/recorder presentation index once per relationship publication instead
  of filtering the full history during rendering.

## Checks

Repeatedly project the same observation and verify that the event count does not change. Project a
resolved observation and then the original issue again; the count must increase exactly once.

The Guest response must satisfy:

```text
events.count <= eventLimit
events.count <= eventTotalCount
```

On macOS, leave Beds selected through several refreshes and switch tabs while a refresh is active.
The selection must render immediately, and the canceled Beds refresh must not republish its result.

## Prevention

Persistent conditions and transition events are separate meanings. Polling may update explicit
current issue state, but it must not manufacture a new domain event from an unchanged condition.
UI row limits must be enforced before SwiftUI body evaluation, and response truncation must always
be reported with explicit page metadata.
