# Host Release Restarts launchd Before the VM Stops

> ID: TS-224
> Category: Update / Host platform reconciliation
> Owner: macOS runtime
> Status: active

## Symptoms

Container and Guest Runtime layers apply successfully, but the Host Platform
layer fails while bootstrapping the VM service with launchctl status 5. The
reported compensation can then fail while bootstrapping Platform Agent with
the same status. Afterward, Platform Agent may be the only loaded replaceable
service.

## Cause

`launchctl bootout` accepts an unload request before the service process has
finished terminating. The VM process can remain in `SIGTERM` state until its
launchd exit timeout expires. Host release reconciliation immediately
bootstrapped the target service with the same label instead of waiting for
launchd to report that the previous service was explicitly not loaded.

When a later target service failed, reconciliation also attempted to bootstrap
the previous release without first unloading target services that had already
started. The resulting duplicate Platform Agent bootstrap hid the primary
failure and interrupted compensation.

The service command adapter discarded launchctl stdout and stderr, leaving
only status 5 in the durable failure receipt.

## Fix Direction

- After every accepted `bootout`, poll launchd's owned service state until it
  explicitly reports `notLoaded`; preserve read, permission, unknown, and
  timeout outcomes as failures.
- Give the VM its declared long stop window instead of treating an accepted
  unload request as completed termination.
- Track each target service that bootstraps successfully. On failure, unload
  and settle only those target services before restoring the previous release.
- Track previous services for which unload was requested so partial quiesce can
  restore exactly that set in manifest start order.
- Capture launchctl stderr or stdout in the typed service command failure.

## Prevention

A service manager command receipt and the resulting service state are separate
proofs. Release activation must not reuse a launchd label until the state owner
reports that the previous service is no longer loaded. Compensation must be
based on recorded completed/requested effects, not on an assumed all-or-nothing
service transition.

## Related Cases

- [TS-192: Update bootstrap journal requires explicit recovery](192_update_bootstrap_journal_requires_explicit_recovery.md)
- [TS-223: Host candidate receipt exceeds the identifier contract](223_host_candidate_receipt_exceeds_identifier_contract.md)
