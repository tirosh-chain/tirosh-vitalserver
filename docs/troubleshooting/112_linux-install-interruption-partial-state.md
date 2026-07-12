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
or self-referential rollback lineage instead of silently replacing it. The
root-owned `/etc/vitalserver/install-transaction.json` records an unfinished
intent, while `/etc/vitalserver/release-complete/<version>.json` is published
only after the release-path Guest Tools install completes. Therefore an
uninterrupted-looking `release.json` cannot make a partial same-version release
eligible for activation. A retry needs the matching transaction, or an explicit
migration from a matching root-owned installed owner and acceptance proof.
When rollback cannot restore the previous systemd units, it retains the
legacy-unit migration snapshot so a later recovery still has an explicit source.
Any invocation that resumes a matching transaction preserves its current link,
install owner, mutable configuration and units, candidate release, completion
receipt, and transaction if it later fails. It reports
`rollbackState=preserved-for-retry` rather than guessing that the live state
still belongs to the transaction's earlier release. Retry the same verified
bundle; do not remove those owners as routine cleanup. If that earlier release
uses a legacy systemd-unit snapshot, the resumed installer validates the
root-owned complete snapshot as the immutable previous-release source but does
not compare it with live units that may already belong to the candidate. A
missing legacy snapshot is an explicit preserved-for-retry failure; it is never
created by copying those candidate units. Before trusting or
executing a release, the installer also verifies that `/opt/vitalserver` and
its `releases` ancestor are root-owned, non-symlink, and not group- or
world-writable, and validates `/var/lib/vitalserver` before writing install
owners there. The final install-owner publish is a no-rollback boundary: after
the temporary owner has been synced, the installer disarms rollback traps before
its atomic rename. A rename or owner-directory durability failure therefore
keeps the transaction and reports `rollbackState=preserved-for-retry` for a
same-bundle retry, instead of restoring the previous release around a possibly
published new owner. The installer also syncs the parent directory after a new
release publish, each `current` link swap (including rollback), and a legacy
systemd-unit snapshot publish before any later durable owner or transaction
stage. If the post-commit transaction removal itself cannot be durably synced,
the installer reports the owner as published and the transaction cleanup as
durability-unknown; it does not falsely claim rollback or infer which side of
that deletion survives a power loss. When a new Agent adds required delivery
fields, the installer performs an explicit schema-1 migration, verifies the
separate API token owner, and keeps a transaction backup so failed acceptance
restores the previous configuration before restarting the previous release's
services.

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
