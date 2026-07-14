# Runtime v2

## 1. Runtime Boundary

### 1-1. Runtime v2 moves service control into the Guest

Runtime v2 makes the Host a VM/proxy/API consumer and moves service control into the Linux Guest. The Host must not infer Docker Compose service state from runtime files once the v2 Guest Control API is the primary service boundary.

### 1-2. Guest Control API is the service control plane

Guest Control API owns service status and service operations. Runtime Control API, Swift Shell, PWA, and CLI should consume this boundary through Host adapters instead of reading Guest files.

Initial Guest endpoints:

```text
GET  /health
GET  /ready
GET  /runtime/capabilities
GET  /runtime/services
GET  /runtime/services/{service}/status
POST /runtime/services/{service}/start
POST /runtime/services/{service}/stop
POST /runtime/services/{service}/restart
POST /runtime/stack/reconcile
GET  /runtime/operations/{operationId}
```

## 2. Current Implementation

### 2-1. Service operations are explicit domain state

Service operations now have explicit domain states. `accepted`, `running`,
`completed`, `failed`, `cancelled`, and `interrupted` are different meanings and
must not be collapsed into success, empty, or unknown.

### 2-2. Compose access is behind an outbound adapter

Docker Compose commands are isolated behind the Guest Control Compose adapter. Domain and application code must not parse Compose output or execute Compose directly.

### 2-3. Guest Control owns a durable SQLite control ledger

Guest Control's operational state is stored in Guest-owned SQLite, not in the
Host shared mount and not in the product Postgres database.

| Platform | Platform-owned root | Must already be mounted | Control-state directory | Database |
|---|---|---:|---|---|
| macOS Guest VM | `/mnt/runtime` | yes | `/mnt/runtime/control` | `control.sqlite` |
| Windows Hyper-V Guest VM | `/mnt/runtime` | yes | `/mnt/runtime/control` | `control.sqlite` |
| Linux Native | `/var/lib/vitalserver` | no | `/var/lib/vitalserver/control` | `control.sqlite` |

These are platform settings defaults, not service-unit arguments.
`[controlStore]` explicitly declares `root` and `requiresMount`, and
`paths.controlStateDir` must be inside that root. Guest Control API startup and
`tirosh-guest-tools-migrate-control-store` both resolve this one settings
contract, while systemd units only run the lifecycle command. The migration
command deliberately has no data-root override, so it cannot migrate a
different ledger from the API's configured database. Before it creates the
Guest-owned `control` directory or `control.sqlite`, migration verifies that
the platform root already exists as a real directory; VM configurations also
require the operating system to report that root as mounted. It never creates a
missing root on the root filesystem. Native Linux explicitly declares its
Host-owned `/var/lib/vitalserver` root with `requiresMount = false`; this is not
an inferred mount exception. A custom root remains unavailable until its
platform has explicitly provisioned it and, when configured, mounted it. When
`VITALSERVER_RUNTIME_CONTROLLER_SETTINGS_PATH` selects a settings file, that
file must be present and readable; missing, unreadable, and invalid settings
are explicit configuration failures rather than a fallback to packaged values.

The SQLAlchemy adapter is an infrastructure implementation detail. Domain
operations remain dataclasses and cross the port as explicit documents; ORM
records and record-to-domain mapping remain inside the SQLite adapter. The
installer creates a new isolated venv from a hash-verified offline wheelhouse.
Before installation it verifies that the requirements file hash-pins every wheel
declared by that target manifest, proves the pinned SQLAlchemy/Alembic imports,
and only then publishes the venv.
It does not create the control database: macOS bootstrap may run before the
durable runtime-data mount is available. The Guest Control systemd service has
an explicit `ExecStartPre` migration command. `RequiresMountsFor` matches the
reviewed default root and orders that command after its mount unit; migration
independently rejects an unmounted configured VM root. That mounted-at-path
gate is deliberately not proof of the expected persistent disk identity. The
units are not generated from a custom settings override: an override must still
be provisioned by its platform, and migration fails explicitly until it is
ready. The VM runtime-data contract proves an ext filesystem label and mount
path during VM preparation, while native Linux owns
`/var/lib/vitalserver` without that same source/label contract. A future
identity proof must remain an explicit platform-owned contract, not a
directory-exists fallback. The command runs after an existing controller
process has stopped and before a new one starts. Native Linux uses the same
service-lifecycle gate. Guest Control API startup only verifies the schema; it
never creates or migrates it as an implicit side effect. Rootfs compilation
records the dependency proof, while migration is proved at service activation.
A missing wheel, failed migration, or unavailable control store is an explicit
startup failure rather than a later API fallback.

One Guest Control process is the control-ledger writer. Command acceptance
commits the operation document, immutable event, and `guest-control` lease in
one SQLite transaction. A terminal transition commits its event and lease
release together. A second command while the lease exists is rejected with
HTTP `409` and public code `operationInProgress`; it is never silently queued
or represented as an empty result. When the controller starts, it explicitly
changes any persisted `accepted` or `running` operation to `interrupted` with
failure kind `controllerRestarted`, records that event, and releases the lease.

Postgres remains a bridge-release dependency for the VitalDB read model and
the Lab service's own session/read-model store. It is not a startup dependency
for the Guest Control control ledger. Moving those remaining product stores and
removing Postgres are a separate migration, not an implicit consequence of
this control-state change.

`GET /ready` probes and returns only required Guest Control dependencies:
currently the Guest-owned `operationRepository` control store. It never probes
the configured VitalDB read model, so a Product Postgres delay or failure cannot
delay or make the Host's Guest Control readiness unavailable. VitalDB read routes
remain responsible for reporting their own product read-model failure to their
consumers.

### 2-4. Host exposes Guest service control through the v2 API path

Host now has a Guest Control API consumer boundary for product service start, stop, and restart. The Swift contract preserves the Guest operation document instead of converting it into a shell command result.

Host-facing entry points:

