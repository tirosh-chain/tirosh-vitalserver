# PWA Runtime Control reads fail contract validation or return 501

> ID: TS-143  
> Category: Runtime Control PWA / Runtime health  
> Owner: macOS Runtime Control API wire boundary  
> Status: resolved in code; package verification pending

## Symptoms

The PWA can show several failures after the installed Runtime and PWA load:

- `/platform/settings` rejects `settings.bridgedInterface` as an invalid type.
- `/runtime/settings` rejects `readError` as an invalid type.
- `/runtime/events` rejects `events[0].failure` as an invalid type.
- `/runtime/vitaldb/observations/latest` rejects `state`, `observation`, or
  `readError`, and recorder anomaly details remain incomplete.
- `/runtime/stack` or `/runtime/services/{service}/resource` returns HTTP 501,
  leaving CPU, memory, disk, and product service details unavailable.

These failures may appear together, but a contract validation failure and an
unimplemented Guest delegation are distinct states.

## Impact

The Runtime may still be healthy while the PWA cannot display or control the
affected resource. A failed read must not be interpreted as an empty setting,
zero resource usage, or an empty VitalDB observation. Reinstalling the VM does
not repair a Host wire-contract or delegation defect.

## Cause

Swift synthesized `Codable` omitted nullable values when they were `nil`.
The OpenAPI and PWA schemas require those nullable keys to be present with JSON
`null`, so valid owner state was rejected at the browser boundary.

The latest VitalDB route also discarded the explicit
`RuntimeVitalDBObservationSnapshot` wrapper and returned only the optional
observation. That collapsed `loaded`, `unavailable`, and `failed` reads into an
ambiguous document-or-null response.

Separately, the macOS Platform Agent handler did not delegate Guest stack and
service resource reads to the Runtime Controller client. Protocol default
methods therefore returned the explicit platform-affordance-unavailable error,
which the HTTP boundary reported as 501.

## Checks

Read the owner contracts directly and retain their response bodies:

```sh
curl -sS http://127.0.0.1:18321/platform/settings
curl -sS http://127.0.0.1:18321/runtime/settings
curl -sS http://127.0.0.1:18321/runtime/events
curl -sS http://127.0.0.1:18321/runtime/vitaldb/observations/latest
curl -sS http://127.0.0.1:18321/runtime/stack
```

Browser-session authentication may be required on an installed system. Export
logs instead of printing the root-owned automation token. Required nullable
fields must be visible as JSON `null`, and the VitalDB response must always
contain `state`, `observation`, and `readError`.

## Actions

- Install a package containing the corrected Runtime Control API and PWA.
- Reload the PWA after the Platform Agent is updated so the bundled schema and
  server wire contract have the same version.
- If a read still fails, preserve the exact endpoint, HTTP status, and response
  body. Do not replace the failed document with an empty UI model.

## Prevention

- Swift wire DTO tests assert that required nullable fields encode as explicit
  JSON `null` and reject a missing key when decoding.
- OpenAPI generation and PWA schema validation use the same explicit VitalDB
  snapshot shape for polling and SSE.
- macOS handler tests verify that Guest stack and service resource reads reach
  the Runtime Controller client instead of a protocol default implementation.
- The Status page reads the Vital Files directory from the Platform-owned
  settings contract and displays failed, unavailable, and missing states
  separately.

## Operational Notes

`Planned` network features are capability information, not a read failure.
They should remain distinct from unavailable Runtime settings and must not be
used to infer bridged interface or static address state.

## Related Cases

- TS-109
- TS-128
- TS-135
- TS-141

## Follow-up

- 2026-07-15: required nullable JSON encoding, explicit VitalDB snapshot
  response, Guest read delegation, and PWA Status presentation tests added.
