# Generated Guest wheel changed rootfs fingerprint during the same delivery run

> ID: TS-120
> Category: Packaging / Rootfs compile / Local development
> Owner: devtools Guest deploy compiler and rootfs cache contract
> Status: resolved

## Symptoms

`make dist/dmg/dev` finishes a clean golden-rootfs compile and DMG readback,
then unexpectedly starts a second golden-rootfs compile before runtime smoke.

The two rootfs contract fingerprints differ even though no reviewed product
input changed between the compile and smoke phases.

## Impact

The standard field-delivery gate becomes slower and harder to interpret. More
importantly, a cache fingerprint that can be changed by its own compile is not
a stable description of compile input.

## Cause

Guest deploy staging built the Guest Python wheel at:

```text
packages/vitalserver-guest-tools/dist/
```

That directory is inside the rootfs contract input tree. The first compile
therefore created a new input artifact; the later runtime-smoke prerequisite
calculated a different fingerprint and correctly refused to reuse the first
rootfs cache.

## Checks

Run the focused deploy and Make-contract tests:

```sh
uv run --project packages/vitalserver-devtools pytest \
  packages/vitalserver-devtools/tests/unit/test_guest_deploy_bundle.py \
  packages/vitalserver-devtools/tests/unit/test_delivery_makefile_contract.py
```

For the field-delivery proof, run:

```sh
make dist/dmg/dev
```

After its clean compile, the runtime-smoke phase must reuse the rootfs whose
receipt matches the unchanged input contract. It must not launch a second
rootfs compile.

## Fix Direction

Build the Guest wheel in a temporary directory and copy it only into the
explicit staged deploy material. Keep legacy source-tree `dist/` artifacts out
of the rootfs fingerprint scan, and bump the rootfs cache contract version so
an old cache cannot be reused.

## Prevention

Generated outputs must never live inside a source tree used as a compile
fingerprint input. A compile fingerprint describes declared source material;
the compiled deploy directory and rootfs receipt describe generated material.
Neither is allowed to mutate the other boundary.

## Related Cases

- TS-107: Guest-tools changes must invalidate a clean-install rootfs cache.
- TS-119: release preparation must not rewrite compile inputs after cache
  selection or Docker export.

## Follow-up

- 2026-07-12: Guest wheel staging moved to a temporary build directory;
  `packages/vitalserver-guest-tools/dist` was excluded as legacy generated
  output; rootfs contract version advanced to v6.
