# Rootfs receipt mismatch after Finder metadata enters compiled deploy

> ID: TS-162
> Category: Packaging / Rootfs compile / Guest deploy
> Owner: VitalServer devtools
> Status: fixed and verified

## Symptoms

DMG compile reaches package staging and then fails before `pkgbuild`:

```text
error: staged Guest deploy does not match rootfs artifact receipt; expected=... actual=...
```

The rootfs artifact and its manifest exist, but the staged deploy contains additional `.DS_Store`
files under directories such as `vendor/`.

## Cause

Initial Guest deploy assembly excluded macOS Finder metadata, but the material digest still traversed
and hashed it. After rootfs compile recorded the deploy digest, Finder could create `.DS_Store` at
different paths or times in the compiled source and package staging trees. Restaging also originally
copied the compiled tree without the same ignore contract. Either mismatch made non-product metadata
change the rootfs receipt.

The digest mismatch is valid compile evidence. It must not be bypassed or replaced with the newly
computed digest.

## Fix

Compiled Guest deploy restaging and material digest traversal now use the same `IGNORED_NAMES` contract
as initial source staging. They exclude `.DS_Store`, AppleDouble `._*`, and `__pycache__` entries while
continuing to copy and verify all product material. Changes to product files still produce a receipt
mismatch.

## Checks

```sh
find .tmp/vitalserver-vm-golden/data/deploy -name '.DS_Store' -print
find '.tmp/vitalserver-vm-pkg/root/Library/Application Support/VitalServerHelper/vm/data/deploy' \
  -name '.DS_Store' -print
```

After restaging, the package deploy must contain none of these ignored metadata files and its material
digest must equal `guestDeploy.materialSha256` in `rootfs-base.raw.gz.manifest.json`.

## Prevention

- Initial assembly and compiled-material restaging must share one ignore contract.
- Finder metadata is not product input and must not enter Guest deploy artifacts.
- Receipt mismatch remains a hard failure for every non-ignored file or mode change.

## Follow-up

- 2026-07-20: Full `make internal/vm/dmg/dev` passed artifact verification and golden disk runtime boot smoke with canonical Guest deploy digest `ec2f102010a136f914acfd36f85bd0fa9954f004b7557dbcaca4d51d0c4b44bf`.
