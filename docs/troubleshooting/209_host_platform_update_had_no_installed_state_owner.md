# TS-209: Host Platform update had no installed state owner

## Symptom

The stable update specification can name a `host-platform` artifact and effect
executor, but Helper 0.2.2 had no installed component that could authoritatively
answer:

- which Host Platform release is active,
- which installation identity and revision that release belongs to,
- which immutable candidate was staged,
- whether service reconciliation actually completed, and
- whether an apply or rollback operation reached a durable terminal state.

Using a package receipt, installed file presence, launchd state, a process exit
code, or updater logs as the answer makes recovery ambiguous. A stale updater
can also overwrite a newer reinstall unless both installation identity and
revision are fenced.

## Cause

`InstalledProductRelease` records the release after an update is settled, but
it is not the owner of Host Platform replacement. The legacy package and
artifact replacement paths perform side effects without one stable,
already-installed manager that owns the active manifest and update operation.

The old path therefore mixed four different meanings:

1. a candidate artifact exists,
2. files were copied,
3. a service command exited,
4. the target release is active.

Only the last meaning is product update success, and it must be authored by the
installation owner.

## Fix

The Host Platform Installation Manager introduces these explicit boundaries:

- `HostPlatformInstallationManifest` owns installation identity, monotonically
  increasing installation revision, active release identity/version/SHA-256,
  rollback release, and the operation that activated it.
- `HostPlatformInstallationOperation` persists the strict
  `requested -> candidate-staged -> services-reconciled -> succeeded` state
  machine. Failure is terminal and never advances the active manifest.
- `SQLiteHostPlatformInstallationRepository` keeps the active manifest,
  active-operation lease, and operation journal in one `BEGIN IMMEDIATE`
  transaction. Every write uses operation and installation CAS.
- `ImmutableHostPlatformCandidateStager` verifies the declared SHA-256 before
  and after copy and refuses to overwrite an existing release slot.
- `HostPlatformServiceReconciling` is an explicit effect port.
  `ReceiptWritingHostPlatformServiceReconciler` requires a correlated,
  owner-written receipt. Process exit is diagnostic context only and cannot
  become success.
- `ManageHostPlatformInstallationUseCase` resumes an existing operation from
  its persisted state, so a caller restart does not repeat completed staging.

The manager intentionally does not inspect package receipts, launchd, logs, or
the filesystem to manufacture active state. The initial manifest must be
registered explicitly by installation composition.

## Packaging integration

Helper 0.2.2 fresh packaging now establishes the same installation contract
that later updates consume:

- immutable Host files are installed under
  `host-platform/releases/<release-id>/release`;
- `host-platform/current` is an explicit symlink to that release root;
- `/Applications/VitalServer Helper.app`, the compatibility CLI links, and
  replaceable launchd definitions resolve through `current`;
- the installation manager, layer effect executor, and handoff supervisor stay
  at fixed paths outside the replaceable release;
- postinstall initializes the installation SQLite database from the packaged
  `HostPlatformInstallationManifest`; and
- clean uninstall removes the product root, stable links, stable executables,
  and launchd definitions through the uninstall contract.

If postinstall reports that `current`, the Helper app link, the initial
manifest, or the manager is missing, the package payload is incomplete. Do not
reconstruct the active release from files or a package receipt. Rebuild the
package with all four explicit inputs and inspect the preserved postinstall
failure log.

## Prevention

- Keep the manager and its SQLite database outside release-owned slots.
- Never reconstruct the active manifest from files, receipts, processes,
  launchd, or logs.
- Require exact installation identity/revision and operation revision on every
  state change.
- Never treat a service process exit as reconciliation success; require a
  correlated receipt with target release identity and digest.
- Activate the manifest only in the same transaction that settles the
  operation as succeeded.
