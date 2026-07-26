# Release Package Build Late Failure Before Preflight

> ID: TS-072  
> Category: Packaging / Local development  
> Owner: devtools release package preflight  
> Status: implemented

## Symptoms

`make dist/dmg/dev`, `make dist/dmg/dev/compile`, `release-pkg`, or `release-dmg` fails after spending time in earlier build stages such as Swift build, app bundle staging, `pkgbuild`, or `hdiutil create`.

Common late failures include:

```text
error: missing package input: <rootfs-base-or-golden-runtime-file>
DMG output is currently attached; detach it before rebuilding
```

Docker registry, Docker daemon, image platform, Compose image/Dockerfile/deploy-include failures belong to the earlier Guest compile phase and must be reported by `make devtools/docker/images` or the clean rootfs compile, not by package preflight.

## Impact

The developer only learns about a missing package input, mounted DMG, or missing local tool after unrelated expensive work has already run. This makes the failed stage look like the cause even when the actual blocker was a package input contract problem.

## Cause

Release packaging previously validated several Host-owned inputs at the point where the adapter needed them. That made the build order decide when failures appeared. Package inputs such as golden runtime artifacts, local packaging toolchain availability, and DMG attachment state are not domain state to infer from a failed command. Docker and Guest source are compile inputs; letting package inspect them again would make package depend on a mutable worktree rather than the compiled receipt.

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

`release-pkg` and `release-dmg` run full package preflight before preparing the package context. The preflight checks:

- required tools: `swift`, `codesign`, `pkgbuild`, and `hdiutil` for DMG builds
- required package inputs: rootfs base receipt, compiled Guest deploy material, golden kernel `Image`, and `initrd.img`
- DMG output attachment state before `hdiutil create`

The standard Make path also runs a separate package-environment preflight before
PWA, Docker, and rootfs compilation. It checks only Host tools and output state;
it deliberately leaves rootfs receipt and compiled Guest deploy checks to the
post-compile package preflight that owns those artifacts.

`make devtools/docker/images` owns the Guest compile contract. Before it invokes Docker, it verifies the Compose product service list, configured image names, build Dockerfiles, and Guest deploy include coverage. Docker pull/build is then the explicit compile evidence for registry and daemon failures.

## Prevention

- Host-owned package inputs must be checked before expensive compile or packaging stages.
- Missing, invalid, unavailable, and blocked states must stay distinct in preflight output.
- Package and compile failures must stay in their owning phase; package must not recreate or reinterpret Guest compile input.

## Related Cases

- TS-064
- TS-071

## Follow-up

- 2026-06-13: Added release package preflight for package inputs, toolchain, Docker manifests, and DMG attachment state before package context preparation.
- 2026-07-12: Moved Docker/Compose validation to Guest compile. Package now consumes the rootfs receipt and compiled Guest material only.
- 2026-07-12: Added a package-environment preflight before the standard PWA and
  golden-rootfs compile path, so local Mac toolchain/output blockers fail before
  VM/Docker work.
