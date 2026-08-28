# Host Platform Reconciliation Is Now a Durable, Resumable Lifecycle

> ID: TS-226
> Category: Update / Host platform reconciliation
> Owner: macOS runtime
> Status: active

## Symptoms

Host Platform layer reconciliation used to run quiesce, publish, activate, and
start as one in-memory sequence. A crash after any irreversible effect left no
durable record of what had completed, so retry could not resume idempotently.
It also classified launchctl results by matching stderr text, so the same exit
code could be read differently across locales, and `bootstrap` exit 0 was
treated as a running/healthy proof instead of re-reading a loaded proof.

## Impact

- A crash between the `current` symlink switch and the receipt/DB settle could
  leave the target activated with no durable phase to resume from.
- A target service that bootstrapped and then immediately unloaded could be
  reported as a successful start.
- `bootout` on an already-not-loaded service (exit 113/3) was treated as a
  failure instead of an idempotent desired outcome.
- Large `tar`/`launchctl` output could deadlock the child because stdout/stderr
  were drained only after `waitUntilExit`.

## Cause

`MacOSHostPlatformReleaseServiceReconciler.reconcileServices` performed every
effect in one call and compensated from in-memory lists, so neither the phase
nor the completed effects were durable. `RuntimeLaunchdServiceStateMapper`
classified launchd state by matching stderr substrings (`could not find
service`, `not found`, `permission denied`). The stager and reconciler read
child stdout/stderr sequentially after `waitUntilExit`, which blocks once a
pipe buffer fills.

`ReceiptWritingHostPlatformServiceReconciler` wrote a `request.json` and
spawned an external executable to produce a `receipt.json`, but no composition
used it: `HostInstallationManager` calls `MacOSHostPlatformReleaseServiceReconciler`
in-process, and the process boundary already lives at
`HostPlatformLayerEffectExecutor`, which spawns the whole manager. The
reconciler-level subprocess wrapper was redundant dead code.

## Fix Direction

- Replace the coarse operation states with a durable phase machine
  (`requested`, `prepared`, `previous-quiesced`, `interfaces-published`,
  `target-activated`, `target-services-loaded`, `completed`, `compensating`,
  `compensated`, `failed`) whose shape is owned by
  `HostPlatformInstallationPhase`.
- Record a durable reconciliation journal entry before/after each irreversible
  effect via CAS on `operationRevision`. Each entry carries the effect, the
  reached phase, the resolved `current` target, and typed launchd observations.
- Drive resume through a pure `HostPlatformInstallationPolicy.nextStep` that
  compares the durable phase to the `current` symlink observation and never
  advances from missing/failed/unknown state.
- Execute one effect per adapter call; `quiesce`, `publish`, `activate`, and
  `load` are each idempotent (`bootout` 113/3 is `alreadyNotLoaded`; `load`
  skips already-loaded services; `activate` no-ops when already target).
- Classify launchd results by exit code only (locale-independent): `0` loaded/
  accepted; `3`/`113` not-loaded/already-not-loaded; `1`/`13` permission-denied;
  otherwise read/command failure. `bootstrap` exit 0 is only load-request
  acceptance; the effect re-reads `print` and requires `loaded`.
- Re-prove the manifest-declared exact closure (no-extra, no-missing) at
  candidate staging, before publish, and on the published application.
- Make `stageCandidate` idempotent so a crash after the move but before the
  `.prepared` journal save resumes: the verified source archive is re-extracted
  to a temporary and its exact closure (every regular-file relative path, byte
  digest, and executable bit) is compared to the existing slot's closure. The
  slot is only reused on a complete match, so a same-id/version slot whose
  payload differs from `command.targetRelease.sha256` is rejected, never
  inferred from mere existence. Missing/invalid/mismatch/read failure stay
  distinct. A leftover temporary extraction directory is removed by explicit
  policy before staging or slot verification and is cleaned up on both success
  and failure.
- Reuse an already-present rollback target slot through the same explicit
  proof, so a rollback whose target release slot already exists does not fail
  deterministically at staging.
