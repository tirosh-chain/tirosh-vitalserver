# Helper stable update specification is hand-assembled

> ID: TS-199
> Category: Update / Packaging
> Owner: Helper release composition
> Status: active

## Symptoms

- `update-bootstrap-bundle` succeeds only after a developer manually writes
  `payload/update-specification.json` and copies files into a payload root.
- A release can fail late with `product update artifact digest mismatch`,
  `layer order mismatch`, or `file closure differs`.
- Two release scripts can assign different IDs, paths, dependencies, or
  rollback meanings to the same Helper layer.
- A Host release archive can accidentally contain the stable installation
  manager or handoff supervisor that must remain alive while that archive is
  applied.
- A rollback smoke can report failure before the asynchronous Host owner has
  settled its journal, or confuse successful handoff admission with successful
  product application.

## Impact

The generic bootstrap signer can correctly authenticate the bytes it receives
without proving that the release process selected the intended Helper product
layers. Manual document assembly therefore makes releases hard to reproduce and
can produce a signed bundle that cannot execute or roll back.

## Cause

The stable bootstrap boundary intentionally does not know Helper packaging.
Before a Helper-owned release model existed, tests and release experiments
assembled the Product Update Specification as untyped dictionaries. Artifact
identity, dependency order, executor configuration, and rollback availability
could drift independently from the payload selected by the release process.

The generic signer is not the owner that should repair this: teaching it Helper
layer rules would couple the permanent bootstrap contract to product packaging.

## Checks

Run the focused release-model and closure test:

```sh
uv run --project packages/vitalserver-devtools pytest \
  packages/vitalserver-devtools/tests/unit/test_helper_stable_update_release.py
```

Inspect a candidate specification and verify that every declared artifact is
present in its prepared payload root before signing:

```sh
uv run --project packages/vitalserver-devtools \
  vitalserver-devtools verify-update-bootstrap-bundle \
  --bundle <candidate.tar.gz> \
  --publisher-trust-store <publisher-trust-store.json>
```

## Actions

1. Construct the specification through
   `HelperStableUpdateReleasePlan` and its explicit layer, artifact, executor,
   configuration, and rollback declarations.
2. Encode it with `encode_helper_stable_update_specification`.
3. Let the release-composition adapter observe the selected files and provide
   exact path, SHA-256, size, and media type declarations.
4. Pass the resulting specification and prepared payload root to the existing
   generic bootstrap signer.
5. Do not derive a rollback artifact from the installed machine or select a
   latest backup. If no signed baseline artifact was supplied, declare rollback
   `unsupported` with an explicit reason.
6. Compose the Host layer with the Helper-specific Host release composer. It
   rejects archives that contain `host-installation-manager` or
   `update-handoff-supervisor` in their replaceable file/service closure.
7. Run the installed success proof and a separately signed Host-failure bundle
   proof. The latter must preserve ordered apply receipts for
   Container, Guest Runtime, and failed Host Platform, followed by successful
   Guest Runtime and Container rollback receipts.

## Prevention

- Keep the Helper release model pure: it consumes complete declarations and
  neither reads the filesystem nor invents missing state.
- Validate the generated document with the same strict Product Update
  Specification policy consumed by the bundle verifier.
- Prove the complete apply/executor/configuration/rollback closure with fake
  executable fixtures before wiring platform effects.
- Keep Helper product composition outside
  `bootstrap_bundle_service.py`; that generic signer must remain stable.
- Treat `apply-update-bootstrap` success as durable handoff admission, not
  terminal layer success. Poll the Host owner journal with explicit timeout
  and interval, then validate the signed report and Runtime Control projection.

## Operational Notes

The public `dist/update/*` path now publishes the signed three-layer closure.
Static verification does not replace field proof: release acceptance still
requires an installed success cycle and a separately signed Host-failure
rollback cycle against the packaged product. Missing journal state, owner read
failure, timeout, terminal failure, and invalid receipt order stay distinct.

## Related Cases

- TS-188
- TS-194
- TS-195
- TS-196

## Follow-up

- 2026-07-29: Added the pure Helper stable update release model,
  specification encoder, and signed fake-payload closure test.
- 2026-07-29: Wired real Container, Guest Runtime, and Helper Host Platform
  layer contracts into `dist/update/*`; added publisher trust verification,
  stable-owner exclusion, durable handoff settlement, ordered effect receipts,
  and installed success/Host-failure rollback proof commands. Packaged field
  evidence remains the release gate.
