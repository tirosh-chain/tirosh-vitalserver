# Dev DMG Rebuild Stale Unmounted Attachment

> ID: TS-064  
> Category: Packaging / Local development  
> Owner: devtools macOS release DMG builder  
> Status: resolved

## Symptoms

`make dist/dmg/dev/cached` 또는 현장 전달 gate의 DMG artifact 생성 단계가 기존 DMG를 unmount한 뒤 실패합니다.

```text
RuntimeError: DMG output is currently attached; detach it before rebuilding:
/path/to/dist/VitalServerHelper-0.1.13-dev.dmg (not mounted)
```

`make dist/dmg/dev/verify` can also fail while inspecting the generated DMG layout:

```text
hdiutil: couldn't eject "disk6" - Resource busy
subprocess.CalledProcessError: Command '['hdiutil', 'detach', '/Volumes/VitalServer Helper']'
returned non-zero exit status 16.
```

The next rebuild may then fail earlier with a stale attached image that has no mount point.

## Impact

The operator has already unmounted the volume, but the disk image remains attached in `hdiutil info`. The build stops before replacing the output DMG.

## Cause

The DMG builder treated every matching attached image as a hard blocker. That was correct for mounted volumes, but too strict for an unmounted stale attachment that still reports a device entry.

The artifact verifier also detached the inspected DMG through the mount path. When macOS reports the volume as busy, the image can remain attached even after the mounted volume disappears. That left explicit external state behind for the next build.

## Checks

```sh
hdiutil info
```

If the output DMG appears with no `mount-point` but still has a `dev-entry`, it is a stale unmounted attachment.

## Actions

The devtools DMG builder now keeps mounted images as explicit blockers, but detaches matching unmounted attachments through `hdiutil detach <dev-entry>` before unlinking and recreating the output DMG.

The artifact verifier detaches generated DMGs through the `dev-entry` reported by `hdiutil attach` when available. If the normal detach fails, it retries once with `hdiutil detach -force <dev-entry>`. If force detach also fails, verification fails explicitly instead of hiding the cleanup failure.

## Prevention

- Mounted images stay visible as user/action state and must not be silently replaced.
- Unmounted attached images are build-owned stale attachment state and can be detached by the build tool using the explicit `dev-entry` from `hdiutil info`.
- DMG verification cleanup should prefer device entries over mount paths and report any final detach failure as a packaging verification failure.

## Related Cases

- TS-024

## Follow-up

- 2026-06-10: cache-preferred dev DMG packaging failed with `(not mounted)` even after unmount. The builder now detaches unmounted matching attachments and the dev DMG build completed.
- 2026-06-15: `make dist/dmg/dev/verify` failed during artifact inspection because `hdiutil detach` by mount path returned `Resource busy`. The verifier now uses the device entry and force-retries cleanup before reporting a final detach failure.