- Terminalize a permanent `.prepared` failure (loadManifest/verifyTopology,
  before any irreversible effect) as a durable `.failed` so the active
  operation cannot stay stuck. Irreversible phases never terminalize here;
  they remain owned by the compensation path.
- Preserve a `recordCompensated` persistence failure after a successful
  compensation effect instead of misrecording it as "compensation failed": the
  real persistence error propagates and the durable `.compensating` state lets
  resume retry idempotently. If the compensation effect itself fails and
  recording its terminal failure also hits a persistence failure, both errors
  are preserved in an explicit `HostPlatformCompensationPersistenceFailure`
  instead of being hidden, and the `.compensating` state remains for retry.
- Record completed settlement with an explicit settle time, so the settle
  journal `observedAt`, the completed operation `updatedAt`, and the manifest
  `activatedAt` all carry the same settlement instant instead of reusing the
  last effect's timestamp.
- Drain child stdout/stderr concurrently with the shared
  `RuntimeProcessOutputCollector` so large output cannot deadlock.
- Delete `ReceiptWritingHostPlatformServiceReconciler` as unused duplicate code.

## Prevention

A service-manager command receipt and the resulting service state are separate
proofs, and every irreversible effect must leave a durable phase plus typed
Host-owned observations. Compensation is itself durable (`compensating` ->
`compensated` -> `failed`) so a crash mid-compensation resumes idempotently.
The model is documented in `docs/runtime/macos/architecture.md` §7-4.

## Related Cases

- [TS-224: Host release restarts launchd before the VM stops](224_host_release_restarts_launchd_before_vm_stops.md)
- [TS-223: Host candidate receipt exceeds the identifier contract](223_host_candidate_receipt_exceeds_identifier_contract.md)
- [TS-218: Applications Helper symlink is not registered](218_applications-helper-symlink-not-registered.md)
- [TS-227: prove-update-bootstrap rejects persisted layer evidence](227_prove_update_bootstrap_rejects_persisted_layer_evidence.md)

## Evidence

`prove-update-bootstrap` does not infer Host Platform phase from the `current`
symlink or from logs. It reads the signed Host Platform effect configuration
from the staged update (digest-bound) and then reads the Host Platform SQLite
journal at `manager.databasePath`:

```text
/Library/Application Support/VitalServerHelper/update-manager/state.sqlite
```

The apply operation id is `<update-id>.host-platform.apply`. Proof correlates
installation id, expected revision, candidate/target release identity, and
artifact SHA-256, then requires a terminal phase:

- `--expect succeeded` → phase `completed`, and the active installation
  must be this operation's target release (id/version/digest/slot) at
  `expectedInstallationRevision + 1`
- `--expect failed-rolled-back` → phase `failed` or `compensated` as distinct
  terminals; the active installation must still be `operation.previousRelease`
  (id/version/digest/slot) at `expectedInstallationRevision`, and
  `activationOperationId` must not be this operation. This holds for
  requested/prepared failure and for compensated failure because failed
  settlement does not advance the SQLite installation.

Missing, read-failed, identity mismatch, and non-terminal phases stay
distinct. Staging under `update-bootstrap/<update-id>/` must still be present
at proof time because the configuration path and digest come from that
closure.

## Follow-up

- `2026-08-14`: Durable reconciliation introduced; TS-224 superseded by this model.
- `2026-08-14`: `stageCandidate` made idempotent (re-proof of an existing slot
  plus explicit temporary-orphan removal), rollback target slot reuse, `.prepared`
  pre-effect terminalization, compensation persistence-failure preservation,
  and explicit settle time.
- `2026-08-14`: `resumeStagedCandidate` now binds an existing slot's exact
  closure to the re-extracted signed source archive (regular-file relative
  path, byte digest, and executable bit) instead of accepting an id/version plus
  self-declared digest match. Source-archive identity mismatch is `manifestInvalid`
  while destination identity/closure mismatch is `stagedSlotMismatch`. Temporary
  cleanup failures are typed on the success path (`temporaryCleanupFailed`) and
  the failure path (`temporaryCleanupAfterFailureFailed`, which preserves both
  the original operation error and the cleanup error).
