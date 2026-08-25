# Runtime Control omits Recorder observability null fields

> ID: TS-232
> Category: Recorder observability / Runtime Control PWA
> Owner: Host Runtime Control response contract
> Status: active

## Symptoms

An installed Helper can show an online Recorder and a working packet activity
graph while every Recorder health section fails contract validation. The PWA
reports the first missing field independently for each request:

```text
support.source (invalid_type)
readError (invalid_type)
nextCursor (invalid_type)
```

The failures correspond to observability detail, timeline, and incident-history
responses. Recorder admission and Guest Control queries may still be healthy.

## Cause

Guest Control owns the response state and emits required nullable fields as
explicit JSON `null`. The Host decodes those documents into Swift optional
properties and then re-encodes them for the loopback Runtime Control API.

Swift's synthesized `Codable` encoder uses `encodeIfPresent` for an optional
property. A `nil` value therefore removes the key instead of encoding `null`.
The PWA correctly rejects that omission because the OpenAPI contract requires
the key and uses `null` to distinguish a reported empty value from a missing
provider contract.

## Checks

Check the Guest owner and the installed PWA separately. For a Recorder without
an observer report, Guest Control should return a complete `notReported`
document:

```sh
curl -sS \
  http://GUEST_IP:18330/runtime/vitaldb/recorders/VR_CODE/observability
```

Verify that nullable keys such as `support.source`, `report.receivedAt`, and
`readError` are present with JSON `null`. A healthy Guest response does not
prove that the Host re-encoded the same contract correctly.

Open the installed Runtime Control PWA at
`http://127.0.0.1:18321/recorders`, select the same Recorder, and inspect the
three health sections. Contract errors naming `support.source`,
`timeline.readError`, or `incidents.nextCursor` identify Host-side key loss,
not Guest absence or an empty history.

## Actions

Install a package or update bundle that uses required-nullable encoding for the
Recorder observability detail and history contracts. Restarting the current
Platform Agent cannot repair the encoded document because the defect is in its
response binary.

After update, select an online Recorder without observer data. The PWA must
render explicit `notReported` or empty-history states without a contract error.

## Prevention

Required nullable contract properties use a shared Swift coding wrapper that:

- encodes `nil` as an explicit JSON `null`;
- rejects a missing key during decoding;
- preserves the wrapped domain type without turning missing into `nil`.

Regression coverage round-trips Recorder detail, timeline, and incident-page
documents and removes one required nullable key from each response to prove that
decoding fails closed.

Do not relax the PWA schema to accept omitted keys. That would collapse missing
provider state into an explicit `null` state and hide future producer drift.

## Related Cases

- `TS-190`: Guest Control Recorder-without-observer response completeness.
- `TS-231`: Installed Recorder observability proof service-start retry.

## Follow-up

- 2026-08-25: reproduced on installed Helper 0.2.2 with online Recorder
  `06311eba`. Guest Control returned complete explicit-null documents, while the
  PWA rejected Host responses first at `support.source`, `readError`, and
  `nextCursor`.
- 2026-08-25: added required-nullable Swift coding and focused contract tests.
  Installed package verification remains pending.
