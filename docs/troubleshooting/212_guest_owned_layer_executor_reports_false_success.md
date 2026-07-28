# Guest-owned layer executor reports false success

> ID: TS-212
> Category: Update / Host-to-Guest execution
> Owner: Container and Guest Runtime Layer Effect Executors
> Status: resolved at bundle executor boundary

## Symptom

- A signed update bundle contains Container or Guest Runtime layer artifacts,
  but the bundle runner has no concrete executable that can apply them.
- An effect process exits successfully after submitting a command even though
  the Guest owner is still `pending` or `running`.
- Connection loss, timeout, malformed JSON, an identity mismatch, or a digest
  mismatch is displayed as an empty or successful result.
- Rollback accidentally sends the apply transition or applies an artifact for
  a different layer.

## Cause

The Guest owners and durable worker provide the authoritative operation state,
but the Host bundle boundary previously stopped at a generic executor
declaration. There was no packaged process that consumed the verified absolute
artifact/configuration paths, imported the bytes, submitted the correct owner
command, correlated the response, and waited for the authoritative terminal
result.

Process exit, HTTP acceptance, missing response fields, and a local artifact
filename are not update state. Treating any of them as success bypasses the
state owner and can settle the signed bundle while the installed product is
unchanged or only partially changed.

## Fix direction

The macOS Runtime package now publishes two fixed-interface products:

- `vitalserver-container-layer-effect-executor`
- `vitalserver-guest-runtime-layer-effect-executor`

Both accept only:

```text
execute --request <absolute-request.json> --receipt <absolute-receipt.json>
```

The request comes from the verified bundle-owned runner and contains verified
absolute artifact and configuration paths plus their expected SHA-256 values.
Each executor:

1. validates its declared layer and executor identity;
2. re-hashes both local files without loading the whole archive into memory,
   and verifies the artifact's declared byte size and layer media type;
3. streams the archive to the Guest content-addressed import owner;
4. submits only its own Container Image-Set or Guest Runtime Release command;
5. correlates operation ID, command, expected identity, target identity,
   digest, and Guest archive reference;
6. polls until the Guest owner reports `succeeded`, `failed`, or
   `unavailable`;
7. atomically writes exactly one strict receipt.

`failed` and `unavailable` remain distinct. Timeout and connection loss are
`unavailable`; malformed contracts, identity/digest disagreement, and explicit
owner failures are `failed`. The process refuses to overwrite an existing
receipt.

The checked-in strict configuration schemas and examples are under
`apps/vitalserver-macos-runtime/Support/UpdateExecutors`. Apply and rollback
must be inverse identity transitions, and the configuration declares exactly
one `container` or `guest-runtime` owner.

Guest Runtime activation switches `/opt/tirosh/guest-tools` to an immutable
release slot and restarts the long-running services whose wrappers resolve
that link. If a restart fails after a partial transition, the effect restores
the previous link and reconciles the previous release again. Failure of that
compensation is persisted separately as
`guestRuntimeReleaseCompensationFailed`; it is not flattened into ordinary
activation failure. The Host poll tolerates transient connection loss after
command acceptance while the Guest Control API restarts, but reports the last
unavailable state if the owner does not recover before its deadline.

## Prevention

- Never settle a layer from HTTP `202`, process exit, or absent state.
- Never let Container and Guest Runtime executors share an implicit target
  owner.
- Reverify bytes at the Host bundle boundary and again inside the Guest.
- Reject unknown response/configuration fields rather than decoding a partial
  success.
- Preserve timeout, dependency loss, owner failure, and correlation mismatch
  as explicit typed receipts.
- Treat rollback as a complete immutable previous artifact plus an explicit
  inverse identity transition.

## Related cases

- [TS-205: Helper stable release has no concrete layer owner ports](205_helper_stable_release_has_no_concrete_layer_owner_ports.md)
- [TS-207: Container update had no explicit image-set owner](207_container_update_had_no_explicit_image_set_owner.md)
- [TS-208: Guest Runtime update had no release owner](208_guest_runtime_update_had_no_release_owner.md)
- [TS-211: Guest update owner operation never executes](211_guest_update_owner_operation_never_executes.md)
