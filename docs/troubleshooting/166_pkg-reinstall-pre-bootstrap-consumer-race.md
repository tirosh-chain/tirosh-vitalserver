# PKG reinstall boots old Guest consumers before replacement bootstrap

> ID: TS-166
> Category: Packaging / Guest bootstrap / Guest containers / Observability
> Owner: Guest bootstrap
> Status: active

## Symptoms

A data-preserving PKG reinstall eventually reports `Install Succeeded`, but the VM remains
`Starting`. `bootstrap-result.json` first remains `running` for several minutes and then becomes
terminal `failed` at `prepare-runtime-data`.

The current-boot Guest console contains both an OOM kill and a later Compose stop failure:

```text
Out of memory: Killed process ... (tirosh-runtime-) ... anon-rss:6953712kB
RuntimeError: systemd units did not stop: tirosh-vitalserver-compose.service=failed
```

The package receipt and deployed Guest wheel can already be correct. This is not evidence that the
PKG payload replacement failed.

An early implementation of the quiescence step also made a fresh-install runtime smoke fail with
the following explicit error because the three units do not exist in a clean rootfs yet:

```text
pre-bootstrap consumer stop request failed: ... exit=5 ... Unit ... not loaded
```

## Cause

The preserved VM disk still has enabled runtime-observation, container-log, and Compose systemd
units. They start during normal multi-user boot before cloud-init reaches `bootstrap.sh`. The old
runtime-observation executable can therefore enter the old unbounded activity migration before the
replacement Guest Tools wheel is installed. In the reproduced incident it reached approximately
6.95 GiB RSS and was OOM-killed 329 seconds after boot.

After memory is released, bootstrap installs the corrected wheel and starts runtime-data
preparation. The old stop implementation used a blocking `systemctl stop`, then sampled
`ActiveState` once. Compose exhausted its stop interval and was observed as `failed`; the console
reported `Stopped` immediately after bootstrap had already written a terminal failure. That later
log line cannot repair the failed operation result.

On a fresh install, `systemctl stop` was initially called before reading unit ownership. systemd
correctly returned `not loaded`; treating that explicit clean-rootfs state as an operational stop
failure prevented the normal first bootstrap.

## Checks

Use the package receipt and Guest-owned bootstrap result as separate proofs:

```sh
pkgutil --pkg-info ai.tirosh.vitalserver.helper
sudo cat "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap-result.json"
sudo shasum -a 256 \
  "/Library/Application Support/VitalServerHelper/vm/data/deploy/python-wheels/guest-tools/"*.whl
```

Locate the current boot marker before counting OOM evidence; old console lines are not current
state:

```sh
sudo rg -n "cloud-init.*modules:final|Out of memory: Killed process" \
  "/Library/Application Support/VitalServerHelper/logs/runtime/launchd.out.log"
```

Inspect the terminal failure stage in the bootstrap log:

```sh
sudo tail -n 200 \
  "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap.log"
```

## Fix

The Guest bootstrap entrypoint now requests a non-blocking stop of every existing Docker consumer
immediately after mounting the deploy share and before installing or validating Guest Tools. This
prevents an enabled old observation process from retaining access to preserved PostgreSQL data while
the replacement runtime is being installed. It first reads each unit's explicit `LoadState`.
`not-found` is preserved as `active_state=None` and is excluded from the stop request; every other
load state remains an existing unit that must accept the stop request and report `ActiveState`.
Property read failures, invalid values, and timeouts remain terminal errors.

Runtime-data preparation now requests non-blocking systemd stops and polls explicit `ActiveState`
until every unit is `inactive` or the 180-second operation deadline expires. A `failed` unit is not
treated as stopped. Bootstrap reads `MainPID` and `ControlPID`; only when both are explicitly zero
does it issue `systemctl reset-failed`, and it then requires a fresh `inactive` read. A failed unit
with either live PID remains a failure.

Bootstrap rewrites its running result message for each workflow step and prints step start/completion
events. Activity migration prints the completed batch number, row count, total row count, and last
snapshot ID. These are diagnostics and progress evidence, not inferred runtime state.

## Prevention

- A replacement bootstrap must quiesce enabled old consumers before installing replacement code.
- Fresh-install `not-found` and reinstall loaded-unit state must remain distinct; absence is read
  explicitly and must not be guessed from a failed stop command.
- Provider shutdown must start from an explicit consumer set and prove terminal state through
  systemd, not console ordering.
- `failed`, `deactivating`, live PID, and `inactive` are distinct states.
- Clearing a failed unit requires explicit no-process proof and an observable recovery command.
- Long bootstrap and data-migration steps must publish current-stage progress.
- Preserved-runtime acceptance must boot an image containing the previous released Guest Tools, not
  only a rootfs already containing the candidate code.

## Related Cases

- `TS-164`: Warm reinstall Compose/Docker stop deadline and final-state proof.
- `TS-165`: Unbounded activity projection migration and runtime-observation consumer ordering.

## Follow-up

- 2026-07-20: Reproduced on a preserved installation. PKG installation completed in 766 seconds and
  installed the expected Guest wheel, while Guest bootstrap later failed independently.
- 2026-07-20: Confirmed the old observation process OOM at 6.95 GiB before replacement bootstrap
  quiescence, followed by the Compose `failed`/`Stopped` race.
- 2026-07-20: Added pre-install consumer quiescence, explicit failed-unit recovery proof, bootstrap
  step reporting, migration batch diagnostics, and focused tests.
- 2026-07-20: Runtime smoke exposed fresh-rootfs `not loaded` units. Quiescence now reads `LoadState`
  first, preserves `not-found`, and sends stop only to the explicit existing-unit set.
