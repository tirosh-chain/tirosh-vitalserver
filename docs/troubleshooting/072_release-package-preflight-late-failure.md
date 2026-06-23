# Release Package Build Late Failure Before Preflight

> ID: TS-072  
> Category: Packaging / Local development  
> Owner: devtools release package preflight  
> Status: implemented

## Symptoms

`make dist/dmg/dev`, `make dist/dmg/dev/compile`, `release-pkg`, or `release-dmg` fails after spending time in earlier build stages such as Swift build, app bundle staging, Docker image bundle creation, `pkgbuild`, or `hdiutil create`.

Common late failures include:

```text
error: missing package input: <rootfs-base-or-golden-runtime-file>
docker pull ... manifest unknown
DMG output is currently attached; detach it before rebuilding
missing required tool: docker
```

## Impact

The developer only learns about a missing build input, unavailable Docker image, mounted DMG, or missing local tool after unrelated expensive work has already run. This makes the failed stage look like the cause even when the actual blocker was a package input contract problem.

## Cause

Release packaging previously validated several Host-owned inputs at the point where the adapter needed them. That made the build order decide when failures appeared. Package inputs such as golden runtime artifacts, Docker image manifests, local toolchain availability, and DMG attachment state are not domain state to infer from a failed command.

## Checks

Run the release command directly and inspect the preflight section:

```sh
uv run vitalserver-devtools --config config/vm-build.toml release-dmg \
  --release-file apps/vitalserver-macos-runtime/release-dev.json \
  --rootfs-base .tmp/vitalserver-vm-golden/rootfs-base.raw.gz \
  --golden-runtime-dir .tmp/vitalserver-vm-golden/runtime \
  --proxy-port 80
```

The command should fail before Swift build or package staging if a required input is missing or unavailable.

## Actions

`release-pkg` and `release-dmg` now run package preflight before preparing the package context. The preflight checks:

- required tools: `swift`, `codesign`, `pkgbuild`, `docker`, and `hdiutil` for DMG builds
- required package inputs: rootfs base, golden kernel `Image`, and `initrd.img`
- configured Dockerfile paths for locally built images
- configured Docker pull image manifest availability and requested platform support
- DMG output attachment state before `hdiutil create`

## Prevention

- Host-owned package inputs must be checked before expensive compile or packaging stages.
- Missing, invalid, unavailable, and blocked states must stay distinct in preflight output.
- Toolchain and external registry failures must not be hidden as empty defaults or late adapter failures.

## Related Cases

- TS-064
- TS-071

## Follow-up

- 2026-06-13: Added release package preflight for package inputs, toolchain, Docker manifests, and DMG attachment state before package context preparation.
