# Release sync mutated compile inputs after Docker export

> ID: TS-119
> Category: Packaging / Release contract / Rootfs compile
> Owner: macOS release-input preparation and VM compile boundary
> Status: resolved

## Symptoms

`make dist/dmg/dev` can fail before the golden rootfs VM starts with a message
such as:

```text
release sync pattern did not match: \("vitalserver:[^"]+", "app"\)
```

More generally, a release manifest image change could produce a Docker archive
from the old `config/vm-build.toml` plan and then stage a changed
`Support/Guest/compose.yaml` into the Guest.

## Impact

The build order was ambiguous: the rootfs cache fingerprint and Docker bundle
could be decided before release sync rewrote compile inputs. A successful
archive or cached rootfs therefore did not necessarily prove the final staged
Guest Compose contract.

The immediate failure appeared after Guest bootstrap correctly removed its
product-image rebuild fallback. The old release script still tried to patch the
now-absent implementation by regular expression.

## Cause

`Support/Build/sync-release.py` mixed two different jobs:

1. generate Swift release metadata; and
2. rewrite tracked Compose, VM build configuration, and Guest Python source.

The second job was a hidden input mutation. It made release behavior depend on
which target happened to run first and allowed a stale source pattern to stop
the whole compile.

## Checks

Run the release-input contract directly before an expensive compile:

```sh
make devtools/release-contract
```

The command must either finish without changing `Support/Guest/compose.yaml`,
`config/vm-build.toml`, or Guest Python source, or fail with the exact source
path, service/field, expected image, and actual image.

For the normal field-delivery proof, run:

```sh
make dist/dmg/dev
```

Its order is review → release-contract → package environment preflight → PWA
build → fresh rootfs compile → DMG readback → golden runtime smoke.

## Fix Direction

Keep `sync-release.py` limited to validation plus the three designated Swift
generated-source files. Treat Guest Compose and the VM Docker plan as immutable
compile inputs. If a service image changes, update the release manifest,
Compose, and VM Docker plan together in the same reviewable change.

The release contract must run before rootfs fingerprint/cache selection and
before Docker export. Existing rootfs cache receipts from the old mutation
pipeline are invalidated by the rootfs contract version.

## Prevention

Build steps may materialize explicitly designated generated output, but must
not silently repair or rewrite source contracts. A mismatch is compile evidence
and must remain a failure.

If dev and release later need different service image identities, use
profile-scoped immutable inputs or profile-scoped rendered deploy material with
its own receipt. Do not restore worktree rewriting as a compatibility path.

## Related Cases

- TS-107: rootfs cache must include actual Guest compile material.
- TS-117: Docker export must prove the selected Guest platform archive.
- TS-118: Guest must not rebuild missing product images.

## Follow-up

- 2026-07-12: replaced regex source mutation with release manifest ↔ Compose ↔
  VM Docker-plan validation, introduced the pre-fingerprint
  `release-contract` target, and invalidated the old rootfs cache contract.
