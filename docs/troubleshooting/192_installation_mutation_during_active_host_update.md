# Installation or removal starts during an active Host update

> ID: TS-192
> Category: Update / Packaging / Uninstall
> Owner: Host Installation Manager and Host Agent coordination boundary
> Status: active

## Symptoms

- A same-release reinstall, repair, or product removal is requested while a
  Host update is active.
- The installer reports
  `active-host-update-blocks-installation` or
  `active-host-update-blocks-removal`.
- If the Host-local administration endpoint cannot be read, the operation is
  blocked instead of being treated as though no update exists.

## Impact

- The requested package mutation does not begin, so C50/C54 journals and
  service or filesystem effects are not created by the blocked operation.
- The operator must first settle the active update or repair the Host-local
  administration contract.
- This guard reduces conflicting mutation, but does not yet prove atomic
  exclusion across the idle-read-to-effect interval.

## Cause

Update and installation/removal mutate overlapping Host services, activation
references, immutable releases, and package state. C80 is the Host Agent-owned
read contract that states whether the current installation has no update owner
or identifies its one active owner. Missing, failed, invalid, unavailable, or
identity-mismatched C80 state cannot prove that mutation is safe.

## Checks

1. Read the C52 Host-local administration descriptor installed for the current
   release.
2. Call `GET /v1/platform/update-operation-ownership` over that exact Unix
   socket or Windows named pipe.
3. Confirm the result is `available`, names the current installation identity
   and revision, and reports `state=idle`.
4. If it reports `active`, inspect the named update ID and journal revision
   before attempting recovery or interruption.

## Actions

- For an active owner, allow the update to finish or use the defined
  interruption request, process-tree termination, and confirmation workflow.
- For a missing or failed endpoint, repair Host Agent/C52 availability; do not
  bypass the read by assuming idle.
- Retry reinstall, repair, or removal only after the exact current
  installation reports `available/idle`.
- A C49-proven clean Host can perform fresh install without C80 because no
  installed Host Agent exists to provide it.

## Prevention

- Package scripts always pass the release-declared C52 descriptor and an
  explicit timeout to Host Installation Manager.
- Package verification rejects a macOS package whose preinstall/postinstall
  handoff omits those inputs.
- Installation Manager checks C80 before persisting C50/C54 state or executing
  effects and preserves every non-idle read meaning.

## Operational Notes

The current C80 check is a fail-closed admission guard. A later atomic Host
lifecycle claim must close the remaining time-of-check/time-of-use race between
an idle read and update admission. Until then, do not describe this check as a
cross-process lock.

## Related Cases

- [TS-042](042_host-install-uninstall-state-contract-gap.md)
- [TS-155](155_host_installation_transaction_strands_services_after_payload_failure.md)

## Follow-up

- 2026-07-27: Added C80 admission checks for same-release reinstall/repair and
  removal, plus explicit package inputs and package verification.