```text
GET  /runtime/services
GET  /runtime/services/{service}/status
POST /runtime/services/{service}/start
POST /runtime/services/{service}/stop
POST /runtime/services/{service}/restart
vitalserver-vm runtime guest-service-start <service> [--guest-control-url <url>]
vitalserver-vm runtime guest-service-stop <service> [--guest-control-url <url>]
vitalserver-vm runtime guest-service-restart <service> [--guest-control-url <url>]
```

Read responses preserve the Guest service list and status documents. Command responses preserve the Guest Control API operation document with `operationId`, `service`, `command`, `state`, timestamps, and optional explicit failure information.

`runtime start-services` and `runtime stop-services` remain native Host
maintenance commands for Host launchd runtime services such as VM, proxy,
guest log sync, and watchdog. They are not exposed through Runtime Control HTTP
API and they are not the product service control path. Product service actions
go through Guest Control so Docker/Compose state and operation state stay
Guest-owned.

Runtime Control capabilities preserve the same ownership split. Platform
maintenance booleans are served only by `GET /platform/capabilities`.
`GET /runtime/capabilities` passes through the Runtime Controller-owned
`schemaVersion` and capability identifiers from Guest Control. Product service
control requires `services:start`, `services:stop`, and `services:restart`;
Product Lab availability comes from Runtime-owned `lab:*` identifiers. The
Platform Agent does not advertise those product capabilities on behalf of the
Runtime Controller.

Guest maintenance capability checks also consume Guest Control API directly.
Host update, Redis backup/restore, and datastore repair preflight checks read
`GET /runtime/capabilities` and map `RuntimeGuestCapabilityRequirement` to explicit
Guest Control capability names such as `maintenance:update-shutdown:create`.
They must not read `runtime-observation.json.capabilities` as the current capability
source. Runtime-state documents do not carry capability state in v2.

Swift and Runtime Control HTTP adapters preserve the same client split.
`RuntimeControlClient` consumes product reads, Product Lab APIs, and Guest
service operations. Datastore repair uses a separate Guest-maintenance
operation client that returns the persisted Guest operation directly; it is not
a Host command response. Host maintenance commands such as proxy repair, VM
disk repair, runtime service repair, and Redis backup are exposed through
`RuntimeHostClient` so product clients do not look like service owners.

### 2-5. Runtime clients read Guest service state from its owner

`RuntimeStatus` is a Host/platform status contract and does not aggregate Guest service or product resource state. Runtime clients read `/runtime/stack` and the per-service resource endpoints directly. Those owner resources preserve `loaded`, `failed`, and `unavailable` as different meanings:

| State | Meaning |
|---|---|
| `loaded` | Guest Control API returned the service list and matching service status documents |
| `failed` | The Runtime owner read failed and its typed read error is preserved by that resource contract |
| `unavailable` | Guest service status was not read in this context |

The Swift and PWA presentations display Guest product service statuses separately from Host services. A failed Runtime owner read is shown as a failed read, not as an empty service list or a reconstructed `RuntimeStatus` field.

Runtime Control product payloads must not expose `containerObservation.composeServices`, `composeServicesReadState`, or `composeServicesReadError`. `runtime-observation.json` also no longer carries `containerServices` or `vitalDBObservation`; product service state and product read-model state must come from Guest Control API, Product APIs, and Guest/Postgres read models rather than Host-readable runtime-state files.

Host watchdog and recovery planning do not consume Guest product service status or controller resources. They use Runtime Control readiness only as a platform boundary signal and may recover the Host-owned VM/proxy boundary; Guest service reconciliation belongs to the Runtime Controller. Product clients still preserve missing, loaded, failed, and unavailable service reads through the direct Runtime owner resources.

Runtime health checks use Guest Control API `/ready` for Guest readiness. The
Host addresses Guest APIs through a typed Guest address provider. The product
path reads `GET /platform/runtime-endpoint`; bootstrap `vm-ip` evidence may
only publish an explicit owner mutation through
`PUT /platform/runtime-endpoint`. Runtime Control may use a loaded owner
address for API routing and display, but `vm-ip` file absence, inspection
failure, or decode/read failure must not create current health issues or failure
reasons or become a routing fallback. `runtime-observation.json.vmIP` is not a
fallback address source. When Guest Control readiness is not reported, current
Guest readiness is `notReported`; it is not reconstructed from runtime-state.
Guest runtime-state load, metadata, freshness, and disk-health reads remain
diagnostics evidence and must not create current health failure reasons.
`runtime-observation.json` remains diagnostics evidence, not the authority for current
Guest API readiness or Host proxy routing readiness.

Runtime status documents preserve the typed Guest address read result from the
health snapshot in addition to the compatibility `vmIP` field. `vmIP` remains a
display and legacy client field derived from a loaded address; missing, invalid,
stale, and read-failed address reads stay distinguishable through
`guestAddressRead`.

Guest Control API is the Guest-side control plane and must not be ordered after
the Docker Compose product stack. The `tirosh-vitalserver-guest-control-api`
systemd unit may depend on Docker and network readiness, but it must stay
independent from `tirosh-vitalserver-compose.service`. Otherwise a slow or
failed Compose startup can leave the Host with a VM IP but no `/ready` or
`/runtime/stack` endpoint, so Runtime Control can only report Guest Control
timeouts instead of observing or reconciling the stack.

Host watchdog must also complete the Host-owned VM lifecycle when the Guest
Control readiness probe and Host proxy probe are explicitly reachable. Guest
service observation can still be degraded or failed, but it must not keep
the Host VM lifecycle owner resource in `bootstrapping` once the Host can reach
the Guest control plane and proxy. Otherwise Status UI keeps showing a starting
or critical VM even though the installed runtime is already serving requests.

Host watchdog managed-operation guards also avoid Guest runtime-state reads.
The guard consumes the explicit Host operation lease only. It must not read
`runtime-observation.json.bootID`, `bootstrap-result.json`, or `runtime-status.json`
to decide whether watchdog recovery is blocked. VM lifecycle remains a
Host-owned health/recovery input, not an active-operation lock.

