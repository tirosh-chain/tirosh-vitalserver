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
| installed product release | installed Host SQLite | Revision 1 is written from an explicit package-install operation; later revisions change only with a correlated terminal next-updater result |

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

The Swift `Contracts` and `Domain` modules define the strict v1 envelope and
pure target/layer/artifact policy. The verified closure is an explicit contract,
and pure admission policy creates revision-one `admitted` journal state only
when its update identity, signed payload digest, and complete artifact set match
the envelope. The Application verification use case keeps
unavailable, failed, invalid, and mismatched results distinct. Outbound adapters
produce the cross-platform canonical payload, verify real Ed25519 signatures,
stream artifact digests, and reject non-regular files. The installed publisher
trust store is also a strict contract; its reader keeps unavailable, read
failure, decode failure, policy violation, and public-key decode failure
distinct. A strict Host-owned journal contract and pure state machine now
separate admitted, handoff-pending, running, succeeded, failed, and interrupted
states; terminal receipts must match the journal revision, request, envelope,
and specification digest. Host SQLite schema v9 owns the journal and singleton
installed-product-release document. A fresh package installation writes
revision 1 with package-install provenance. A succeeded update journal revision
and its correlated next installed-product-release revision are committed in one
immediate transaction with optimistic revision validation; a stale writer or
either write failure changes neither fact. The Platform Agent reads this SQLite
owner for Helper runtime-version presentation and preserves missing or failed
reads as explicit issues. `runtime-version.json` remains an installation
projection during the transition, but is not a fallback for authoritative
product release state. Bootstrap staging now copies into an attempt-specific temporary
directory and atomically publishes an immutable update-ID workspace; an
existing final workspace is an explicit conflict and is never deleted or
replaced. The fixed v1 handoff invocation is created only from a persisted
`running` journal and carries correlation identities, digests, and relative
artifact paths rather than arbitrary commands. Invocation document
persistence is exclusive, and the process adapter can execute only the staged
updater with the fixed `execute --invocation` argument shape. A strict receipt
reader preserves missing, inspection, read, and decode failures, while the
Application settlement use case accepts only a receipt correlated by the
journal state machine. The durable handoff workflow persists admitted,
handoff-pending, and running revisions before dispatch, then persists the
correlated terminal revision. Operation failure, failure-transition failure,
and failure-persistence failure remain distinct. A settlement failure
transitions the last persisted running journal to an explicit failed revision
rather than leaving an uncommitted success visible. Release tooling now composes
the envelope, staged next updater, and opaque specification into one exact
three-file archive closure. It signs the Swift-compatible canonical payload
with Ed25519, refuses symlink or non-regular inputs, refuses to replace an
existing release artifact, and provides a separate verification command that
checks the publisher signature, closure, sizes, and digests. The signing
implementation uses the cross-platform Python `cryptography` API rather than a
host `openssl` executable, whose Ed25519 capability differs across macOS,
Windows, and Linux installations. The installed-product-release contracts,
pure policy, application ports, SQLite repositories, package-install
composition, handoff workflow, admission policy, and Helper presentation read
path are implemented and tested. The installed Host now also has strict
bootstrap-directory readers and a pure exact-closure policy: the envelope and
its two declared artifacts must be the only regular files, duplicate or unsafe
paths and symbolic links are rejected, and missing, inspection, listing, read,
and decode failures remain distinct. The installed CLI now exposes
`runtime apply-update-bootstrap <bundle> --request-id <id>`. Its Host
composition materializes an archive or explicit bundle directory, requires the
installed product release and an absent journal for the envelope ID, loads the
installed trust store, verifies the exact authenticated closure, persists
admission, atomically stages the bundle, launches only the staged executable
with the fixed handoff invocation, reads the correlated completion receipt, and
atomically settles the succeeded journal with the next installed release
revision. An existing journal is an explicit collision: this entry point does
not guess whether it should retry, resume, or replace that state. Archive
materialization cleanup failure is also reported instead of being hidden.
Package assembly now requires a release-process-owned public-key trust store as
an explicit input before VM/rootfs compile. The tooling strict-decodes the v1
contract, installs the exact bytes at
`/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json`,
and reads the expanded PKG payload back from the DMG to prove that it matches
the release input. It neither creates a default key nor derives a public key
from private signing material. Persisted non-terminal journals now have
state-specific operator commands. `resume-update-bootstrap-handoff` accepts
only `handoff-pending`, re-reads the exact staged closure, and repeats
publisher, target, artifact, and journal correlation verification before it
persists `running` and dispatches the updater.
`settle-update-bootstrap-handoff` accepts only `running`, reads and correlates
an existing receipt, verifies the referenced report file digest, and settles
without launching the updater again. A missing receipt or invalid report
leaves a recovered `running` journal unchanged. An operator can explicitly
terminate any non-terminal journal with
`fail-update-bootstrap <id> --reason <reason>`; the reason is required and the
update ID is not silently reusable. These commands require an exact journal
ID and never select the latest journal as fallback.

The fixed handoff invocation now also carries the exact `layerOrder` from the
authenticated bootstrap envelope. The bundle-owned next updater parses the
strict `ProductUpdateSpecification` contract and pure planning policy requires
its layer plan to cover that order exactly, preserves the declared order
without sorting, requires every dependency to refer to an earlier layer, and
requires `host-platform` to be final. Layer artifacts, rollback artifacts,
effect executors, and executor configuration are distinct immutable payload
members with explicit paths, sizes, media types, and SHA-256 digests. This
planning boundary does not execute effects; process execution and typed layer
effect receipt aggregation remain a separate adapter responsibility.

The bundle-owned execution workflow now consumes only the pure execution plan
and explicit layer-effect execution results. It issues `apply` requests in the
authenticated order, validates every typed receipt against the update, layer,
declared executor, operation, and artifact digest, and stops at the first
non-successful effect. Previously applied layers are requested in reverse order
with their explicitly declared rollback artifacts. Missing executor evidence,
adapter unavailability, process failure, invalid correlation, unsupported
rollback, and rollback failure remain different typed outcomes. The workflow
aggregates them into one correlated `ProductUpdateExecutionReport`; it never
uses a process exit code or missing receipt as success. Filesystem
materialization, fixed process arguments, atomic report publication, and the
standalone next-updater executable remain outside this pure workflow.

Release automation calls:

```sh
vitalserver-devtools update-bootstrap-bundle \
  --update-id <stable-id> \
  --product-version <version> \
  --runtime-version <version> \
  --target-platform <macos|windows|linux> \
  --target-architecture <arm64|amd64> \
  --layer <ordered-layer> \
  --next-updater <executable> \
  --specification <json> \
  --publisher-key-id <installed-trust-key-id> \
  --publisher-private-key <unencrypted-ed25519-pkcs8-pem> \
  --issued-at <canonical-utc> \
  --output <new-tar-gz-path>

vitalserver-devtools verify-update-bootstrap-bundle \
  --bundle <tar-gz-path> \
  --publisher-public-key <ed25519-spki-pem>
```

The private key path is an explicit release-publisher input. The tool neither
searches for a key nor falls back to another signer. Secret storage and key
materialization remain responsibilities of the release environment.

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
