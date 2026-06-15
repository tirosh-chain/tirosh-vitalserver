# Distribution Verification Phase Gaps

## Symptom

Distribution commands can appear successful even though a later phase still has an unverified
failure path. Examples:

- `dist/pkg/*/verify` and `dist/dmg/*/verify` do not run the same review gate.
- `dist/troubleshooting/*` stages command files but does not verify executable bits or wrapper
  contracts.
- update bundle verification checks the archive, but the static smoke and apply smoke interfaces are
  not visible as separate phases.
- installation can be run without a single target that first verifies the package and then checks the
  installed runtime.

## Cause

Distribution targets historically grew around artifact type instead of release phase. That made build,
artifact verification, install verification, update smoke, and installed runtime smoke easy to confuse.
The missing phase is not a runtime state and must not be hidden by a successful build target.

## Fix Direction

Expose each distribution phase as an explicit target:

```sh
make dist/pkg/dev/verify
make dist/dmg/dev/verify
make dist/troubleshooting/dev/verify
make dist/update/dev/smoke
make dist/image-update/dev/smoke
make dist/install/dev/verified
make dist/installed/smoke
```

Release targets must use the same review gate as development targets before compile and runtime smoke.
Troubleshooting Tools must verify staged command wrappers and bundled CLIs. Update apply smoke must stay
guarded because it can modify an installed runtime.

## Prevention

Keep these meanings separate in Make targets and devtools usecases:

- review gate: source, contract, and unit-level checks
- compile: build package, DMG, or bundle artifacts
- artifact verify: inspect generated artifact layout and checksums
- static smoke: verify bundle/application contracts without applying them
- apply smoke: explicitly guarded runtime mutation
- installed smoke: inspect installed files, launchd state, and HTTP health

Do not let a build target imply a later phase passed. If a phase is not implemented, the target must
fail explicitly instead of returning success.
