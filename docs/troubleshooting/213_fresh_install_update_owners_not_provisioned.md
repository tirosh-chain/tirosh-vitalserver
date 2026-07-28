# Fresh install does not provision update owners

> ID: TS-213
> Category: Packaging / Guest bootstrap / Update
> Owner: Guest bootstrap and Guest SQLite control store
> Status: resolved

## Symptom

- A newly installed Helper has no current Container Image-Set or active Guest
  Runtime Release in Guest SQLite.
- Container or Guest Runtime apply/rollback is rejected because its expected
  current identity is missing.
- Rebooting after a successful Guest Runtime update can replace the active
  release with the package baseline, or bootstrap can fail because the active
  link no longer targets that baseline.

## Cause

The repositories exposed test-only initial provisioning methods, but the
product build did not produce an explicit initial owner contract and bootstrap
did not consume one. A separate pre-bootstrap filesystem command also treated
the active symlink as installation state. That made filesystem shape, rather
than the Guest SQLite state owner, decide whether initialization had happened.

## Fix direction

Product compile now creates
`deploy/build-metadata/fresh-install-release.json` from the release manifest.
The rootfs build composes the following artifacts from the actual staged
bytes:

- the bundled Container Image-Set archive;
- a deterministic archive of the installed Guest Runtime;
- `deploy/initial-update-owner-state.json`, containing exact release
  identities, SHA-256 digests, relative paths, and content-addressed owner
  references.

After Guest SQLite migration, bootstrap verifies and imports both archives.
On the first installation it converts the bootstrap Guest Runtime directory
to an immutable release slot and atomically writes both owner pointers plus an
`initial_update_owner_provisioning` receipt.

Every later boot verifies the exact contract digest and initial declaration
against that receipt. It also verifies that current/active pointers still
resolve to decodable immutable records. A valid receipt does not require the
current owners to remain at the package baseline, so a later update survives
reboot. Missing receipt with partial owner state, receipt mismatch, missing
pointer, and dangling/invalid immutable state are explicit failures.

## Prevention

- Generate initial owner identity and digest only from staged release inputs
  and actual archive bytes.
- Keep first-install state in Guest SQLite; never infer it from a symlink,
  directory, filename, log, or absent value.
- Write the two owner pointers and immutable provisioning receipt in one
  transaction.
- Verify the receipt on every boot without resetting owners changed by an
  accepted update.
- Treat VM/rootfs compilation as failed when the initial owner contract or
  either declared archive is missing.

## Related cases

- [TS-207: Container update had no explicit image-set owner](207_container_update_had_no_explicit_image_set_owner.md)
- [TS-208: Guest Runtime update had no release owner](208_guest_runtime_update_had_no_release_owner.md)
- [TS-211: Guest update owner operation never executes](211_guest_update_owner_operation_never_executes.md)
- [TS-212: Guest-owned layer executor reports false success](212_guest_owned_layer_executor_reports_false_success.md)
