# Ubuntu cloud image has no Guest boot artifacts

- **ID:** TS-192
- **Category:** Packaging / Guest bootstrap
- **Owner:** macOS release input process
- **Status:** active

## Symptom

`macos-development-guest-boot-input-assembly` stops in C42 before C43 or C47
publishes an artifact:

```text
C42 extractor failed exitCode=1
reason=Guest Linux boot artifact extraction failed
stage=boot-resource-extract
reason=C42 declared Guest boot path /boot/vmlinuz cannot be opened:
target file boot/vmlinuz does not exist and was not asked to create
```

Trying a versioned path such as `/boot/vmlinuz-6.8.0-60-generic` produces the
same result for the Ubuntu Noble cloud image used by the macOS development
release.

## Cause

The selected Ubuntu cloud disk and the boot-loader inputs are different
release resources. The root ext4 filesystem in
`ubuntu-24.04-server-cloudimg-arm64.img` has an empty `/boot` directory. Ubuntu
publishes the matching kernel and initial RAM disk separately under that
release's `unpacked/` directory.

Filesystem strings are not a state contract. A raw disk can retain an old
kernel filename in deleted or unrelated bytes even though the path is absent
from the current ext4 directory. Selecting a Guest path from `strings` output
therefore produces a false source declaration.

## Fix direction

Select the immutable boot resources as explicit `external-artifact` inputs:

- `ubuntu-24.04-server-cloudimg-arm64-vmlinuz-generic`
- `ubuntu-24.04-server-cloudimg-arm64-initrd-generic`

Bind both resources to their HTTPS origin URI, Ubuntu release, size, and
SHA-256 identity. Keep the raw cloud disk as the separately declared C73/C42
root-storage source. C42 validates the external identities, decompresses the
gzip kernel into `boot/Image`, and copies the initial RAM disk without
inventing a Guest filesystem path.

Do not copy boot files from an older build merely because their filenames
match. Re-download or reuse them only when their recorded origin and SHA-256
match the selected immutable Ubuntu release.

## Prevention principle

The release caller owns boot-resource selection. C42 must open only the
declared source and fail when it is absent; it must not discover the newest
kernel, follow stale filename evidence, or fall back from a missing Guest path
to an external file.

Keep these meanings separate:

- source cloud disk identity;
- root filesystem layout and partition index;
- kernel source representation;
- initial RAM disk source representation;
- uncompressed kernel output consumed by Apple Virtualization.

## Verification

The successful C42 receipt must identify the expected kernel and initial RAM
disk outputs, and C47 must bind the same identities into the package receipt:

```sh
jq '.bootResources' \
  runtime-platform/.tmp/<release>/guest-boot-inputs/c42-artifacts/guest-linux-boot-artifact-extraction-receipt.json

jq '.guestArtifactCompilation.macOSGuestArtifactManifest' \
  runtime-platform/.tmp/<release>/macos-release-package-assembly-receipt.json
```

For Ubuntu Noble release `20250516`, the verified output identities are:

- uncompressed ARM64 `boot/Image`:
  `49a14f0fab402ae89e53884fecc1bf56b5d2002dc1e5374ff668e757f6535326`;
- `boot/initrd.img`:
  `f559578a26c655526ac732e7c817026f0baa23606e72230a55a6bd8dc1c5ac45`.

These values describe that release only and are not defaults for a newer
Ubuntu release.

## Related cases

- [TS-148](148_macos_virtual_machine_start_fails_before_guest_boot_console.md)

## Follow-up

- 2026-07-27: reproduced while building the issue #40 stable bootstrap
  development package. External Ubuntu `unpacked/` boot resources produced a
  verified C42/C43 chain and a C47 package.