Guest bootstrap result remains boot proof and diagnostics evidence. Current
Host health does not read `guest-bootstrap-result.json` to create VM errors or
failure reasons; it consumes Guest Control readiness, Guest service status, and
Host-owned VM lifecycle state. A running bootstrap result must not participate
in the watchdog managed-operation guard and must not be compared against
`GuestRuntimeObservationDocument.bootID` for current health or recovery decisions.

Runtime Control status reads no longer read `runtime-observation.json` directly. The status reader uses the typed Guest address provider, not `runtime-status.json.vmIP`, to call Guest Control API. Runtime Control command execution uses the same Guest address provider when deriving a Guest Control base URL, unless the caller supplies an explicit override URL. It must not fall back to Guest runtime-state files or status snapshots for product service liveness, VM IP discovery, CPU, memory, disk status, or Guest API command routing. `RuntimeControlStatusAssembler` also does not accept a Guest runtime-state read input, so Host-readable runtime-state documents cannot be promoted into current RuntimeStatus resource fields through a test-only or alternate caller path.

Host managed service liveness has the same owner rule. Runtime Control current status reads do not read `runtime-status.json`; status documents are diagnostics/export artifacts only. Current `runtimeState` and `failureReasons` are assembled from explicit current owner reads, not from the status snapshot. VM, proxy, and watchdog service loaded/read-failed state must come from live Host service reads. HTTP probe state (`guestHTTP`, `hostProxyHTTP`, Redis UI, Swagger UI) is also filled from explicit probe reads, not from `runtime-status.json` snapshots. Current VM IP display comes from a loaded Guest address provider result, current VM state/errors come from the Host-owned VM lifecycle document read, current Host proxy port display/probe input comes from the proxy launch daemon/config read, runtime version comes from `runtime-version.json`, and latest backup comes from the managed backup directory read. The concrete Host file readers for those Host-owned inputs live behind `RuntimeHostStatusOwnerReaders`; `SystemRuntimeStatusReader` consumes the typed read models and must not reopen status/progress/install documents or raw owner files as fallback state. RuntimeStatus does not carry active operation, workflow progress, or status document read/decode diagnostics; those belong to PlatformOperationState, explicit operation-state/API owner contracts, and dedicated diagnostics/export paths. Presentation surfaces must not recreate operation messages or file diagnostics from legacy RuntimeStatus fields. Progress artifact absence or read/decode failure must not create current health issues. Proxy config/plist absence, read failure, or invalid port may leave `proxyPort` unavailable for display/probes, but it must not create current health issues or failure reasons. A stale or optimistic status document must not hide a launchd permission failure, missing service, current service stop, current probe failure, explicit API/owner Guest address unavailability, VM lifecycle read failure, runtime version read failure, or backup directory read failure.

Current Host status owner inputs are classified as follows:

| Input | Current owner role | File status | Next migration direction |
|---|---|---|---|
| Runtime endpoint | Platform-owned runtime/process address state | Host `runtime-state.sqlite.runtime_endpoint` is the durable owner and `GET`/`PUT /platform/runtime-endpoint` exposes that repository contract. `vitalserver-proxy-run` promotes loaded bootstrap `vm-ip` evidence through the SQLite owner and clears the same row when the proxy exits. Runtime lifecycle, health checker, command routing, and API consume `SQLiteRuntimeGuestAddressResourceStore` or the API resource; UI/API listener availability is not required for Host operation. Proxy readiness comes from direct HTTP probes, not `runtime-observation.json.guestHTTP`. Missing, invalid, and read/write failure remain distinct | Implement the same Platform endpoint owner contract in Windows Service and Linux systemd adapters; do not reintroduce endpoint JSON, `runtime-status.json.vmIP`, or `runtime-observation.json.vmIP` as current owners |
| Runtime Provider lifecycle | Platform-owned runtime/process state | `GET`/`PUT /platform/runtime-provider` is the API contract. `runtime-state.sqlite.vm_lifecycle` owns durable lifecycle state so the provider can publish before the UI/API process starts; controller, watchdog, VM launcher/delegate, and status/health readers consume `SQLiteRuntimeVMLifecycleResourceStore`. Missing, invalid, failed, and loaded stay distinct | Add richer provider reconciliation on top of this owner contract; do not use lifecycle JSON, `runtime-status.json`, or probe output as lifecycle state |
| Host proxy port | Host launchd/config owner input | `RuntimeHostProxyPortReader` reads the proxy launch daemon plist as the explicit Host config source for current `proxyPort` display and probe routing. Missing, unreadable, invalid, and out-of-range values are preserved in `proxyPortReadState`; they do not become current health failure reasons and they do not fall back to `RuntimeSettings` or `runtime-status.json.proxyPort` | Promote to a Host API owner resource only if proxy config becomes mutable controller state; until then keep it as a typed Host config read and do not hide config read failures with settings fallback |
| Runtime version | Applied package/runtime artifact | `runtime-version.json` is install/update artifact metadata, not health state | Keep as artifact read unless version ownership becomes a release registry API |
| Latest backup | Managed backup inventory | Backup directory scan is operational metadata; read failure is a read issue only | Keep as explicit inventory read or expose through a backup inventory API |
| Boot VM config / host time | Host-provided contract to VM/bootstrap | `vm-config.json` and host-time JSON are generated inputs owned by Host SQLite/config providers, not RuntimeStatus owner state. Applied settings remain in SQLite; `applied-vm-config.json` is diagnostics-only | Keep boot files as generated contracts; do not use them as settings or status fallback |

Watchdog active-operation suppression and Runtime Control active-operation display both avoid `runtime-status.json` as the current owner. Recovery is blocked only by the explicit Host operation lease exposed through PlatformOperationState. `runtime-progress.json` is a diagnostics/export artifact for workflow step detail, not a RuntimeStatus field. Status documents, progress documents, and bootstrap proof files may describe what was last published, but they must not act as the active-operation lock, recreate operation ownership, or provide health/recovery state from stale file state.

