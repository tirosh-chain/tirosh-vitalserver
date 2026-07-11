# Linux installation interruption reports or leaves partial state

> ID: TS-112  
> Category: Packaging / Update  
> Owner: Linux installer transaction  
> Status: resolved

## Symptoms

An interrupted Linux install or update can appear successful to its caller, or
a failed first installation can leave generated configuration, systemd units,
or a release directory that blocks a clean retry.

## Impact

The install owner can disagree with filesystem and service state. A later
retry may consume partial configuration as if it were pre-existing user-owned
state, which makes rollback and data-preservation conclusions unreliable.

## Cause

Signal exit status was not mapped explicitly, and rollback tracked generated
configuration too coarsely. Cleanup therefore could not distinguish files and
units created by the current transaction from state that existed beforehand.

## Checks

Check the transient unit's `Result` and `ExecMainStatus`, the `current` symlink,
the target release directory, `/var/lib/vitalserver/install.json`, generated
files under `/etc/vitalserver`, and the three VitalServer systemd services.

## Actions

Use a bundle containing the transactional installer fix. After a failed older
install, verify and remove only the partial state owned by that failed run;
preserve `/var/lib/vitalserver/data` and any explicit pre-existing owner files.

## Prevention

The installer maps HUP, INT, and TERM to 129, 130, and 143, respectively. It
tracks each created configuration owner separately, removes only a release
created by the active transaction, and removes first-install units and
ephemeral run/proof state when that first installation fails. The install owner
is published only after installed acceptance passes. Same-version reapplication
preserves the existing owner's earlier `previousRelease`; it rejects an invalid
or self-referential rollback lineage instead of silently replacing it.
When a new Agent adds required delivery fields, the installer performs an
explicit schema-1 migration, verifies the separate API token owner, and keeps a
transaction backup so failed acceptance restores the previous configuration
before restarting the previous release's services.

## Operational Notes

On 2026-07-11 a TERM sent to the 0.2.2 installer main process produced status
143, restored `current` to `releases/0.2.1`, removed release 0.2.2, and preserved
all nine owner hashes plus Vital Files, Postgres, and Redis sentinels.

## Related Cases

- TS-012
- TS-037

## Follow-up

- 2026-07-11: First-install failure cleanup and interrupted-update rollback
  were both exercised on an Ubuntu 24.04 x86_64 QEMU machine.
- 2026-07-11: A 0.2.3 update exposed missing required delivery fields in the
  0.2.1 config. Explicit migration, failure restoration, successful update,
  and same-version rollback-lineage preservation were then exercised.
