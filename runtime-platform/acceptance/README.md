# Acceptance

Acceptance tests express observable product behavior across deployable units.

They may drive the public control facade, recorder ingress, and explicit test adapters. They must not reach into private state stores or use production code from the legacy root. When a scenario needs behavior evidence from the existing product, it may use only a registered, digest-verified fixture from `reference-fixtures/`; it must still assert a new-platform public contract rather than a legacy internal state.

The Host/Guest control proof uses a real Guest Runtime **application composition** and a real Host Agent HTTP facade with separate temporary SQLite databases. Its explicitly named `guest-runtime-control-http-acceptance-fixture` binds only the public TCP/HTTP control contract so the same contract proof can run on a macOS or Windows host. It never pretends to be a production Guest process and deliberately does not bind the Linux Guest's AF_VSOCK control listener. The production `guest-runtime` entry point still requires that C37-declared listener; the macOS virtual-machine smoke is the separate proof for C32 Host-local bridge ↔ C37 Guest virtio-socket transport. The deterministic provider result sources used by this fixture never become selectable by the product Host Agent. Cross-platform acceptance supplies its Host Agent through C33 `HostAgentDeploymentConfiguration`, so test deployment uses the same startup contract as launchd rather than retired individual configuration flags. See [Host/Guest Control Slice](../../docs/architecture/host-guest-control-boundary.md) for the exact proof and its intentional limits.

This proof also reads C77 only through `platformctl` and the Host facade,
restarts the real Guest application composition with the same SQLite ledger
and migrated PostgreSQL owner, and requires the SQLite identity, PostgreSQL
identity, exact revision, owner-schema set, migration receipt, and non-secret
private-material-set identity to remain equal. This is portable ownership and
restart evidence; it is not clean ARM64 Guest boot, virtio transport, or C24
installation evidence.

The C78 installed Guest evidence runner is the matching clean-host collection
workflow. `create-run` binds an explicit `platformctl` executable, C52
local-control descriptor, `sysctl`, canonical contract root, release plan ID,
and new evidence directory. `record-first-boot` requires available readiness
and C77 while the Host boot-session ID is stable. `record-direct-upload`
requires one explicit approved-provenance `.vital` source, Recorder ID,
reported bed, Recorder code, upload ID, Edge origin, and `curl` executable. It
streams the whole file as one multipart upload, never segments it, and accepts
the step only when the Recorder Assignment receipt, Recorder artifact page,
and Archive artifact detail agree on source receipt, SHA-256, byte size, and
matched Recorder attribution. The plain Gateway `success` body is necessary
but insufficient. After the operator performs the real Host reboot,
`record-post-reboot` requires both prior stages, a different boot-session ID,
and exact equality of C77 `sqlite`, `postgresql`, and `bootstrap` identity.
The runner writes immutable evidence plus a separate SQLite journal containing
command observations. It does not reboot the Host or infer Guest state from
C24 package and launchd evidence.
The macOS C24 runner consumes the resulting three immutable C78 documents only
through its explicit `record-installed-guest-runtime` command. That command
validates and embeds the exact chain as a distinct required C24 stage; it does
not merge Guest readiness into `clean-install` or `reboot`.

The Recorder Gateway proof runs a built Gateway with a test-only Engine.IO v3 / Socket.IO protocol-v4 wire fixture (the protocol used by Socket.IO v2 Recorders), a real v4 Socket.IO server adapter, durable temporary Gateway state, and a deliberately narrow VitalServer acknowledgement fixture. The harness reads only the Gateway's public receipt routes and validates the emitted C5/C13 documents with the canonical JSON schemas. It does not inspect Gateway-private durable ingress-state files.

The Lab Runner/Gateway proof starts both production Node entrypoints and drives
their Guest-loopback HTTP and Socket.IO contracts. It verifies a Runner-selected
scenario joins the real Gateway, receives packet acknowledgements, finalizes
the exact capture, and matches the public packet-sequence digest to Gateway's
finalization receipt. The only fixture is the named C19 Guest catalog boundary,
which acknowledges the Recorder-owned observation and never supplies Gateway
ingress, capture, finalization, Archive, or upstream state.

