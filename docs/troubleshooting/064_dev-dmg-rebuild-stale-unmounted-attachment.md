# Dev DMG Rebuild Stale Unmounted Attachment

> ID: TS-064  
> Category: Packaging / Local development  
> Owner: devtools macOS release DMG builder  
> Status: resolved

## Symptoms

`make dist/dmg/dev` fails after the existing DMG was unmounted:

```text
RuntimeError: DMG output is currently attached; detach it before rebuilding:
/path/to/dist/VitalServerHelper-0.1.13-dev.dmg (not mounted)
```

## Impact

The operator has already unmounted the volume, but the disk image remains attached in
`hdiutil info`. The build stops before replacing the output DMG.

## Cause

The DMG builder treated every matching attached image as a hard blocker. That was correct
for mounted volumes, but too strict for an unmounted stale attachment that still reports a
device entry.

## Checks

```sh
hdiutil info
```

If the output DMG appears with no `mount-point` but still has a `dev-entry`, it is a stale
unmounted attachment.

## Actions

The devtools DMG builder now keeps mounted images as explicit blockers, but detaches matching
unmounted attachments through `hdiutil detach <dev-entry>` before unlinking and recreating
the output DMG.

## Prevention

- Mounted images stay visible as user/action state and must not be silently replaced.
- Unmounted attached images are build-owned stale attachment state and can be detached by the
  build tool using the explicit `dev-entry` from `hdiutil info`.

## Related Cases

- TS-024

## Follow-up

- 2026-06-10: `make dist/dmg/dev` failed with `(not mounted)` even after unmount. The builder
  now detaches unmounted matching attachments and the dev DMG build completed.
