# Beds tab hides Bed read state and clips bed-focused columns

> ID: TS-191
> Category: macOS Helper / VitalDB Beds / Presentation
> Owner: Bed read model and macOS presentation
> Status: implemented; package verification pending

## Symptoms

The macOS Helper Beds tab can show `0` metrics or "no Bed data" when the Bed
read failed. The list can clip its header and trailing columns because a wide
set of flexible technical columns is laid out in a horizontal scroll view. A
selected Bed can also expose Recorder health, version, IP, and relationship
details even though the primary user needs Bed and patient-presence context.

## Cause

The original Beds presentation predates the explicit Bed history contract. It
recomputes summary values and does not render `RuntimeVitalBedHistory.state` or
`readError`. A later layout copied too much of the Recorder surface: eight
flexible minimum-width columns, Recorder observability detail, and technical
relationship content. `LazyVStack` combined with fixed-size layout made the
wide header susceptible to vertical and trailing-edge clipping.

## Fix direction

- Render the provider-owned Bed history state, summary, and read issue.
- Keep an empty loaded Bed collection distinct from partial and failed reads.
- Keep the list focused on Bed status, Bed identity, patient presence, last
  observation, and Bed data issues.
- Use bounded fixed-width columns and a regular vertical stack inside
  horizontal scrolling.
- Do not request or render Recorder observability, incidents, version, IP, boot,
  resource, or relationship detail from the Bed surface.
- Move Bed hide, unhide, and confirmed delete actions to the selected detail
  workflow.
- Keep technical Bed ID and visibility as secondary detail or management
  information.
- Keep History Recorder-only until the Bed owner provides an explicit current
  observation field equivalent to `presentInLatestObservation`.
- Document `linkedRecorderVersion` as a legacy-optional wire field while
  requiring current providers to emit it explicitly.

## Prevention

Bed and Recorder reads are separate owner contracts and serve different user
questions. The Bed surface must not derive clinical availability from Recorder
health or expose infrastructure detail as Bed state. Patient identity,
encounter, clinical signal availability, and data-gap coverage require explicit
provider contracts; absence of those fields must not become inferred clinical
state.

## Related cases

- [TS-176: Swift Beds tab becomes slow after remaining open](176_swift_beds_tab_relationship_history_growth.md)
- [TS-190: Recorder without observer reports a detail decode failure](190_recorder-without-observer-detail-decode-failure.md)
