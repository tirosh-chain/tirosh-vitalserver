# Effect Configuration Signed Without v2 Schema Validation

> ID: TS-225
> Category: Update / Release composition
> Owner: vitalserver-devtools
> Status: active

## Symptoms

`helper-stable-update-release` composes and signs a bundle whose
`container`/`guest-runtime` effect configuration is not checked against the
`vitalserver.guest-owner-layer-effect-configuration/v2` schema. A malformed
configuration (wrong `schemaVersion`, wrong `layer`, missing or extra fields,
invalid timeouts or identity transitions) is signed successfully and rejected
only later by the installed layer-effect executor.

The same composition also declares an executor artifact `id` that does not match
the configuration's `effectExecutorId`. The Swift executors refuse such an
invocation with `executorIdentityMismatch` / `layer-effect-invocation-invalid`,
so a structurally complete bundle can still fail at the first layer effect.

## Cause

The composer copied the effect configuration bytes verbatim and recorded the
executor artifact id as a hardcoded `helper-<layer>-effect-executor`, unrelated
to the identity the configuration declares. There was no read, decode, or schema
validation of the effect configuration before signing, and no contract tying
`effectExecutorId` to the specification's executor artifact id.

## Fix Direction

- Read and JSON-decode the effect configuration before signing, with distinct
  errors for read/permission failure, UTF-8 decode failure, JSON parse failure,
  and non-object root.
- Validate `container` and `guest-runtime` configurations against the v2 schema
  semantics (exact keys, `schemaVersion` and `layer` constants, timeout and poll
  ranges, and apply/rollback identity transitions with the reverse invariant).
- Use the validated `effectExecutorId` as the executor artifact id in the
  specification, so the single declared identity is preserved end to end rather
  than rewritten or inferred. The `effectExecutorId` is checked against the
  specification's identifier contract (ASCII `[A-Za-z0-9._-]`, 1-128 chars) at
  the configuration boundary so the error surfaces before signing.
- Read the effect configuration once and write those exact bytes to the payload,
  recording digest and size from the same bytes, so validation and the signed
  closure cannot desynchronize (no TOCTOU window).
- Validate `host-platform` configurations minimally for their declared
  `effectExecutorId` and `schemaVersion`.

## Prevention

The executor identity is owned by the effect configuration (a publisher-owned,
explicit identity document), not recomputed by the composer. Schema parity tests
load the JSON schema and example documents to keep the hand-written validator
from drifting, and the validator keeps its own exact-key and identifier helpers
so it does not depend on the bootstrap bundle implementation. A minimal
`{"layer": ...}` configuration is no longer a signed success.

## Related Cases

- [TS-199: Helper stable update specification is hand-assembled](199_helper_stable_update_specification_is_hand_assembled.md)
- [TS-202: Helper stable release was built from inferred or incomplete payload](202_helper_stable_release_was_built_from_inferred_or_incomplete_payload.md)
- [TS-205: Helper stable release has no concrete layer owner ports](205_helper_stable_release_has_no_concrete_layer_owner_ports.md)