Guest-owned resource usage is published by Guest Control `GET /runtime/stack` and exposed to product clients as `GET /runtime/stack`. The stack status document carries explicit `cpuUsagePercent`, VM `memory`, VM `systemDisk`, and per-service container `memory` values. Helper Status UI consumes that owner resource directly; it must not infer VM or container resource usage from files, logs, container diagnostics fallback, missing fields, or `RuntimeStatus`. Per-service desired state, observed state, conditions, last operation, and read failures are read directly from `GET /runtime/services/{service}/resource`.

Guest Control observation endpoints must keep their own probe budgets smaller
than the Host read timeout. Required service-state reads may fail the endpoint
when the state owner cannot provide an explicit document. Optional resource
metrics must not consume the whole endpoint budget or block service-state
delivery. Container memory uses Docker inspect metadata plus container memory
cgroup files instead of waiting for `docker stats --no-stream`. Slow optional
probes return missing metric fields plus explicit `probeErrors`; they must not
turn a loaded stack status into an empty success or a Host-side timeout. The
operational budget rule is:

```text
Host Guest Control read timeout > Guest endpoint required read budget > optional probe budget
```

This relationship belongs in the Guest Control contract and tests. Operators
should not have to memorize every UI polling interval, watchdog interval, and
Guest probe timeout to decide whether a timeout is meaningful.

The Runtime-owned stack document preserves optional probe failures in its
`probeErrors` field. That field is diagnostics evidence for UI and API clients;
it is not a Host `RuntimeStatus` field and must not be promoted into Host
failure reasons or watchdog recovery plans when service statuses are loaded and
healthy.

Swift and PWA Status recorder-ingress queue and detail rows consume explicit `recorderIngressStatusRead` documents sourced from Guest Control API `GET /runtime/recorder-ingress/status`. `RuntimeStatus` does not publish `containerObservation`, so recorder-ingress display cannot fall back to the v1 container diagnostics payload.

The Host `runtime-status.json` document also does not carry
`containerObservation`. `RuntimeContainerObservation` is no longer a production
contract; recorder-ingress status remains explicit through its dedicated read
result contract, and runtime-state file metadata is not part of current health.
Missing or failed container observation reads also must not exist as typed Host
`RuntimeFailureReason` cases; legacy raw codes decode as unknown.

Host health failure and recovery planning policies do not accept Guest service, container, or VitalDB product observations as decision inputs. Those observations remain evidence for diagnostics, events, and product read-model surfaces, while product recovery belongs to the Runtime Controller.

Recorder activity windows consume Guest/Postgres read models through Guest Control API `GET /runtime/vitaldb/recorders/{vrcode}/activity`. Host SQLite activity buckets are transitional diagnostics only when a caller explicitly opts into diagnostics/migration projection mode; the live v2 path must not use Host SQLite to enrich Guest-owned recorder state. Host SQLite VitalDB projection reads live behind a dedicated diagnostics adapter, not inside the product observability reader or its product-facing initializer. Host status publishing also must not append VitalDB observations into the Host SQLite projection; Guest/Postgres owns the product read-model write path.

The Host diagnostics projection adapter collects explicit projection reads only. It must not assemble product read models or become a fallback source of current product state; Contracts assemblers remain responsible for turning explicit reads into presentation/API read models.

VitalDB observation reads may still appear in Host health snapshots and runtime events as explicit evidence. They must not create Host runtime failure reasons, watchdog recovery blockers, typed `RuntimeFailureReason` observation missing/read-failed/stale cases, a `runtime-status.json` contract field/current state, or a `RuntimeStatus.vitalDBObservation` product status field. Guest service and VitalDB state both belong to Runtime/Product owner surfaces and are not Host recovery authority.

### 2-6. Product Lab has a first-class API namespace

Runtime v2 treats virtual recorder scenarios and `.vital` replay as Product Lab capability, not as a dev-only TestKit concern. Runtime Control API now reserves `/runtime/lab/*` for product-facing Lab contracts:

```text
GET  /runtime/lab/scenarios
GET  /runtime/lab/sessions
POST /runtime/lab/sessions
GET  /runtime/lab/sessions/{sessionId}
POST /runtime/lab/sessions/{sessionId}/start
POST /runtime/lab/sessions/{sessionId}/stop
POST /runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start
POST /runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop
GET  /runtime/lab/beds
POST /runtime/lab/beds/create
POST /runtime/lab/recorders/create
GET  /runtime/lab/recorders
POST /runtime/lab/vital-files/replay
POST /runtime/lab/vital-files/upload
```

The Host contract explicitly returns `unavailable` when Guest Control or Product Lab is not reachable. Missing Lab backend, failed Lab reads, and empty scenario lists must remain different meanings.

### 2-7. Guest Control API mediates Product Lab execution

Runtime v2 routes Product Lab execution through Guest Control API. Host Runtime Control clients call `/runtime/lab/*`, the Host adapter calls Guest Control `/runtime/lab/*`, and the Guest adapter talks to the Product Lab service API as the implementation boundary. Vital Files import is the exception: it is a storage operation owned by the Runtime Control/Guest library adapter and is not forwarded to Product Lab as an execution command.

Guest Product Lab endpoints:

```text
GET  /runtime/lab/scenarios
GET  /runtime/lab/sessions
POST /runtime/lab/sessions
GET  /runtime/lab/sessions/{sessionId}
POST /runtime/lab/sessions/{sessionId}/start
POST /runtime/lab/sessions/{sessionId}/stop
POST /runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start
POST /runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop
GET  /runtime/lab/beds
POST /runtime/lab/beds/create
POST /runtime/lab/recorders/create
GET  /runtime/lab/recorders
POST /runtime/lab/vital-files/replay
POST /runtime/lab/vital-files/upload
```

Command-style Product Lab requests create persisted Guest Control operations using the
same SQLite control ledger as service restart. Lab operation failures are saved
as failed operations and returned through the Lab response `readError` instead
of being converted into an empty scenario list or a successful stopped session.
The multipart Vital Files import validates and commits one explicit batch through
the configured library adapter; it does not create a Product Lab operation or
send the files to VitalServer `/upload`.

