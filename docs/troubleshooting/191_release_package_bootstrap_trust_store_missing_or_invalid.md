# Release package bootstrap trust store is missing or invalid

> ID: TS-191
> Category: Packaging / Update / Local development
> Owner: update release publisher tooling
> Status: active

## Symptoms

`make dist/pkg/dev`, `make dist/dmg/dev`, or a release profile fails before
rootfs compile with one of these messages:

```text
error: VM_UPDATE_BOOTSTRAP_TRUST_STORE is required
update bootstrap trust store is unavailable or invalid
```

An artifact verification invoked without the same release input fails as well.

## Impact

No PKG or DMG should be distributed without the public trust root required by
the installed stable updater bootstrap. The build stops before expensive
VM/rootfs compile when the input is missing or invalid. Existing installed
runtime data is not changed.

## Cause

The stable updater authenticates the release publisher with an installed
Ed25519 public-key trust store. That trust root is owned by the release process,
not by source defaults or the package builder. Missing, unreadable, symlinked,
malformed, empty, duplicated, or non-Ed25519 key input therefore cannot be
converted into a package with an empty/default trust state.

## Checks

```sh
test -n "${VM_UPDATE_BOOTSTRAP_TRUST_STORE:-}"
test -f "${VM_UPDATE_BOOTSTRAP_TRUST_STORE}"
test ! -L "${VM_UPDATE_BOOTSTRAP_TRUST_STORE}"
.venv/bin/vitalserver-devtools --config config/vm-build.toml \
  release-package-environment-preflight \
  --release-file apps/vitalserver-macos-runtime/release-dev.json \
  --output-kind dmg \
  --update-bootstrap-trust-store "${VM_UPDATE_BOOTSTRAP_TRUST_STORE}"
```

The file must use strict schema `v1`, contain at least one unique key ID, use
`algorithm: ed25519`, and encode exactly 32 public-key bytes as base64.

## Actions

Materialize the release-approved **public-key-only** trust store outside the
repository, then pass its exact path to the complete delivery gate:

```sh
export VM_UPDATE_BOOTSTRAP_TRUST_STORE=/secure/release/update-bootstrap-trust-store.json
make dist/dmg/dev
```

Use the stable release manifest and `make dist/dmg/release` for a stable
artifact. Do not copy a private signing key into the JSON, source tree, PKG, or
DMG. Do not substitute a test key to make preflight pass.

## Prevention

PKG/DMG release commands require the explicit trust-store input. Preflight
strict-decodes it before VM/rootfs compile, package staging copies its exact
bytes, and DMG artifact verification expands the PKG and compares the installed
file byte-for-byte with the same release input.

## Operational Notes

Rotating a publisher key means deliberately changing the release input and its
key IDs. It is not inferred from the private key used to sign a bundle. The
bundle `publisherKeyId` must match a key admitted in the installed trust store.

## Related Cases

- `TS-188`: bundle integrity is not publisher authentication.
- `TS-190`: portable Ed25519 signing does not rely on macOS OpenSSL.

## Follow-up

- 2026-07-27: PKG/DMG assembly and artifact readback gained an explicit
  release-owned trust-store contract.
