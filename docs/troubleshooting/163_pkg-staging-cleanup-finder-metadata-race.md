# macOS artifact staging cleanup fails when Finder recreates metadata

> ID: TS-163
> Category: Packaging / Local development
> Owner: VitalServer devtools
> Status: fixed and verified

## Symptoms

DMG or Product Update build reaches artifact staging and fails while removing the previous staging
tree:

```text
OSError: [Errno 66] Directory not empty: '.../node_modules'
make[2]: *** [internal/vm/dmg] Error 1
```

The signing messages immediately before the traceback, including `replacing existing signature` and
`install_name_tool` signature invalidation warnings, are not the failing stage.

## Impact

Packaging stops before `pkgbuild`. The compiled rootfs and Guest deploy inputs are not proven invalid,
and deleting or reinstalling the installed product is unnecessary.

For Product Update builds the same race can stop the build before
`update-bundle-<channel>-product-update-<releaseLabel>.tar.gz` is replaced.

## Cause

Package and Product Update staging used independent single `shutil.rmtree()` calls to clear prior
trees. Finder could recreate `.DS_Store` inside a directory after `rmtree` enumerated it but before the
parent directory was removed. The resulting `ENOTEMPTY` error aborted a valid build. The captured
package failure left `node_modules/.DS_Store` as the only child of the reported directory; Product
Update staging had the same unbounded failure path.

## Checks

```sh
find '.tmp/vitalserver-vm-pkg/root' -name '.DS_Store' -o -name '._*'
```

Confirm the traceback ends at `installer_package.py:stage_pkg_root`,
`update_artifacts.py:stage_update_artifacts`, or another artifact staging cleanup call rather than a
codesign command.

## Actions

The macOS artifact-files adapter owns one shared staging cleanup contract. PKG, DMG, troubleshooting
tools, copied artifact trees, and Product Update staging all call it. Cleanup retries only `ENOTEMPTY`,
removes Finder `.DS_Store` and AppleDouble files between attempts, and preserves every other filesystem
error as an explicit build failure. Artifact tar creation independently excludes `.DS_Store`,
AppleDouble, and `__pycache__` path components, so metadata recreated after staging cleanup cannot enter
the product archive. Guest deploy copying and digesting also exclude the same non-product metadata under
TS-162.

Re-run the same DMG or Product Update target. A manual clean or product reinstall is not required.

## Prevention

- All macOS artifact staging cleanup must tolerate bounded Finder metadata recreation races through one
  shared adapter contract.
- Permission, ownership, I/O, and other deletion failures must not be converted to success.
- Finder metadata must stay excluded from artifact material and receipt computation.

## Related Cases

- `TS-162`: Finder metadata changes the staged Guest deploy receipt.

## Follow-up

- 2026-07-20: Reproduced the reported `ENOTEMPTY` path with `.DS_Store` as the remaining child and added a focused retry test.
- 2026-07-20: Full DMG build passed staging cleanup, `pkgbuild`, DMG artifact verification, and golden disk runtime boot smoke.
- 2026-07-20: Moved bounded cleanup to the shared artifact-files adapter and routed Product Update,
  PKG, DMG, troubleshooting tools, and copied artifact trees through it.
- 2026-07-20: Deep inspection of the first rebuilt Product Update found Finder metadata recreated inside
  `guest-deploy.tar.gz` after staging. Added an independent tar filter and nested-archive regression test.
- 2026-07-20: Rebuilt the dev Product Update after the tar fix; manifest/checksum verification and deep
  metadata inspection of all four nested artifact archives passed.
