# Recorder without observer reports a detail decode failure

> ID: TS-190
> Category: Recorder observability / Runtime Control
> Owner: Guest Control recorder observability contract
> Status: implemented; package verification pending

## Symptoms

A Recorder can be `Online` and `Present` while Recorder Details shows:

```text
Health detail read failed: guestControl=guest control API response decode failed:
boot.orderingState: missing required key
```

This commonly affects Recorders that do not have the observer package installed and therefore
have not submitted a Recorder observability profile, boot event, health observation, or incident
assessment.

After the detail contract is corrected, the same Recorder can show:

```text
Incident history is unavailable: Recorder ingress Recorder observability incidents
for VR_CODE request failed: status=503
```

## Impact

Recorder connectivity and patient presence remain available, but the complete health detail read
is rejected. The UI cannot distinguish the valid `notReported` state from a Guest dependency or
decode failure.

No Recorder data is lost. This is a cross-boundary response contract failure.

## Cause

Recorder presence and Recorder observability have different owners. An online Recorder without an
observer can legitimately have no observability row. Recorder ingress reports that absence as
`404 not_found`, and Guest Control converts it to a successful `notReported` detail.

The Guest Control `notReported` constructor omitted three required explicit fields:

- `boot.orderingState`
- `evidenceHealth`
- `incidentState`

The dependency-failure `unavailable` constructor had the same omission. The Swift Host contract
correctly rejected the incomplete document instead of inferring state. Runtime Control OpenAPI
also declared the `orderingState` property without including it in the Boot schema's `required`
list, so generated-contract verification did not expose the drift.

The incident-history 503 had a separate recorder-ingress SQL cause. PostgreSQL parsed
`'kernel-' || document->>'incidentType'` using the overloaded JSON concatenation operator before
JSON text extraction. It therefore tried to decode `kernel-` as JSON and failed with:

```text
invalid input syntax for type json
DETAIL: Token "kernel" is invalid.
```

The query now makes the JSON-to-text boundary explicit as
`'kernel-' || (document->>'incidentType')`.

Recorder ingress already preserves boot-version meaning:

- observer boot event v2: `orderingState=ordered`
- v1 boot event: `orderingState=unknown`
- no observer report: `state=notReported`, `orderingState=unknown`
- explicitly non-orderable evidence: `state=nonOrderable`, `orderingState=nonOrderable`

The hotfix does not reinterpret v1 or missing observer data as v2.

## Checks

Read the recorder-ingress result and the Guest Control result separately:

```sh
curl -i \
  http://127.0.0.1/runtime/vitaldb/recorders/VR_CODE/observability

curl -sS \
  http://GUEST_IP:18330/runtime/vitaldb/recorders/VR_CODE/observability
```

For a Recorder without observer data, recorder ingress may return `404 not_found`. Guest Control
must return a complete `notReported` document whose Boot section contains
`orderingState=unknown`, with explicit `notReported` evidence and incident states.

A Guest Control dependency failure must instead return `state=unavailable` with a non-empty
`readError`; it must not be converted to `notReported`.

For an incident query, inspect the recorder-ingress response and PostgreSQL log. A Recorder without
observer data must return a loaded incident page with an empty `incidents` array. A 503 containing
`invalid input syntax for type json` is the SQL operator-precedence failure, not evidence that an
incident exists or that the observer is required.

## Actions

Install a package or update bundle containing the hotfix, then restart the updated Guest Control
service through the normal update workflow. Installing the observer package is not required to
make Recorder Details readable.

After update, select an online Recorder without observer data and confirm that Recorder Details
shows the explicit missing/not-reported states without a health-detail decode error.

## Prevention

Guest Control now emits complete explicit Boot, evidence-health, and incident-state contracts for
both `notReported` and `unavailable` results. Its outbound recorder-ingress validator requires the
same fields and accepts the explicit `nonOrderable` state.

Regression coverage includes:

- recorder-ingress 404 converted to a complete `notReported` document;
- missing `boot.orderingState` rejected at the Guest boundary;
- dependency unavailability kept distinct from observer absence;
- v1 boot ordering remaining `unknown` and v2 boot ordering reported as `ordered`;
- Swift decoding of a Recorder-without-observer response;
- OpenAPI-generated PWA contract requiring `orderingState`;
- PostgreSQL execution of the incident query with a kernel incident;
- an incident query for a Recorder without observer rows returning an empty result.

## Operational Notes

Do not fix this symptom by making Host fields optional or by deriving boot order from timestamps,
file names, or report absence. The Guest owner must provide `unknown`, `notReported`, or
`unavailable` explicitly.

## Related Cases

- `TS-030`: Runtime state inference and fallback boundaries.
- `TS-128`: Recorder presence and activity read-model gaps.

## Follow-up

- 2026-07-27: reproduced against a live online Recorder with no observability row. Recorder
  ingress returned `404 not_found`; Guest Control returned an incomplete `notReported` document,
  and Swift failed first at `boot.orderingState`.
- 2026-07-27: added the explicit-state hotfix and cross-language regression coverage.
- 2026-07-27: reproduced the follow-on incident-history 503 against the live Guest PostgreSQL
  service. Added an explicit JSON text-extraction boundary and PostgreSQL-backed regression proof.