The current Guest adapter maps these Product Lab commands to the `lab` service API:

| Product Lab operation | Guest adapter target |
|---|---|
| Scenario list | `GET http://lab:8080/lab/scenarios` |
| Bed read model | `GET http://lab:8080/lab/beds` |
| Recorder read model | `GET http://lab:8080/lab/recorders` |
| Session collection | `GET http://lab:8080/lab/sessions` |
| Create session | `POST http://lab:8080/lab/sessions` |
| Read session | `GET http://lab:8080/lab/sessions/{sessionId}` |
| Start session | `POST http://lab:8080/lab/sessions/{sessionId}/start` |
| Stop session | `POST http://lab:8080/lab/sessions/{sessionId}/stop` |
| Delete session aggregate | `POST http://lab:8080/lab/sessions/{sessionId}/delete` |
| Start recorder | `POST http://lab:8080/lab/sessions/{sessionId}/recorders/{recorderId}/start` |
| Stop recorder | `POST http://lab:8080/lab/sessions/{sessionId}/recorders/{recorderId}/stop` |
| `.vital` replay | `POST http://lab:8080/lab/vital-files/replay` |

This makes Product Lab the product boundary and removes the TestKit adapter from the Guest Control Lab execution path.

`POST /runtime/lab/vital-files/upload` accepts repeated multipart `files` fields.
Every filename must be a basename ending in `.vital`; an empty batch, duplicate
name, invalid extension, missing library, or destination conflict fails the whole
batch. The adapter validates every entry before staging and only then commits all
files. It never treats a partially imported batch as success.

Product Lab session creation does not infer ownership from existing beds,
recorders, fixture names, or previous command output. A session that should
occupy existing Lab resources must pass explicit `bedIds` in
`RuntimeLabSessionCreateRequest`. The Lab service validates those bed IDs
against its Lab-owned bed read model, carries those bed IDs on the session
response, and updates the matching Lab bed/recorder read model rows to the
session state. When no `bedIds` are provided, session creation creates a new
session-scoped Lab read model from `recorderCount` and optional
`bedRoomNames`.

The regular VitalDB Bed and Recorder tabs continue to display Guest/Postgres
VitalDB observation state. Helper also surfaces Product Lab beds and
recorders separately so Lab-managed virtual resources are visible without
pretending they are VitalDB-observed resources before the upstream product
read model reports them. Product Lab bed rows are selectable in SwiftUI and the
common PWA; their detail renders only the Lab-owned `RuntimeLabBed` fields
(`name`, `bedId`, `sessionId`, `state`, `createdAt`, `updatedAt`) and does not
infer VitalDB relationship, patient, or recorder state.

The Lab presentation does not keep the just-created session only in client memory. SwiftUI and the common PWA read the persisted session collection, select a session explicitly, then read its detail. Whole-session Start/Stop and per-recorder Start/Stop are separate commands. A recorder command is available only when the selected session is explicitly `running` and the recorder read model explicitly names that session. Refresh/read failure remains visible and does not become an empty session list or a locally reconstructed session.

VitalDB Recorder and Bed product reads are separate contracts. `/runtime/vitaldb/recorders`
returns recorder history and recorder-linked summary fields; `/runtime/vitaldb/beds`
returns `RuntimeVitalBedHistory` from the Guest/Postgres bed read document.
The Beds tab must consume the Bed document directly, not slice `beds` out of
recorder history. Bed hide/unhide/delete commands return the refreshed Bed
history so recorder read failures cannot mask a successful Bed state change.
Permanent delete plans Lab cleanup only when the selected VitalDB row carries
the explicit `vitalserver-lab` recorder version. Guest Control resolves its
owning session from the Product Lab recorder contract, stops that session's
execution, deletes the session with all owned beds and recorders, and only then
commits the VitalDB visibility tombstone. An unavailable or invalid Product Lab
contract fails the delete; it is never treated as an empty Lab collection or a
successful cleanup. A successful Product Lab read with no matching vrcode is
an explicit already-absent cleanup result, which keeps repeated child deletes
idempotent. Deleted entities are also excluded from recorder activity and
relationship read models, while the tombstone remains to prevent a producer
from silently recreating visible state.
The Swift Helper ViewModel keeps `vitalBeds` as a distinct published read
result; Recorder panels may link to beds for display, but they must read those
links from the Bed read result rather than the Recorder history payload.

CLI automation uses the same boundary. `vitalserver-vm runtime lab-*` commands call Guest Control `/runtime/lab/*` and print the returned Product Lab contracts as JSON. The Host CLI must not read Lab fixture files, TestKit state files, or container-local process state to infer session state.

Swift Helper navigation now treats Lab as a primary product section. Observability and Logs move toward diagnostics/More surfaces, while Lab scenario creation, session control, and `.vital` replay use the Runtime Control Product Lab client contract instead of direct TestKit container calls.

Product Lab `.vital` replay preserves the selected mounted file path as private
session execution input inside the Lab-owned store. Public Lab session responses
must not echo the path, but the stored execution input must survive a later
session start so replay requests do not degrade into generic generated
scenarios.

The Lab service only accepts absolute `.vital` paths under its configured
`VITALSERVER_LAB_VITAL_FILES_MOUNT` directory. Missing files, paths outside the
mount, and invalid extensions are separate request failures. This keeps Host file
selection, Guest mount configuration, and Product Lab replay execution aligned
without letting Lab infer or scan private host data.

## 3. v1 File Boundary Demotion

### 3-1. Runtime smoke proves operation persistence

Runtime boot smoke now uses Guest Control API for product service proof. The `compose-services` stage reads `GET /runtime/stack` instead of `runtime-observation.json.containerServices`, and the `guest-control-api` stage checks Guest Control API readiness, capabilities, service listing, `app` status, `app` restart, stack reconcile, `/runtime/operations/{operationId}` readback, Product Lab scenarios, Product Lab session create/start/stop operations, and Product Lab `.vital` replay request acceptance as part of the product runtime proof.

