# Installed Bootstrap Missing Rootfs Input Metadata

> ID: TS-073
> Category: Packaging / Install / Guest bootstrap
> Owner: macOS package staging / guest bootstrap contract
> Status: implemented

## Symptom

Fresh install completes provisioning, but the runtime becomes `critical` shortly after first start. The helper message can report:

```text
watchdog cannot recover missing installed artifacts
```

Older diagnostics/status projections can show `vm-runtime-state-missing`, stale
VM lifecycle, and failed host proxy HTTP while the VM launchd service is still
running. Current Runtime Control status must come from explicit owner reads
rather than treating `runtime-status.json` as the failure owner. Older builds
could also report missing container observation, but v2 keeps container
observation as diagnostics evidence instead of a typed Host failure reason.

After the metadata is present, the next visible failure can be Docker image load failing with:

```text
stat /mnt/runtime/docker/tmp: no such file or directory
```

Another related failure can appear after `dockerDataRoot/tmp` exists:

```text
symlink ../<layer>/diff /mnt/runtime/docker/overlay2/l/<link>: no such file or directory
```

## Cause

Guest bootstrap failed before starting runtime services because installed deploy artifacts did not include:

```text
/mnt/tirosh/deploy/build-metadata/rootfs-input.json
```

`tirosh-vitalserver-runtime-data-prepare` reads that file as the explicit runtime data disk contract. The golden rootfs staging path created the metadata, but macOS package staging only copied guest deploy files and did not write the same Host-owned contract into the installed deploy directory.

The installed bootstrap path also applies the runtime data disk contract before loading Docker image bundles. Creating only `dockerDataRoot` is not enough for that path; Docker image load can require the `dockerDataRoot/tmp` work directory before containers ever start.

Bootstrap must also not start Docker consumers before the runtime data contract is applied. Starting container log collection, guest observability, or any service with `Requires=docker.service` before `tirosh-vitalserver-runtime-data-prepare` can activate Docker with an unprepared or partially configured data-root. Later `docker load` then fails inside overlay2 even though the runtime data disk itself was freshly created.

## Fix Direction

Package staging now writes `deploy/build-metadata/rootfs-input.json` from explicit build inputs: Ubuntu source, apt snapshot, runtime data disk contract, and Docker image platform. Guest bootstrap continues to fail on missing metadata instead of inferring runtime data state.

Runtime data preparation now creates the Docker data-root work directory explicitly:

```text
<dockerDataRoot>/tmp
```

Golden rootfs smoke creates the same directory so compile validation covers the contract shape used by installed bootstrap.

Guest bootstrap is now an explicit guest-tools workflow. `bootstrap.sh` only mounts the deploy share, installs the guest-tools wheel, and execs `tirosh-vitalserver-bootstrap`; operation order is owned by `GuestBootstrapWorkflow`. The workflow stays in the application layer and talks through explicit bootstrap operations. Concrete systemd, Docker, mount, filesystem, curl, and JSON writes live in `infrastructure/bootstrap_operations.py`.

The workflow enables background services without starting them before runtime data preparation. It starts guest background services only after Docker is configured on the runtime data disk, and starts container log collection only after the compose service has started. Runtime data preparation also stops Docker and containerd before applying the data-root contract so accidental earlier activation is not hidden.

## Prevention Principle

- Host packaging must provide every Guest bootstrap contract explicitly.
- A contract required by both golden rootfs and installed bootstrap must be staged through a shared typed plan, not only by the local golden-rootfs command path.
- Missing runtime data metadata is a packaging failure, not a Guest default.
- Compile must prove the installed bootstrap contracts it claims to protect. Golden rootfs success alone is not proof that installed package deploy and first-boot runtime data preparation are valid.
- No Guest service that can activate Docker may start before the runtime data contract has been mounted, configured, and made visible to Docker.
- `bootstrap.sh` must stay a thin entrypoint. Guest bootstrap states, guards, effects, and terminal result writes belong in `GuestBootstrapWorkflow`, where they can be tested as operation order.
- Application bootstrap code must not import infrastructure modules or construct systemd/Docker commands directly; those are adapter/infrastructure responsibilities behind explicit operations.
