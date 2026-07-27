# Update bootstrap journal requires explicit recovery

> ID: TS-192
> Category: Update / Host runtime / Recovery
> Owner: stable updater bootstrap workflow
> Status: active

## Symptoms

A stable bootstrap apply is interrupted by process termination, host restart,
or power loss. A later apply of the same update ID is rejected because a
journal already exists. The persisted state is `admitted`,
`handoff-pending`, or `running`.

Settlement can also fail with an explicit missing, unreadable, invalid, or
digest-mismatched completion receipt/report error.

## Impact

The Host does not guess whether the updater ran. In particular, it never
relaunches a `running` journal because the updater may already have changed the
product. Installed release state is not advanced without a correlated receipt
and a report file whose SHA-256 matches that receipt.

## Cause

The bootstrap journal is committed before external effects:

- `admitted` means authentication succeeded but immutable staging was not
  durably recorded.
- `handoff-pending` means immutable staging is recorded and updater dispatch
  has not started.
- `running` is committed before invocation write and process launch. After an
  interruption, Host cannot infer whether execution started or completed.

These states therefore require different recovery actions. A generic retry
would turn missing evidence into guessed state.

## Checks

Inspect the Host-owned SQLite journal directly:

```sh
sudo sqlite3 \
  "/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite" \
  "select journal_id,journal_revision,state,updated_at from update_bootstrap_journals order by updated_at desc;"
```

Record the exact journal ID and state. Do not choose a command from log text or
from the presence of staging files alone.

## Actions

For `handoff-pending`, resume the verified staged handoff:

```sh
sudo /usr/local/bin/vitalserver-vm runtime \
  resume-update-bootstrap-handoff <update-id>
```

This command strict-validates the staged three-file closure and publisher
signature again before changing the journal to `running`.

For `running`, first allow the updater process to finish if it is still active,
then settle only its existing completion evidence:

```sh
sudo /usr/local/bin/vitalserver-vm runtime \
  settle-update-bootstrap-handoff <update-id>
```

This command does not launch the updater. A missing receipt/report or report
digest mismatch leaves the journal `running` so evidence can be repaired or
investigated without inventing a terminal result.

When an operator has evidence that a non-terminal operation must be abandoned,
record that decision and its reason explicitly:

```sh
sudo /usr/local/bin/vitalserver-vm runtime \
  fail-update-bootstrap <update-id> \
  --reason "operator-confirmed reason"
```

An `admitted` journal cannot be resumed because it does not own a staged
bundle. Mark it failed and publish a newly identified bootstrap envelope if a
new attempt is required. Do not delete or rewrite the SQLite row to reuse its
identity.

## Prevention

Keep the state-before-effect ordering and optimistic journal revisions.
Recovery commands must remain state-specific, require an exact ID, revalidate
any code that will execute, and verify terminal evidence before installed
release state is changed.

## Related Cases

- `TS-188`: integrity is not publisher authentication.
- `TS-191`: installed release packages require an explicit publisher trust
  store.

## Follow-up

- 2026-07-27: added explicit pending resume, running settlement, non-terminal
  failure, and completion report digest verification.
