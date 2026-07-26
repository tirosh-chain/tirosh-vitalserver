# Linux Runtime image archive architecture mismatch

> ID: TS-111  
> Category: Packaging / Guest containers  
> Owner: Linux Runtime Bundle builder  
> Status: resolved

## Symptoms

A Linux bundle is named `amd64`, and its outer checksums pass, but containers
fail with `exec format error` on an x86_64 installation target.

## Impact

Offline installation cannot start the Product Stack. Retrying the same archive
does not help, and treating the filename as architecture proof can publish an
unbootable release.

## Cause

The original archive was assembled on Apple Silicon. Every saved image config
declared `linux/arm64`, even though the artifact filename declared `amd64`.
Docker archive filenames and image tags do not own image architecture.

## Checks

Inspect every config document referenced by the Docker save `manifest.json` or
OCI index. Each selected image must explicitly report `os=linux` and
`architecture=amd64`.

## Actions

Rebuild or resolve each image for `linux/amd64`, create a new image archive,
and rebuild the Linux bundle. Do not rename the existing archive.

## Prevention

`scripts/build_linux_runtime_bundle.py` parses Docker save and OCI archives and
rejects the build unless every referenced image config explicitly proves
`linux/amd64`. Unit tests include an arm64 rejection case.

## Operational Notes

Outer SHA-256 integrity proves that bytes were not changed. It does not prove
that their execution architecture matches the installation target.

## Related Cases

- TS-009
- TS-014

## Follow-up

- 2026-07-11: Reproduced before the Ubuntu 24.04 x86_64 installed acceptance;
  rebuilt all eleven images and passed the strict architecture gate.
