# Guest bootstrap product image rebuild fallback

> ID: TS-118
> Category: Packaging / Guest bootstrap / Guest containers
> Owner: Guest bootstrap and Host image-bundle compile boundary
> Status: resolved

## Symptoms

`make dist/dmg/dev` can pass golden rootfs compile but fail when the clean
golden disk is booted for runtime smoke. The launcher log can contain an image
tag that is not in the compiled bundle followed by an unexpected Guest-side
Compose build:

```text
Error response from daemon: No such image: vitalserver-recorder-recovery:0.1.0
docker compose ... build recorder-recovery
Guest bootstrap failed before completion.
```

Before the fix, the Host configuration and staged `compose.yaml` declared
`vitalserver-recorder-recovery:0.2.0`, while Guest bootstrap still inspected
the retired `0.1.0` tag.

## Impact

An air-gapped installation could attempt a product image build inside the
Guest after the Host had already compiled and verified its image bundle. That
made boot behavior depend on Guest source, Compose environment-file state, and
an obsolete tag instead of the delivered artifact.

## Cause

Guest bootstrap retained a `build_missing_images()` fallback with its own
hard-coded product image list. It was a second, stale source of image identity
beside the Host Docker image plan and Guest `compose.yaml` contract.

The fallback also ran before the normal Compose startup path materialized its
runtime environment contract, so an absent developer `.env` could surface as
an unrelated Compose build failure.

## Checks

For a failed runtime smoke, inspect the explicit bootstrap result and launcher
log:

```sh
jq . .tmp/vitalserver-vm-golden-runtime-smoke/data/run/bootstrap-result.json
tail -n 200 .tmp/vitalserver-vm-golden-runtime-smoke/logs/launcher.log
```

The smoke wait command now fails immediately when the result reports
`status=failed`, with `runId`, `stage=bootstrap-result`, `reasonCodes`, and
both evidence paths.

## Actions

Use the standard clean delivery gate after updating the source:

```sh
make dist/dmg/dev
```

Do not work around the failure by manually building or pulling an image inside
the Guest. If the bundle is missing an image, correct the Host image plan or
Guest Compose contract and compile a new artifact.

## Prevention

Only Host compile may build, pull, and export product images. Guest bootstrap
only loads the verified bundle and starts Compose with `--pull never
--no-build`; missing images remain explicit failures.

Guest Compose environment state is materialized from `runtime-config.json` and
`runtime-settings.json` into `/mnt/runtime/compose.env`. It must not depend on
or modify a build machine's `.env` or the immutable compiled deploy share.

The Host Docker compile contract rejects a Compose image tag that is not in the
configured image plan, and runtime boot smoke verifies the actual fresh boot.

## Related Cases

- TS-070: runtime boot proof must observe Guest bootstrap failure.
- TS-088: image/source omissions must fail at compile or bootstrap.
- TS-107: a changed Guest tool must invalidate the rootfs compile cache.
- TS-117: Host Docker export must contain the complete selected platform.

## Follow-up

- 2026-07-12: removed Guest `build_missing_images()` fallback, made runtime
  Compose fail closed for pull/build, and added immediate bootstrap failure
  evidence to runtime smoke waiting.
