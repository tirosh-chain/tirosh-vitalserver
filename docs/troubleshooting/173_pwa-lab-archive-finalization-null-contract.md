# PWA rejects Product Lab sessions when archive finalization null fields disappear

> ID: TS-173
> Category: Runtime Control PWA
> Owner: macOS Runtime Control contract
> Status: resolved

## Symptoms

The Product Lab page loads the catalog but fails the session query with:

```text
The response for /runtime/lab/sessions did not match the PWA contract.
First mismatch: sessions[0].archiveFinalization.updatedAt (invalid_type) Invalid input
```

The same response can fail next at `archiveFinalization.readError`. Existing Lab sessions and
their recorder data remain stored, but the PWA cannot display or control the selected session.

## Impact

This is a Runtime Control projection failure. It does not delete the Lab session, recovery
artifact, or recorder data. Reinstalling the VM or clearing Lab state is unnecessary.

## Cause

Product Lab correctly returned explicit nullable evidence:

```json
{"state":"exported","updatedAt":null,"readError":null}
```

`RuntimeLabArchiveFinalization` used synthesized Swift `Codable`. After the Helper decoded the
Guest response, `JSONEncoder` omitted optional properties whose values were `nil`, producing a
Host response such as `{"state":"exported"}`. The OpenAPI and PWA contracts require
`updatedAt` and `readError` to be present while allowing their values to be `null`; missing and
null have different meanings.

The PWA finalization-state enum and labels were also stale: they still used `uploaded`, while
recorder ingress and the Swift contract expose the distinct `exported` and `published` states.

## Checks

Inspect the Runtime Control response without changing session state:

```sh
curl -sS http://127.0.0.1:18320/runtime/lab/sessions
```

For every non-null `archiveFinalization`, verify that `state`, `updatedAt`, and `readError` are
present. `updatedAt: null` and `readError: null` are valid; absent keys are contract failures.

## Actions

Install a Helper build containing TS-173. The fix does not require deleting or recreating the VM.
Refresh the Product Lab page after the updated Helper and PWA are running.

## Prevention

`RuntimeLabArchiveFinalization` now has explicit Swift encoding and decoding:

- encoding writes `nil` as JSON `null` for both required nullable fields;
- decoding rejects a missing key instead of inferring it as `nil`;
- PWA and OpenAPI accept `exported` and `published`, and reject obsolete `uploaded`;
- contract tests cover explicit null preservation and missing-key rejection.

UI labels use recovery artifact export terminology so cold-path artifacts are not presented as
already published Vital Files.

## Operational Notes

Do not loosen the PWA schema to make these fields optional. That would hide an invalid Host
contract and merge missing evidence with an explicitly observed null value.

## Related Cases

- `TS-137`: Product Lab finish and recorder-ingress cold-path ownership
- `TS-169`: Vital Files upload memory and request boundaries

## Follow-up

- 2026-07-22: Explicit nullable encoding, finalization state synchronization, and PWA labels fixed.
