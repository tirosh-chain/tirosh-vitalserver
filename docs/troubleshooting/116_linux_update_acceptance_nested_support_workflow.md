# Linux update rolls back when installed acceptance starts support export

> ID: TS-116  
> Category: Packaging / Update  
> Owner: Linux installed acceptance workflow  
> Status: resolved

## Symptoms

A trusted Linux update reaches installed acceptance, then fails at
`platform-support-export` with:

```text
HTTP contract read failed path=/platform/support-exports: HTTP Error 409: Conflict
```

The installer exits nonzero and the update transaction restores the previous
release even though the new support exporter itself is valid.

## Impact

The update is correctly reported as failed and Runtime data is preserved, but
an otherwise valid release cannot be installed through the Platform update
workflow. Direct offline installation can still pass.

## Cause

The installed acceptance tried to schedule a durable `support-export` while
the enclosing durable `update-apply` operation was still `running`. The
Platform Agent correctly permits only one active Platform workflow, so it
returned conflict instead of overwriting the update owner.

## Checks

Read both explicit proofs:

```sh
sudo cat /var/lib/vitalserver/run/platform-workflow.json
sudo cat /var/lib/vitalserver/proof/linux-native-acceptance.json
```

The workflow should identify the failed `update-apply`; the acceptance proof
should name `platform-support-export` and HTTP 409. Do not treat the conflict as
a failed collector or remove the active-operation guard.

## Actions

Apply a release whose updater invokes the installer with the explicit
`capability-only` support-export acceptance mode. Direct/initial installation
continues to execute and verify a real managed artifact. After the enclosing
update completes, run the normal installed acceptance separately when an
artifact proof for that exact installed release is required.

## Prevention

`update-linux.py` passes
`--acceptance-support-export-mode capability-only` to `install.sh`.
`acceptance-linux.py` still requires `canExportLogs=true`, but does not create a
second durable operation in that mode. The default remains `execute`, so a
direct install cannot publish installation state without a real support
artifact proof.

For the first transition from an older installed updater that cannot pass the
new argument, acceptance reads `/platform/workflows/current`. It defers only
when that owner explicitly identifies the enclosing `update-apply` in
`running`; another active kind remains a failure. Missing, invalid, or failed
owner state is not converted into an active update.

Package tests pin both the explicit mode and the owner-qualified first-transition
case. Process ancestry, filenames, and logs are not used to infer an active
workflow.

## Operational Notes

On 2026-07-11 workflow `workflow-1d0e690de096a6d23dca23b87d5a0c1f`
reproduced the conflict on Ubuntu 24.04 x86_64. The failed 0.2.7 release was
removed and `current` plus `install.json` returned to 0.2.6.

## Related Cases

- TS-112
- TS-115

## Follow-up

- 2026-07-11: Reproduced with trusted Platform API update and fixed with an explicit non-nested acceptance mode.
- 2026-07-11: 0.2.9 trusted workflow `workflow-bb613dbfe95b3cbddc1504a6bef615ca` passed the older-updater transition; post-update full acceptance run `0deaed7b-113c-46cc-be21-bb539dee0000` then created and verified a support artifact.
