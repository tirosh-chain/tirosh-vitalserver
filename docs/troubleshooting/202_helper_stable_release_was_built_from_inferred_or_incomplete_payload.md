# TS-202: Helper stable release was built from inferred or incomplete payload

## Symptom

A Helper update bundle has a valid bootstrap envelope, but a layer cannot be
applied or rolled back because its artifact, effect executor, effect
configuration, or rollback artifact is absent. A release may also accidentally
publish bytes discovered from an installed machine instead of the intended
release inputs.

## Cause

The low-level `update-bootstrap-bundle` command signs a caller-provided Product
Update Specification and copies the artifacts declared by that specification.
It does not decide which three Helper layers form a product release.

Building the specification separately from the payload permits release
automation to omit a role or to observe mutable installed state. A signed
envelope proves the supplied closure; it does not prove that the caller supplied
the complete Helper product release.

## Fix direction

Use `helper-stable-update-release` for Helper 0.2.2 and later. Supply these
actual files explicitly for each of `container`, `guest-runtime`, and
`host-platform`:

- layer artifact and its media type,
- effect executor,
- effect configuration,
- rollback artifact and its media type.

Also supply the bundle-owned next updater, publisher key identity and private
key, deterministic issue timestamp, target, versions, update identity, and
output path.

The composer copies each supplied regular file into a fixed role path, observes
the copied bytes, creates the Product Update Specification from those
observations, and invokes the signed stable bootstrap builder. It rejects a
missing, symlinked, duplicated-by-content role, reordered layer, unreadable
input, or pre-existing output. It does not inspect the installed Helper,
receipts, runtime databases, logs, or prior release directories.

The low-level command remains useful for bootstrap contract tests, but it is not
the Helper product-release composition boundary.

## Prevention

Keep release composition as one application workflow:

1. accept immutable, explicit release artifacts,
2. materialize and hash every role,
3. derive one deterministic Product Update Specification,
4. build one signed bundle from the exact materialized closure, and
5. verify the signed bundle with the publisher public key before publication.

Do not add installed-state discovery, optional rollback inference, wildcard
payload copying, or a separately maintained specification template to this
workflow.
