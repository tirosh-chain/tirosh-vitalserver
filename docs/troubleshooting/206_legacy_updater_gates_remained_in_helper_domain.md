# Legacy updater gates remained in the Helper domain

> ID: TS-206
> Category: Update / Domain contract
> Owner: Helper update contracts
> Status: resolved

## Symptom

- Helper 0.2.2 advertises the stable bootstrap path, but the Swift update
  manifest still exposes `minUpdaterVersion` and `requiresTwoPhaseUpdate`.
- Domain tests continue to describe updater-version comparison and bridge
  releases as valid product behavior.
- A future caller can accidentally reactivate the installed-updater
  compatibility model even after the public release path moves to a
  bundle-owned next updater.

## Cause

The new bootstrap command was added beside the old schema-3 update engine.
Removing fields from `release.json` and Runtime Control presentation did not
remove the same concepts from `UpdateBundleManifest`,
`RuntimeUpdateCompatibilityChecker`, or apply preflight input.

This left two conflicting domain models in one product: stable bootstrap
delegated specification interpretation to the signed next updater, while the
legacy Swift manifest still invited the installed updater to decide whether it
was new enough.

## Fix direction

- Remove minimum-updater and two-phase fields from the Swift manifest.
- Remove updater-version input and bridge policy from compatibility checks.
- Retain only checks that still belong to the legacy artifact boundary while
  it is being removed: channel, target platform, and explicit Guest activation
  consistency.
- Route public release automation exclusively through the Helper stable
  release composer. Do not translate the removed fields to empty, zero, or
  default values at the stable contract boundary.

## Prevention

An update compatibility rule must have one named owner. The installed Host
owns only the fixed signed bootstrap envelope. The bundle-owned next updater
owns the evolving Product Update Specification. A release field must not be
kept in a shared domain model merely because an obsolete serializer still
accepts it.
