# Electron Builder DMG build leaves a temporary disk image attached

> ID: TS-157
> Category: Packaging / Local development
> Owner: Runtime Console desktop package builder
> Status: active

## Symptoms

`npm --prefix runtime-platform/interfaces run package:macos` can fail while
Electron Builder resizes or verifies its temporary DMG.

```text
hdiutil: resize failed - Resource temporarily unavailable
hdiutil: verify: unable to recognize "...dmg" as a disk image.
```

The failed run can leave a Builder-created temporary disk image attached even
though the final Runtime Console DMG was not produced.

## Impact

The macOS operator-interface artifact is not trustworthy for that run. A
subsequent package build can also fail until the specific stale attachment is
removed. This is a packaging-only condition; it must not be treated as a
Runtime Platform Host, Guest, or data-state failure.

## Cause

`hdiutil` owns disk-image attachments outside the Node package process. A
Builder process interrupted while preparing its temporary image can leave that
external attachment behind. The packaging command cannot safely infer which
other images are disposable.

## Checks

Inspect the full attachment list before any detach action:

```sh
hdiutil info
```

Only an entry whose image path is an Electron Builder temporary DMG from the
failed Runtime Console package invocation is relevant. Do not detach a macOS
system image, an operator-mounted image, or an image whose ownership cannot be
established from this output.

## Actions

1. Record the failing package output and the matching `hdiutil info` entry.
2. Confirm that the `dev-entry` belongs to the failed Builder temporary DMG.
3. Detach only that exact device entry, for example:

   ```sh
   hdiutil detach /dev/diskN
   ```

4. Re-run the package command and require `hdiutil verify` on the resulting
   final DMG before publishing it.

If the device remains busy, stop and identify the process using the volume;
do not use a broad detach loop or silently delete a DMG path.

## Prevention

- Package verification treats a failed `hdiutil` operation as a failed build;
  it does not publish a partial image.
- Cleanup is evidence-scoped to the exact temporary image selected from
  `hdiutil info`; the package script never detaches arbitrary disks.
- The Runtime Console package staging directory is removed after its child
  process exits, so source dependencies and package contents remain separate
  from this OS-owned attachment state.

## Related Cases

- TS-064

## Follow-up

- 2026-07-20: an Electron Builder macOS DMG run reported `Resource temporarily
  unavailable` and left two Builder temporary images attached. After inspecting
  the exact paths and detaching only those entries, a fresh package run and
  `hdiutil verify` succeeded.
