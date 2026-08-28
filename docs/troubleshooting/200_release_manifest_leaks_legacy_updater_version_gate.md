# Release manifest leaks the legacy updater version gate

> ID: TS-200
> Category: Update / Packaging / Runtime Control
> Owner: Helper release contract
> Status: resolved

## Symptoms

- Building or synchronizing a Helper release fails unless
  `release.json` contains `minUpdaterVersion`.
- Runtime Control and the PWA display a minimum updater version even though
  stable updates use the bootstrap envelope and Product Update Specification.
- A release-version change requires editing a compatibility value that is not
  owned by the stable update protocol.

## Impact

The top-level product release contract appears to impose a version gate that
the stable bootstrap does not consume. Release tooling, generated Swift,
OpenAPI, and presentation can then drift independently and make operators
believe an older installed Helper is categorically unable to process a newer
update specification.

## Cause

`minUpdaterVersion` belongs to the retained legacy schema-3 bundle serializer.
It leaked into the Helper release source of truth, Python release model,
generated Swift constants, Runtime Control read model, OpenAPI schema, and PWA.
Those consumers promoted a legacy serialization detail into product state.

## Checks

Validate both release manifests and generated-source policy:

```sh
.venv/bin/python -m pytest -q \
  packages/vitalserver-devtools/tests/unit/test_release_manifest.py \
  packages/vitalserver-devtools/tests/unit/test_release_sync_contract.py
```

Verify that current product contracts do not expose the field:

```sh
if rg 'minimumUpdaterVersion|minUpdaterVersion' \
  apps/vitalserver-macos-runtime/release.json \
  apps/vitalserver-macos-runtime/release-dev.json \
  apps/vitalserver-macos-runtime/Sources/Contracts/RuntimeControl \
  apps/vitalserver-runtime-pwa/src \
  docs/runtime/runtime-control.openapi.json; then
  echo "legacy updater version gate leaked into a current product contract" >&2
  exit 1
fi
```

The focused Swift test intentionally contains the JSON key as a negative
assertion and is not a provider contract.

## Actions

1. Remove `minUpdaterVersion` from `release.json` and `release-dev.json`.
2. Reject the legacy field explicitly in both Python release loading and
   release-to-Swift synchronization.
3. Remove the field from `ReleaseManifest`, generated release constants, and
   `RuntimeReleaseInfo`.
4. Remove the projection from Runtime Control OpenAPI, the embedded console,
   PWA decoding, and the Info page.
5. Keep the legacy schema-3 publisher isolated until it is removed. Its
   required SemVer slot is serialized as the explicit no-gate value `0.0.0`;
   it is not product release state.

## Prevention

- Stable update compatibility is structural: the installed bundle-owned
  updater validates the authenticated bootstrap envelope and delegates the
  signed specification to its declared next updater.
- Release source-of-truth fields must have a current owner and consumer.
  Legacy serializer fields must not be projected through product APIs.
- Contract tests must reject obsolete top-level fields rather than silently
  ignoring them, so they cannot reappear through copied release files.
- Generated Swift and TypeScript must be regenerated from their source
  contracts in the same change.

## Related Cases

- TS-188
- TS-196
- TS-198
- TS-199

## Follow-up

- 2026-07-29: Helper release metadata moved to 0.2.2 and the legacy minimum
  updater version projection was removed from current release and read
  contracts.