### 3-2. Runtime files are no longer the service control boundary

Runtime files remain valid for bootstrap, host proxy discovery, health evidence, diagnostics, and export artifacts. They must not become the primary product service control/status boundary in Runtime v2.

| Runtime concern | v2 owner | File role |
|---|---|---|
| Product service list/status | Guest Control API | diagnostic evidence only |
| Product service restart operation | Guest Control API + SQLite control ledger | none |
| Product Lab scenarios/sessions | Guest Control API + Lab service | none |
| Guest stack reconcile operation | Guest Control API + SQLite control ledger | none |
| VM boot discovery | Guest bootstrap address writer | `vm-ip` compatibility file, then typed address provider |
| Host nginx proxy target | Host proxy consuming Guest address plus direct HTTP probes | explicit discovery input and probe evidence |
| Health proof evidence | Runtime smoke/status readers | explicit evidence with read state/error |

### 3-3. Runtime v2 review and acceptance proof

Runtime v2 completion is proven through explicit Make targets. The fast review
gate is:

```text
make runtime/proof/review
```

This target runs `runtime/proof/no-v1-service-state`,
`runtime/proof/python-focused`, `pwa/check`, `pwa/test`, and `pwa/build`. It proves
the static v1 file-boundary cleanup, the Product Lab and Guest Control
Postgres-backed Python test set, and the Runtime Control PWA generated contract,
typecheck, test, and build gates.

The final acceptance gate is:

```text
make runtime/proof/acceptance
```

This target extends the review gate with `runtime/proof/swift-focused`,
`runtime/proof/http-e2e`, and `runtime/proof/smoke`. Runtime v2 is not complete until the final acceptance gate passes.
The final gate must run in an environment that can run SwiftPM and Docker/VM
smoke without sandbox, credential-helper, or network restrictions.

The focused Python proof is:

```text
make runtime/proof/python-focused
```

This target runs Product Lab, Guest Control API/usecase/domain, Guest Control
Postgres repository, Product Lab adapter, recorder-ingress adapter, Redis
maintenance adapter, devtools packaging/release manifest, rootfs, and runtime
lifecycle wait tests.

The focused Swift proof is:

```text
make runtime/proof/swift-focused
```

This target runs the Host-side Runtime v2 contract, Guest Control gateway,
health, and runtime status reader tests selected by
`VM_RUNTIME_PROOF_SWIFT_FOCUSED_FILTER`.

The Runtime Control HTTP E2E proof is:

```text
make runtime/proof/http-e2e
```

This target aliases `runtime/e2e/smoke` and proves the local Runtime Control
HTTP server can serve the core read endpoints over loopback.

The remaining acceptance proof is an end-to-end VM smoke run. `make runtime/proof/smoke` runs the dev golden runtime boot smoke so the test-enabled runtime proves Guest Control API readiness, service readback, restart operation persistence, Product Lab scenario/session operation acceptance, Runtime Control API exposure, and Swift/PWA-facing status read model behavior in the packaged runtime.

`make runtime/proof/no-v1-service-state` is the fast static cleanup proof. It checks that Host product service liveness and command routing use Guest Control API through explicit Guest address reads instead of `runtime-status.json.vmIP`, Runtime Control current runtimeState, failureReasons, VM IP, VM lifecycle state/errors, Host proxy port, runtime version, and latest backup use explicit owner reads instead of `runtime-status.json` snapshots, Runtime Control current status does not read `runtime-status.json`, active operation, progress, and status document diagnostics are absent from RuntimeStatus and Swift/PWA presentation consumers, progress document, Guest address, and proxy config failures do not become current status issues, Host managed service liveness and current HTTP probe state use explicit live reads instead of `runtime-status.json`, watchdog active-operation suppression uses operation leases only instead of `runtime-status.json`, `runtime-observation.json`, or `bootstrap-result.json`, Host runtime health does not consume `bootstrap-result.json` as current health state, `RuntimeContainerObservation` is not a production contract, `runtime-observation.json` no longer carries container service state, VitalDB observation state, or capability state, Host no longer keeps `RuntimeGuestRuntimeStatePolicy` or runtime-state freshness observation as a runtime-state guestHTTP/vmIP promotion path, host proxy does not read `runtime-observation.json` for routing readiness and uses explicit Guest address owner reads plus direct HTTP probes, devtools runtime wait reads the `vm-ip` bootstrap address and direct HTTP probes instead of `runtime-observation.json.vmIP` or `runtime-observation.json.guestHTTP`, dev `runtime/proxy/start` derives upstream from Runtime Control Guest address owner instead of reading `vm-ip` directly, `runtime-status.json` no longer carries container diagnostics evidence or a VitalDB observation contract field, `RuntimeStatus` no longer carries legacy VitalDB observation state, runtime boot smoke validates product services through Guest Control stack status, Redis backup has no request/result file bridge, `/dev/testkit` product surfaces are absent, runtime config no longer carries TestKit enablement, product packaging includes Lab and excludes TestKit runtime artifacts, VitalDB read-model contracts do not name Host SQLite as a product source, VitalDB Beds consume explicit Guest/Postgres Bed history documents instead of slicing recorder history, Host SQLite VitalDB projection reads require explicit diagnostics mode behind a dedicated diagnostics adapter, Host status publishing does not write VitalDB observations into Host SQLite, Host runtime health does not promote VitalDB read-model failures into recovery reasons, Host recorder-ingress status reads go through Guest Control API only, and whole-stack start/stop plus Host maintenance commands are absent from the product `RuntimeControlClient` and product client callers. It also checks that whole-stack start/stop is absent from Runtime Control HTTP, PWA, and Swift product presentation surfaces, that runtime-data backup/restore plus update activation/shutdown consume Guest Control maintenance API instead of request/result files, that shared Host/Guest contracts no longer publish legacy `*.request` or `*-result.json` filenames, and that Swift production source no longer carries legacy guest result document contracts or polling evaluators.

