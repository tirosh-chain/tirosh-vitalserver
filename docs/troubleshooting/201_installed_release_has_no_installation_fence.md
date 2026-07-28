# TS-201: Installed release has no installation identity fence

## Symptom

An update completion can identify the product release revision, but it cannot
prove that the release still belongs to the same installed product instance.
After a clean reinstall, both the old and new installations can start with
release revision `1`.

## Cause

The Host-owned `installed_product_release` contract stored product and runtime
versions plus a release revision. It did not own a stable `installationId` or an
installation-wide revision. Release revision alone therefore could not fence a
writer from a previous installation.

Schema v9 also stored the release revision only. Reading `document_json` without
cross-checking its indexed columns could hide a damaged or partially rewritten
record.

## Fix direction

Contract v2 and Host SQLite schema v10 own:

- a stable, opaque `installationId` created once for an installation,
- an `installationRevision` incremented by every accepted installation
  transition, and
- the existing `releaseRevision`, which advances only when the installed
  product release advances.

Package installation inserts revision `1` only when the singleton is absent.
Update settlement compares installation identity and revision, then performs a
single SQL compare-and-swap while settling the update journal in the same
transaction. Reads validate that SQLite columns and the strict JSON document
describe the same state.

Existing unreleased schema-v9 rows use a dedicated v9-to-v10 migration. The
migration receives a new installation identity from its explicit migration
input and maps the previously recorded release transition count to the initial
installation revision. It does not derive identity from a path, version,
receipt, or operation log.

## Prevention

Every install, update, uninstall, and recovery command must carry the expected
installation identity and revision from admission through settlement. A
repository must reject identity mismatch, stale revision, malformed migration
input, and column/document mismatch as distinct failures. Do not regenerate,
guess, or silently replace installation identity during ordinary reads.
