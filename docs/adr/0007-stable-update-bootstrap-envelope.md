# ADR 0007: Stable Update Bootstrap Envelope

## 상태

Accepted, implementation in progress

This decision supersedes the updater-compatibility and two-phase-update
decision in ADR 0004. ADR 0004 remains the record of the previous design.
The Product Update and VM Image Update distinction remains valid.

## 배경

ADR 0004 made the updater version and the detailed update manifest a
compatibility gate. That design requires an already-installed updater to
understand the next release's manifest and orchestration rules. A new required
field, artifact layout, verification rule, or activation sequence can therefore
make a valid future release unreachable. `minUpdaterVersion` and
`requiresTwoPhaseUpdate` describe this limitation but do not remove it.

VitalServer Helper 0.2.2 is the clean-install baseline that changes this
boundary. The installed Host must understand only a small, stable bootstrap
envelope. The release bundle carries both the next updater and the detailed
product update specification. The installed Host authenticates and stages those
two artifacts, then hands execution to the staged updater. It does not interpret
the detailed specification.

## 결정

The stable Host bootstrap contract is `UpdateBootstrapEnvelope`.

It contains only:

- contract version and immutable update identity;
- product, platform, and architecture target;
- target product/runtime release identity;
- declared layer order;
- the next-updater artifact identity, path, size, and digest;
- the product-update specification artifact identity, path, size, and digest;
- publisher signature metadata and issue time.

The envelope deliberately has no `minUpdaterVersion`,
`requiresTwoPhaseUpdate`, migration command, service command, rollback command,
or layer-specific instruction. Unknown fields are rejected. A contract change
must therefore be deliberate rather than silently interpreted as an older
meaning.

The detailed product-update specification belongs to the release-bundled next
updater. The installed Host treats it as authenticated opaque bytes.

## 상태와 책임

| State or effect | Owner | Rule |
| --- | --- | --- |
| selected bundle path | Helper UI or Runtime Control caller | Input only; selection is not verification or admission |
| bootstrap envelope bytes | release publisher | Signed immutable release input |
| envelope decode and target policy result | installed Host bootstrap | Rejects missing, unknown, invalid, or mismatched state explicitly |
| publisher authenticity | installed Host bootstrap verifier | Verifies the envelope with an installed trust root before staging |
| next updater and specification bytes | release publisher | Digests and sizes are bound by the authenticated envelope |
| staged update workspace | installed Host bootstrap | Materializes only verified bundle-owned files under an update-specific path |
| update operation lease and handoff journal | installed Host | Durable source of truth for admission and handoff status |
| layer order, commands, migrations, health gates, rollback | staged next updater | Reads the release-owned specification; never inferred by the installed Host |
| layer effect result | the adapter responsible for that layer | Reports an explicit result to the next updater |
| installed release settlement | installed Host | Changes only from a correlated terminal next-updater result |

The UI formats these explicit states. It does not infer success from process
exit, files appearing, services becoming reachable, or the absence of an error.

## 적용 순서

```text
caller selects bundle
  -> installed Host reads strict envelope
  -> Host validates product and target
  -> Host verifies publisher signature
  -> Host verifies next-updater/specification size and digest
  -> Host creates durable operation admission and staged workspace
  -> Host invokes the staged next updater through a fixed handoff contract
  -> next updater owns detailed layer orchestration and rollback
  -> next updater submits a correlated terminal result
  -> Host settles installed release and operation state atomically
```

The Host platform layer, when present, must be last. This keeps the process that
owns admission and handoff available while container and Guest Runtime effects
run.

## 0.2.1에서 0.2.2로의 전환

The supported default is:

1. preserve or explicitly reset operator-owned data according to the install
   contract;
2. install the 0.2.2 PKG;
3. use the stable bootstrap envelope for updates after 0.2.2.

The unreleased 0.2.1 updater is not treated as a general compatibility
foundation. A direct 0.2.1-to-0.2.2 updater migration may be added only as an
explicit, tested one-time migration when product distribution requires it. It
must not be an automatic fallback.

The legacy schema-3 apply path remains closed until the new verification,
journal, handoff, and settlement path is complete. Removing the old
compatibility check before the new trust boundary exists would widen update
authority.

## 구현 상태

The Swift `Contracts` and `Domain` modules now define the strict v1 envelope and
pure target/layer/artifact policy. Cryptographic verification, durable
admission/handoff state, staged updater execution, release composition, and
Helper/PWA wiring remain implementation work. This paragraph must be updated as
each owner becomes executable.

## 결과

- Future detailed update specifications can evolve with their matching updater.
- The installed Host has a small and stable attack surface.
- Compatibility is structural rather than a version-number guess.
- Missing, invalid, mismatched, unverified, staged, handed-off, and settled are
  separate states.
- Release tooling must always produce and verify the envelope, next updater,
  and specification as one authenticated closure.

## 관련 결정

- ADR 0003 defines product component vocabulary.
- ADR 0004 retains the Product Update versus VM Image Update distinction and
  records the superseded updater-version compatibility design.
- `docs/architecture/host-update-handoff-supervisor-boundary.md` describes the
  corresponding next-generation handoff boundary.