The same proof also checks that Guest maintenance capability preflight reads
come from Guest Control `GET /runtime/capabilities`. Capability checks must preserve
capability read failure separately from a loaded-but-missing capability, and
they must not use `GuestRuntimeObservationDocument.capabilities` as the current
maintenance capability source.

Redis backup no longer has a request/result file bridge in the Guest diagnostics artifact writer or Redis backup usecase. Product service operations, product read models, and Redis backup maintenance operations must go through Guest Control API and its persisted operation documents.

### 3-4. API catalog is a support surface, not a state source

Runtime v2 keeps the Swagger/API catalog as an operator support surface under
Advanced/More. It must not become a product service-state source, a replacement
for Guest Control reads, or a way to expose legacy TestKit runtime routes.

The packaged Swagger UI catalog exposes only public or support-facing specs:

```text
VitalServer API -> /swagger/docs/openapi.yaml
Runtime Control API -> /swagger/docs/macos-runtime/runtime-control.openapi.json
Recorder Ingress API -> /swagger/docs/openapi/recorder-ingress.openapi.yaml
VitalDB Observer API -> /swagger/docs/openapi/vitaldb-observer.openapi.yaml
```

Guest Control API and Product Lab service remain implementation boundaries
consumed through Runtime Control `/runtime/guest/*`, `/runtime/lab/*`, and `/runtime/vitaldb/*`
contracts. Until those internal services publish explicit support OpenAPI
documents, the API catalog must not invent direct Swagger entries for them.

`make runtime/proof/no-v1-service-state` checks that the guest Swagger catalog,
PWA Advanced API catalog, and Swift Advanced API catalog expose the same v2
support specs and do not reintroduce `/dev/testkit` or TestKit API catalog
entries.

### 3-5. Redis backup has a Guest Control maintenance operation API

Runtime v2 now exposes Redis backup and restore through Guest Control API as
maintenance operations:

```text
POST /runtime/maintenance/redis-backup
POST /runtime/maintenance/redis-restore
POST /runtime/maintenance/datastore/repair
POST /runtime/maintenance/update-activation
POST /runtime/maintenance/update-shutdown
GET  /runtime/operations/{operationId}
```

The Redis backup API creates a persisted Guest Control operation with command
`redis-backup`. On success, the completed operation stores an explicit
`result.archive` path in the SQLite-backed control operation document. On failure,
the operation stores a typed failure from the Redis backup adapter. Host clients
must read this operation contract instead of polling Redis backup result files
for the v2 maintenance path.

The Redis restore API accepts an explicit `archive` field and creates a
persisted Guest Control operation with command `redis-restore`. On success, the
completed operation stores `result.restoredArchive`. On failure, missing
archives, unsafe archive paths, invalid archive members, and Docker/volume
dependency failures are recorded as typed operation failures. The legacy
`redis-restore.request` / `redis-restore-result.json` contract and no-argument
restore systemd service are removed; CLI restore requires an explicit
`--archive` argument.

The legacy Redis backup request/result file contract has been removed from the
Guest Redis backup usecase and diagnostics artifact writer. Redis backup execution
returns an explicit archive outcome to the Guest Control maintenance adapter,
and Host clients consume the persisted Guest Control operation result instead
of observing `redis-backup.request` or `redis-backup-result.json`.

The datastore repair API creates a persisted Guest Control operation with
command `repair-datastore`. The Guest adapter executes the Redis append-only
file repair and compose restart path directly. The legacy
`repair-datastore.request` / `repair-datastore-result.json` contract and
datastore repair systemd service are removed, so stale repair request files
cannot trigger compose restart. Failures are recorded as typed Guest operation
failures.

The Runtime Control HTTP boundary forwards that operation unchanged from
`POST /runtime/maintenance/datastore/repair` as `202 Accepted`. Its body is a
`RuntimeGuestControlServiceOperation`, not a `RuntimeControlCommandResponse`:
the persisted operation id, `repair-datastore` command, current state, and any
typed failure remain visible to the caller. A terminal failed operation is
still a `202` operation response, not converted into Host stdout/stderr or an
empty success. The common PWA may offer this action only after the Guest
advertises `maintenance:datastore-repair:create`; otherwise it displays the
Guest maintenance capability as unavailable and does not issue the request.

The update activation API creates a persisted Guest Control operation with
command `activate-update`. The request body must include explicit `requestId`
and `version` fields, and the Guest adapter runs the existing activation path
directly. The legacy `activate-update.request` /
`activate-update-result.json` contract and activation systemd service are
removed, so stale activation request files cannot recreate the stack.

Host update activation consumes the same Guest Control maintenance API.
`RuntimeGuestActivationComposition` starts the VM when needed, calls
`activateUpdateThroughGuestControl(requestID:version:)`, and logs the returned
Guest operation id. The activation composition no longer writes
`activate-update.request` or polls `activate-update-result.json` as its primary
path.

The Host file gateway no longer exposes update activation request/result
methods. Guest Control API is the update activation command boundary; old
`activate-update.request` artifacts are older-install evidence, not a v2
runtime contract.

### 3-6. Host Redis backup create and restore consume Guest Control API

Host Runtime Control no longer creates or restores Redis backups by launching
`vitalserver-vm runtime redis-backup` or `vitalserver-vm runtime redis-restore`
from the Swift control worker. The Swift command worker now resolves the Guest
Control base URL, calls the Guest maintenance endpoint, validates the returned
Guest operation through `RuntimeGuestMaintenanceControlUseCase`, and maps the
completed operation into the existing `RuntimeCommandResult` response shape for
Runtime Control API and PWA compatibility.

The CLI commands `vitalserver-vm runtime redis-backup` and
`vitalserver-vm runtime redis-restore <archive.tar.gz>` also consume the Guest
Control maintenance API. Restore still stages a host-selected archive into the
shared data directory because Guest must receive a path under `/mnt/tirosh`, but
the restore execution and operation state now come from Guest Control API
instead of the Redis restore request/result file pair.

