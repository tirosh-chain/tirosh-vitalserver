# Release DMG verification fails while an orphaned helper holds the image

> ID: TS-177
> Category: Packaging / Local development
> Owner: VitalServer Helper DMG builder
> Status: resolved

## Symptoms

The Helper PKG and DMG are created, but the final artifact verification fails:

```text
hdiutil: verify: unable to recognize ".../VitalServerHelper-0.2.0-dev.dmg"
as a disk image. (Resource temporarily unavailable)
hdiutil: verify failed - Resource temporarily unavailable
```

`hdiutil info -plist` may also stop responding. Re-running the full rootfs and package build does
not make the existing DMG holder release the file.

## Cause

`hdiutil create` can return after leaving its macOS `diskimages-helper` child alive with parent PID
1. The orphan can retain an open descriptor for the completed output DMG. A second `hdiutil`
operation then receives `EAGAIN` even though the image bytes and checksum are valid.

For the observed failure, `lsof` identified one exact holder of the release DMG. The process was a
PPID 1 `diskimages-helper`, its only open `.dmg` path was the build output, and it remained idle after
`SIGTERM`. After terminating that exact process, the same artifact passed `hdiutil verify`; the DMG
did not need to be rebuilt.

## Fix

The DMG adapter now waits for normal descriptor release after `hdiutil create`. If the output is
still held, automatic recovery is allowed only when every holder satisfies all of these conditions:

- executable basename is exactly `diskimages-helper`;
- parent PID is exactly 1;
- the process's complete open `.dmg` set contains only the exact release output path.

The adapter sends `SIGTERM`, waits, and escalates to `SIGKILL` only when the same ownership proof is
still valid. Any other holder fails the build with PID, parent PID, executable, and open DMG paths;
it is never signaled. Artifact verification applies the same release guard before `hdiutil verify`.

`hdiutil info -plist` also has a bounded timeout so a DiskImages framework stall is reported instead
of hanging the build indefinitely.

## Checks

Inspect the exact output if manual diagnosis is required:

```sh
lsof -nP "/absolute/path/to/VitalServerHelper-0.2.0-dev.dmg"
ps -p <PID> -o pid=,ppid=,command=
lsof -nP -p <PID>
```

Do not signal the process unless its identity and complete open DMG set satisfy the ownership rule
above. After release, verify the existing artifact directly:

```sh
hdiutil verify "/absolute/path/to/VitalServerHelper-0.2.0-dev.dmg"
make internal/vm/dmg/dev/artifact-verify
```

## Prevention

- DMG creation is not complete until the exact output descriptor is released.
- Recovery is based on explicit process ownership evidence, not an error string or process name
  alone.
- The builder never kills arbitrary `hdiutil`, `diskimages-helper`, mounted operator images, or a
  process that has another DMG open.
- `hdiutil verify` remains required; cleanup cannot convert a corrupt or incomplete image into a
  successful artifact.

## Related Cases

- TS-157