The opt-in C4 Lab replay proof starts the production Guest Runtime application
composition, Lab Recorder Runner, Recorder Gateway, and a narrow VitalServer
acknowledgement fixture. The named `lab-replay-guest-runtime-acceptance` target
requires an explicitly migrated PostgreSQL test database. It first proves a
frozen synthetic v1 source reaches a persisted upstream acknowledgement, then
admits a valid synthetic v3 source whose only numeric track has no explicit
VitalServer graph mapping. That second replay must persist `failed` at
`track-decode` with `no-vitalserver-graph-tracks`, zero messages, and
`not-attempted`; source-upload acceptance alone is never replay success. This
generated negative fixture is protocol evidence, not the approved real-file
corpus required for release compatibility evidence.

2026-07-24에는 이 target을 지원 범위인 Node 20.19.3과 별도
`0006_backup_owner` PostgreSQL clone에서 실행해 두 public replay 시나리오가
통과했다. 지원 밖 Node 실행은 이 증거를 대체하지 않으며, repository의
환자 `.vital` 파일도 비식별·재배포 provenance 승인 없이 release corpus로
선택하지 않는다.

The separate `lab-replay-approved-corpus-acceptance` target is the C79 release
gate. It requires an absolute human-approved manifest, its reviewed external
corpus directory, and a migrated PostgreSQL database. Before starting replay,
the verifier requires exact registration of every `.vital` file and matches
its regular-file identity, byte size, and SHA-256. Each entry must then reach a
Guest-owned `succeeded` replay with the declared v1-v3 format and at least the
declared graph-compatible signal count. Parser success cannot create or replace
the manifest's human non-identification and redistribution approval.

The Lab and Archive proof runs the same real Guest Runtime application composition through the explicitly test-only HTTP acceptance fixture and uses only public Lab and Archive HTTP resources. It proves that `stop` has no implicit export claim, that source finalization/manifests and upload/index receipts are separate immutable facts, that known provider failures leave Lab state unchanged, and that an unknown provider outcome remains a durable running operation without a guessed receipt. It also proves hide/detach/delete semantics and the explicit retained Archive references left by a Lab cascade delete. The harness never reads Guest SQLite tables or archive object bytes.

The external, time, and observability proof builds the Guest Runtime HTTP acceptance fixture and test-only Host Agent composition, drives only published HTTP resources, and validates C16–C20 documents through the canonical schemas. It proves external-upstream capability does not inherit bundled lifecycle behavior, relay and external-upstream state stay independent, Host/Guest clock quality is node-local, Recorder-owned `occurredAt` survives Catalog projection, and telemetry keeps redaction/cardinality/collector outcomes separate from product state. The deterministic profile adapters used by this harness are named test deployments; they do not turn a missing physical NTP or OTLP collector into a production success claim.

The opt-in C76 Guest operational-state proof requires a freshly migrated
PostgreSQL source, a distinct database with no non-system schema or public
relation, and explicit absolute `pg_dump`/`pg_restore` paths. The named
`guest-operational-state-backup-restore-acceptance` target first seeds Catalog,
Archive, and Assignment facts through their real repository/application
boundaries. It then executes the durable Guest backup and restore workflows
with a real SQLite online snapshot, PostgreSQL custom archive, metadata-only
artifact inventory, immutable manifest, absent SQLite target, and empty
PostgreSQL target. Success requires restored SQLite operation evidence, exact
row-count parity for every owner evidence surface, revision and database
identity reads, and explicit rejection of a second restore to the now non-empty
target. The caller owns source/target provisioning; the test never creates an
empty-state claim from a missing environment variable.

The installation and update proof builds the test-only Host Agent composition, `release-composer`, the separately compiled `host-updater`, and `host-update-handoff-supervisor`, but drives only their published CLI/Host-local contracts. It proves C25–C31 signed release composition, C31 consumption by the C56 supervisor, C57 immutable dispatch evidence, durable handoff ordering, request/report idempotency, restart handoff recovery, next-updater-only C26 planning, digest-verified C55 executor receipts, atomic C28 evidence, and C52 Unix-socket C27 completion. `completion-submitted` in C57 is deliberately not update success; C29 is still the settlement owner. Its verified bundle path performs native signature verification and staging; the C55 executors are fixtures, so it is not package activation, concrete layer replacement, or a clean-host release proof.
