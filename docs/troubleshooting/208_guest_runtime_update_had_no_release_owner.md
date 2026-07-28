# Guest Runtime update had no immutable release owner

> ID: TS-208
> Category: Update / Guest state ownership
> Owner: Guest Runtime Release Manager
> Status: resolved at contract and state-owner boundary

## Symptom

- Host update code replaces files in a shared Guest deploy directory and then
  asks Guest activation to restart services.
- An activation process can exit successfully without proving which Guest
  Runtime release is active.
- A stale update or rollback request cannot state which active release it
  expected before mutation.
- Release archive loading, active-release switching, and terminal operation
  evidence are not owned by one Guest component.

## Cause

The previous update boundary accepted only a product version and request ID.
The Host replaced Guest files before making that request, so the component
that owned the state did not own the mutation. Active release identity was
therefore inferred from files, process completion, or service behavior.

An archive path or a successful process exit is observation data. Neither is
an authoritative active-release state.

## Fix direction

Guest Control now provides a dedicated Guest Runtime Release Manager:

- each release has an immutable identity, Guest-owned archive reference, and
  canonical SHA-256 digest;
- Guest SQLite owns the explicit active release;
- active reads return `available` with the complete release or `unavailable`
  with a typed failure;
- apply and rollback require `expectedActiveIdentity` and a complete target;
- acceptance performs atomic compare-and-swap and persists `pending`;
- durable operations distinguish `pending`, `running`, `succeeded`, `failed`,
  and `unavailable`;
- only the valid `running -> succeeded` owner transition switches the active
  release;
- an identity cannot be rebound to another archive/digest, and an archive
  reference cannot be assigned to another identity.

The macOS Helper accesses this state through its
`RuntimeGuestReleaseGateway` application port and Guest Control HTTP adapter.
It does not replace Guest files or derive release state from logs and process
exit.

This change intentionally stops at the owner boundary. A future Guest effect
executor must verify and materialize the archive, report `running`, and then
author the terminal operation. Until that executor exists, an accepted command
remains `pending`; HTTP 202 is not update success.

Control-store schema revision `0003` adds release, active-release, and
operation tables. Migration does not guess the installed release. Installation
must explicitly provision the initial active identity, archive reference, and
digest.

## Prevention

- Guest Runtime filesystem and service state must be mutated only through the
  Guest-owned release manager.
- Require expected and target identities for every apply and rollback.
- Never infer active release from a shared directory, archive filename,
  version string, process exit, logs, or absence of errors.
- Preserve missing active state as `unavailable`; do not manufacture an
  installed default during migration.
- A layer effect receipt can report success only after the correlated
  owner-authored operation is `succeeded` and the target release is active.
