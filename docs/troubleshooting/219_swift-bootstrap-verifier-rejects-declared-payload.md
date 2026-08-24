# Swift Bootstrap Verifier Rejects Declared Payload

> ID: TS-219
> Category: Update / Bundle closure
> Owner: macOS runtime
> Status: resolved

## Symptoms

The publisher verifies a signed stable Product Update bundle, but the installed
Swift verifier rejects the same bundle before handoff:

```text
fileClosureMismatch(
  missing: [],
  unknown: ["payload/layers/..."]
)
```

The unknown paths are layer apply, effect executor, effect configuration, and
rollback files that belong to the authenticated bundle.

A v1 envelope cannot be admitted by a v2 Host, and a v2 envelope cannot be
admitted by a v1 Host. There is no fallback that accepts both.

## Cause

The v1 bootstrap envelope closed only over the envelope, next updater, and
specification files. The installed Host therefore treated every other regular
file as unknown before next-updater handoff.

The publisher already copied specification-declared layer artifacts into the
archive. Producer and consumer consequently enforced different closures: the
publisher expected those files, and the installed Host rejected them.

Decoding the Product Update Specification to learn the missing paths would have
made the installed Host depend on a changing specification schema. That is the
wrong owner. The specification remains opaque bytes to the installed Host.

## Fix Direction

Bootstrap envelope schema is now `v2`. The signed envelope itself declares
`payloadArtifacts` as an exact regular-file closure.

Verification has two explicit stages:

1. Structural validation rejects unsafe paths, unsupported entry kinds,
   duplicates, and missing envelope-owned files. Extra regular files are not
   classified yet.
2. Publisher signature, next-updater digest/size, and specification digest/size
   are verified. The specification is not decoded.
3. Exact closure is calculated from the envelope, next updater, specification,
   and every `payloadArtifacts` entry. Missing, extra, duplicate, wrong kind,
   wrong digest, and wrong size remain distinct failures.
4. After staging, the Host re-verifies the same envelope-owned closure and
   requires the staged proof to match the admitted proof.

The verification proof keeps bootstrap artifact IDs and payload artifact IDs
separate. Journal admission and recovery validate both proofs. Unknown envelope
keys and schema versions other than `v2` fail. `issuedAt` must be a real
canonical UTC instant, not only a regex match. Identifiers remain ASCII
`[A-Za-z0-9._-]{1,128}`.

## Prevention

An archive entry cannot be called unknown until its owning authenticated
contract has been read. Structural archive safety and semantic exact closure
must remain separate policies and execute in that order.

The installed Host must authenticate an envelope-owned payload list. It must
not decode Product Update Specification bytes to invent that list.

Keep a cross-implementation fixture gate: the Python publisher verifier and the
Swift installed-runtime verifier must both accept the same signed v2 envelope
and the same exact `payloadArtifacts` closure.

## Evidence

```sh
vitalserver-devtools verify-update-bootstrap-bundle \
  --bundle <bundle.tar.gz> \
  --publisher-trust-store <trust-store.json>

vitalserver-vm runtime verify-update-bootstrap <bundle.tar.gz>
```

Both commands must report the same update ID and accept the same archive
closure. A v1 envelope must fail as an unsupported schema.

## Related Cases

- [TS-195: Bootstrap bundle omits specification-owned payload](195_bootstrap_bundle_omits_specification_payload.md)
- [TS-199: Helper stable update specification is hand-assembled](199_helper_stable_update_specification_is_hand_assembled.md)