This keeps the UI/API command surface stable while moving the control-state
owner to the Guest SQLite ledger. `RuntimeGuestControlServiceOperation` now carries an optional
`result` contract so Redis backup `result.archive` and Redis restore
`result.restoredArchive` are preserved when Host reads or returns the operation.

Runtime-data backup and restore now use the same Guest Control maintenance API
for Redis archive creation and restore execution. Host still owns local backup
manifest assembly, host file copying, start-on-boot state capture, and
host-selected archive staging, but Redis operation state comes from Guest
SQLite control documents rather than Redis backup/restore
request/result files.

Swift Runtime Control's datastore-repair HTTP path consumes the Guest Control
maintenance API through the dedicated Guest-maintenance operation boundary and
returns the Guest operation document unchanged with `202 Accepted`. CLI
`repair-datastore` also consumes the same Guest operation, then performs the
Host-owned proxy/watchdog restart and health aftercare without writing or
polling datastore repair request/result files. That CLI aftercare does not
change the HTTP operation owner or its response shape.

Update shutdown now uses a two-step Guest Control maintenance API. First,
`POST /runtime/maintenance/update-shutdown` accepts explicit `requestId` and
`version`, persists `accepted` and `running`, starts the Guest shutdown
preparation in a background thread, and persists a completed operation when the
Guest reaches `poweroff-ready`. The result preserves
`shutdownPhase=poweroff-ready` and the Redis backup archive path when available.
Second, Host calls `POST /runtime/maintenance/guest-poweroff` after it has read the
completed `poweroff-ready` operation.

Host update shutdown consumes this API as its primary path. The Swift shutdown
workflow no longer writes `prepare-update-shutdown.request` or polls
`prepare-update-shutdown-result.json`; it starts the Guest operation, polls
`GET /runtime/operations/{operationId}` until `poweroff-ready`, then explicitly
requests Guest poweroff. Host still owns VM process observation and post-poweroff
service stop.

The Host file gateway no longer exposes update shutdown request/result cleanup
or polling methods, and the Guest request-file poller no longer dispatches
`prepare-update-shutdown.request`. Guest Control API owns the shutdown
operation state, while Host owns VM process observation and host service stop.

The Guest shutdown application no longer reads
`prepare-update-shutdown.request` or writes
`prepare-update-shutdown-result.json`. The no-argument
`tirosh-vitalserver-prepare-update-shutdown.service` is removed from Guest
packaging. Direct CLI execution remains available only with explicit
`--request-id` and `--version` arguments, so shutdown preparation cannot be
triggered by a stale file.

The remaining Guest command request-file poller has been removed from the v2
runtime. Host-visible Guest document readers no longer expose bootstrap-result
or runtime-state files as product state gateways. Runtime-state file metadata
and bootstrap-result documents can remain as diagnostics/export evidence, but
they are not Guest state contracts. Datastore repair, Redis restore, update
activation, and update shutdown use Guest Control maintenance operations as
their command and operation-state boundary.

Current Host health names this input as Guest readiness, not Guest runtime-state.
`RuntimeGuestReadinessInput` is built from Guest Control `/ready`; runtime-state
missing, stale, invalid, and decoded payload fields are not current health input.
Runtime Control `RuntimeStatus` also no longer exposes `guestRuntimeStateError`;
current read failures surface through explicit status/read issues, Guest
Control readiness, Guest service status, VM errors, or failure reasons.

Swift Guest readiness presentation follows the same boundary. It does not treat
legacy runtime-state stale or missing signals as initial Guest readiness waiting
state. Legacy runtime-state errors can still be rendered as decoded failure
evidence, but Guest readiness waiting presentation is driven by Guest Control
readiness and missing VM IP state only.

Current health evaluation also filters legacy runtime-state VM errors. Older
`vm-runtime-state-*`, `guest-runtime-state-*`, and `guest-bootstrap-result-*`
raw strings decode as `unknown(raw)` diagnostics for older status/event
evidence, but they do not exist as explicit product error cases and do not
become live `vmErrors`, failure reasons, VM state, or watchdog recovery inputs.

Current health read contracts also no longer carry `runtime-observation.json` file
metadata or bootstrap-result proof state. Host does not read runtime-state mtime
or bootstrap-result documents as health inputs. Those files may remain as
diagnostics/export evidence, but live Host health uses Guest Control readiness, VM
lifecycle, and Guest service status contracts.

Uninstall, VM disk repair, proxy repair, and remaining non-datastore
maintenance flows are platform-specific maintenance extensions until their
workflows are moved behind explicit Guest APIs. They may still use explicit
platform/native workflows where supported, but they are not common PWA actions
and must not be used as product service/read-model state.

Guest Control API production composition opens the required SQLite control
ledger before serving requests. The ledger implements separate application
ports for service operations, service-status snapshots, GuestService controller
resources, and Redis relay status, even though those documents share one
SQLite database file. That separation keeps desired state, observed status,
conditions, and operation history distinct without making Postgres a hidden
control-plane dependency. Missing database files, an unknown schema revision,
permission errors, decode errors, and a busy writer remain typed failures;
there is no in-memory fallback.

The Guest compose stack includes `postgres` with `postgres-data`, and the
product `lab` service is configured to use the Postgres session store. Host must
continue to consume Lab, service operation, and read-model state through
Guest/Product APIs instead of reading Postgres directly.

Guest service operations persist service status snapshots through the service
status snapshot repository after successful `start`, `stop`, `restart`, and `reconcile`
commands. A post-command status read failure is persisted as a failed operation,
because v2 operation completion requires Guest to produce the explicit service
state contract instead of leaving Host to infer service state from files,
compose diagnostics, or a later poll.

`recorder-ingress` must not use `runtime-observation.json` as a replay-control input.
The v1 runtime-state memory guard read `containerServices`, but v2
runtime-state no longer carries product service/container state. Until an
explicit Guest/Product resource API exists, recorder-ingress replay adaptive
memory guard is disabled by default and the product service does not mount
`/run/tirosh/runtime`.
