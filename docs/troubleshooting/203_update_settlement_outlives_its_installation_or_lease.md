# TS-203: Update settlement outlives its installation or operation lease

## Symptom

An updater admitted before a reinstall, or a process that no longer owns the
active update operation, can attempt to publish a successful journal and
installed release after its authority has changed.

The update ID and journal revision may still be valid while the installed
product singleton now represents another installation.

## Cause

The update journal previously carried an operation identifier, but it did not
carry the Host-owned installation identity and revision observed at admission.
Settlement compared the journal and installed release revisions without
atomically proving that:

- the same update operation lease is still active,
- the lease targets the same installation identity and revision, and
- the installed product singleton still has that identity and revision.

These independent revisions cannot substitute for one another.

## Fix direction

The stable update lease and journal now carry
`targetInstallationId` and `expectedInstallationRevision`. Admission reads the
installed product release explicitly and copies that fence into the journal.
The update journal operation ID is the active lease operation ID.

SQLite settlement uses one immediate transaction to validate the active lease
owner, lease installation fence, persisted journal revision, and current
installed release fence before advancing both the journal and installed release.
Any mismatch fails without changing either aggregate.

Schema v11 adds nullable installation-fence columns to the operation lease
table. Existing schema-v1 lease rows migrate explicitly as unbound legacy
leases; they cannot satisfy stable update settlement.

## Prevention

Treat installation identity, installation revision, operation lease ownership,
and aggregate revision as separate mandatory compare-and-swap inputs. Never
reconstruct one from another, and never allow a missing legacy fence to mean
the current installation.
