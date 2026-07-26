# 101 Docker build context canceled after interrupt

> ID: TS-101
> Category: Packaging / Local development / Docker image bundle
> Owner: devtools
> Status: implemented

## Symptoms

DMG/package build stops while building Docker images and reports:

```text
ERROR: failed to build: failed to solve: Canceled: context canceled
KeyboardInterrupt
make[1]: *** [internal/vm/dmg] Interrupt: 2
```

The Docker progress usually shows the build context being transferred when it
stops.

## Cause

This is an interrupt, not proof that the Dockerfile failed. `KeyboardInterrupt`
means the devtools Python process received an interrupt while waiting for
`docker buildx build`. Docker then cancels BuildKit context transfer and prints
`context canceled`.

## Fix Direction

Do not debug the Dockerfile first from this symptom alone. Re-run the same build
without interrupting it, or build the reported Dockerfile directly with
`docker buildx build --progress=plain` to prove whether the Dockerfile has a
real failure.

Devtools catches `KeyboardInterrupt` and exits with code `130` with an explicit
message so the cancellation is not reported as a Python traceback.

## Prevention

Keep interrupt, dependency failure, Dockerfile failure, and context-transfer
failure separate in diagnostics. Do not convert a user interrupt into a package
compile failure.
