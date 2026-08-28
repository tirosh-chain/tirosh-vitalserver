# Bootstrap bundle omits specification-owned payload

## Symptom

- The Host verifies and stages a stable bootstrap bundle.
- The staged next updater decodes the Product Update Specification.
- The first layer fails because its artifact, effect executor, executor
  configuration, or rollback artifact is missing from the staged directory.

## Cause

The release composer treated only the bootstrap envelope, next updater, and
specification document as the bundle closure. The specification referenced
additional immutable files, but those files were neither copied nor verified.
The bootstrap documents were internally valid while the release was not
executable.

## Fix direction

1. Require an explicit prepared payload root from the release process.
2. Strictly decode and validate the Product Update Specification before
   signing the bootstrap envelope.
3. Resolve every declared file below the payload root.
4. Require regular non-symlink files with exact declared sizes and SHA-256
   digests.
5. Copy only the declared files and reject conflicts with bootstrap-owned
   paths.
6. During verification, derive the complete expected closure from the
   authenticated specification and reject missing or unknown files.

## Prevention

A release bundle is complete only when every file required for apply and
rollback is present and bound by an authenticated contract. A valid document
that points to absent bytes is not a valid executable release.
