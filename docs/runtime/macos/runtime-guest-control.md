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
GET  /v1/capabilities
GET  /v1/services
GET  /v1/services/{service}/status
POST /v1/services/{service}/start
POST /v1/services/{service}/stop
POST /v1/services/{service}/restart
POST /v1/stack/reconcile
GET  /v1/operations/{operationId}
```

## 2. Current Implementation

### 2-1. Service operations are explicit domain state

Service operations now have explicit domain states. `accepted`, `running`, `completed`, `failed`, and `cancelled` are different meanings and must not be collapsed into success, empty, or unknown.

### 2-2. Compose access is behind an outbound adapter

Docker Compose commands are isolated behind the Guest Control Compose adapter. Domain and application code must not parse Compose output or execute Compose directly.

### 2-3. Operation state is persisted in Postgres

Guest Control API persists service operation state through the `postgres` Compose service. The current adapter uses `docker compose exec -T postgres psql` so the Guest tool package does not need an additional Python database wheel in the airgap bundle.

### 2-4. Host exposes Guest service control through the v2 API path

Host now has a Guest Control API consumer boundary for product service start, stop, and restart. The Swift contract preserves the Guest operation document instead of converting it into a shell command result.

Host-facing entry points:

```text
GET  /runtime/guest/services
GET  /runtime/guest/services/{service}/status
POST /runtime/guest/services/start
POST /runtime/guest/services/stop
POST /runtime/guest/services/restart
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

Runtime Control capabilities preserve the same ownership split.
`canControlRuntimeServices` is the Host maintenance capability for settings,
recovery, backup/restore, and VM/proxy/watchdog lifecycle work.
`canControlGuestServices` is the product service control capability for Guest
Control start/stop/restart operations.

Guest maintenance capability checks also consume Guest Control API directly.
Host update, Redis backup/restore, and datastore repair preflight checks read
`GET /v1/capabilities` and map `RuntimeGuestCapabilityRequirement` to explicit
Guest Control capability names such as `maintenance:update-shutdown:create`.
They must not read `runtime-state.json.capabilities` as the current capability
source. Runtime-state documents do not carry capability state in v2.

Swift and Runtime Control HTTP adapters preserve the same client split.
`RuntimeControlClient` consumes product reads, Product Lab APIs, and Guest
service operations. Host maintenance commands such as proxy repair, datastore
repair, VM disk repair, runtime service repair, and Redis backup are exposed
through `RuntimeHostClient` so product clients do not look like service owners.

### 2-5. Runtime status preserves Guest service read state

Runtime status assembly now consumes Guest Control API service reads. `loaded`, `failed`, and `unavailable` are preserved as different states:

| State | Meaning |
|---|---|
| `loaded` | Guest Control API returned the service list and matching service status documents |
| `failed` | Guest Control API was expected but the read failed; the error is preserved in `guestServicesReadError` |
| `unavailable` | Guest service status was not read in this context |

The Swift advanced service health presentation displays Guest product service statuses separately from Host launchd services and legacy VM diagnostics. A failed Guest Control read is shown as a failed read, not as an empty service list.

Runtime Control product payloads must not expose `containerObservation.composeServices`, `composeServicesReadState`, or `composeServicesReadError`. `runtime-state.json` also no longer carries `containerServices` or `vitalDBObservation`; product service state and product read-model state must come from Guest Control API, Product APIs, and Guest/Postgres read models rather than Host-readable runtime-state files.

Runtime watchdog and recovery planning also consume explicit Guest Control service status. Guest service failures produce Guest-owned service failure reasons and plan Guest stack reconcile through the Guest Control API. Guest service status reads must remain explicit when they are missing, loaded, failed, or unavailable.

Runtime health checks use Guest Control API `/ready` for Guest readiness. The
Host addresses Guest APIs through a typed Guest address provider. During the
compatibility window that provider reads the `vm-ip` bootstrap discovery file,
but it preserves loaded, missing, invalid, stale, and read-failed states instead
of collapsing failures to a missing address. `runtime-state.json.vmIP` is not a
fallback address source. When Guest Control readiness is not reported, current
Guest readiness is `notReported`; it is not reconstructed from runtime-state.
Guest runtime-state load, metadata, freshness, and disk-health reads remain
diagnostics evidence and must not create current health failure reasons.
`runtime-state.json` remains bootstrap readiness and diagnostics evidence, not
the authority for current Guest API readiness.

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
`/v1/stack/status` endpoint, so Runtime Control can only report Guest Control
timeouts instead of observing or reconciling the stack.

Host watchdog must also complete the Host-owned VM lifecycle when the Guest
Control readiness probe and Host proxy probe are explicitly reachable. Guest
service observation can still be degraded or failed, but it must not keep
`vm-lifecycle.json` in `bootstrapping` once the Host can reach the Guest
control plane and proxy. Otherwise Status UI keeps showing a starting or
critical VM even though the installed runtime is already serving requests.

Host watchdog managed-operation guards also avoid Guest runtime-state reads.
The guard may compare a running bootstrap result with the Host-owned VM
lifecycle `bootID`, but it must not read `runtime-state.json.bootID` to decide
whether watchdog recovery is blocked. Bootstrap result, operation lease, and VM
lifecycle documents are the explicit guard contracts for this Host decision.

Guest bootstrap failure evaluation uses the same boot identity boundary. A
failed `guest-bootstrap-result.json` belongs to the current boot only when its
`bootID` matches `RuntimeVMLifecycleDocument.bootID`; if the lifecycle boot id
is not available, the evaluator falls back to the explicit freshness window.
It must not compare against `GuestRuntimeStateDocument.bootID` for current
health or recovery decisions.

Runtime Control status reads no longer read `runtime-state.json` directly. The status reader may use the explicit VM IP already published in `runtime-status.json` to call Guest Control API, but it must not fall back to Guest runtime-state files for product service liveness, VM IP discovery, CPU, memory, or disk status. `RuntimeControlStatusAssembler` also does not accept a Guest runtime-state read input, so Host-readable runtime-state documents cannot be promoted into current RuntimeStatus resource fields through a test-only or alternate caller path.

Guest-owned resource usage is published by Guest Control `GET /v1/stack/status`. The stack status document carries explicit `cpuUsagePercent`, VM `memory`, VM `systemDisk`, and per-service container `memory` values. Helper Status UI consumes those fields as a service consumer; it must not infer VM or container resource usage from files, logs, container diagnostics fallback, or missing fields. Runtime Control status also reads GuestService controller resources through Guest Control `GET /v1/services/{service}/resource`, preserving desired state, observed state, conditions, and per-service resource read issues in `RuntimeStatus`.

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

RuntimeStatus preserves loaded stack-status optional probe failures as
`guestStackProbeErrors`. That field is diagnostics evidence for UI and API
clients. It is not `guestServicesReadError`, and it must not create runtime
failure reasons or watchdog recovery plans when service statuses are loaded and
healthy.

Swift and PWA Status recorder-ingress queue and detail rows consume explicit `recorderIngressStatusRead` documents sourced from Guest Control API `GET /v1/recorder-ingress/status`. `RuntimeStatus` does not publish `containerObservation`, so recorder-ingress display cannot fall back to the v1 container diagnostics payload.

The Host `runtime-status.json` document also does not carry
`containerObservation`. `RuntimeContainerObservation` is no longer a production
contract; recorder-ingress status remains explicit through its dedicated read
result contract, and runtime-state file metadata is not part of current health.
Missing or failed container observation reads also must not exist as typed Host
`RuntimeFailureReason` cases; legacy raw codes decode as unknown.

Health failure and recovery planning policies do not accept container or VitalDB diagnostics observations as decision inputs. Guest service status is the only product-service observation that can create service failure reasons or Guest stack reconcile decisions; container and VitalDB observations remain evidence for diagnostics, events, and product read-model surfaces.

Recorder activity windows consume Guest/Postgres read models through Guest Control API `GET /v1/vitaldb/recorders/{vrcode}/activity`. Host SQLite activity buckets are transitional diagnostics only when a caller explicitly opts into diagnostics/migration projection mode; the live v2 path must not use Host SQLite to enrich Guest-owned recorder state. Host SQLite VitalDB projection reads live behind a dedicated diagnostics adapter, not inside the product observability reader or its product-facing initializer. Host status publishing also must not append VitalDB observations into the Host SQLite projection; Guest/Postgres owns the product read-model write path.

The Host diagnostics projection adapter collects explicit projection reads only. It must not assemble product read models or become a fallback source of current product state; Contracts assemblers remain responsible for turning explicit reads into presentation/API read models.

VitalDB observation reads may still appear in Host health snapshots and runtime events as explicit evidence. They must not create Host runtime failure reasons, watchdog recovery blockers, typed `RuntimeFailureReason` observation missing/read-failed/stale cases, a `runtime-status.json` contract field/current state, or a `RuntimeStatus.vitalDBObservation` product status field. Guest service status is the Host recovery authority for product service liveness; VitalDB observation state belongs to Guest/Product read-model surfaces.

### 2-6. Product Lab has a first-class API namespace

Runtime v2 treats virtual recorder scenarios and `.vital` replay as Product Lab capability, not as a dev-only TestKit concern. Runtime Control API now reserves `/lab/*` for product-facing Lab contracts:

```text
GET  /lab/scenarios
POST /lab/sessions
GET  /lab/sessions/{sessionId}
POST /lab/sessions/{sessionId}/start
POST /lab/sessions/{sessionId}/stop
GET  /lab/beds
POST /lab/beds/create
POST /lab/recorders/create
GET  /lab/recorders
POST /lab/vital-files/replay
POST /lab/vital-files/upload
```

The Host contract explicitly returns `unavailable` when Guest Control or Product Lab is not reachable. Missing Lab backend, failed Lab reads, and empty scenario lists must remain different meanings.

### 2-7. Guest Control API mediates Product Lab execution

Runtime v2 routes Product Lab execution through Guest Control API. Host Runtime Control clients call `/lab/*`, the Host adapter calls Guest Control `/v1/lab/*`, and the Guest adapter talks to the Product Lab service API as the implementation boundary.

Guest Product Lab endpoints:

```text
GET  /v1/lab/scenarios
POST /v1/lab/sessions
GET  /v1/lab/sessions/{sessionId}
POST /v1/lab/sessions/{sessionId}/start
POST /v1/lab/sessions/{sessionId}/stop
GET  /v1/lab/beds
POST /v1/lab/beds/create
POST /v1/lab/recorders/create
GET  /v1/lab/recorders
POST /v1/lab/vital-files/replay
POST /v1/lab/vital-files/upload
```

Command-style Lab requests create persisted Guest Control operations using the same Postgres operation repository as service restart. Lab operation failures are saved as failed operations and returned through the Lab response `readError` instead of being converted into an empty scenario list or a successful stopped session.

The current Guest adapter maps these Product Lab commands to the `lab` service API:

| Product Lab operation | Guest adapter target |
|---|---|
| Scenario list | `GET http://lab:8080/lab/scenarios` |
| Bed read model | `GET http://lab:8080/lab/beds` |
| Recorder read model | `GET http://lab:8080/lab/recorders` |
| Create session | `POST http://lab:8080/lab/sessions` |
| Read session | `GET http://lab:8080/lab/sessions/{sessionId}` |
| Start session | `POST http://lab:8080/lab/sessions/{sessionId}/start` |
| Stop session | `POST http://lab:8080/lab/sessions/{sessionId}/stop` |
| `.vital` replay | `POST http://lab:8080/lab/vital-files/replay` |
| `.vital` upload | `POST http://lab:8080/lab/vital-files/upload` |

This makes Product Lab the product boundary and removes the TestKit adapter from the Guest Control Lab execution path.

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
read model reports them.

CLI automation uses the same boundary. `vitalserver-vm runtime lab-*` commands call Guest Control `/v1/lab/*` and print the returned Product Lab contracts as JSON. The Host CLI must not read Lab fixture files, TestKit state files, or container-local process state to infer session state.

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

Runtime boot smoke now uses Guest Control API for product service proof. The `compose-services` stage reads `GET /v1/stack/status` instead of `runtime-state.json.containerServices`, and the `guest-control-api` stage checks Guest Control API readiness, capabilities, service listing, `app` status, `app` restart, stack reconcile, `/v1/operations/{operationId}` readback, Product Lab scenarios, Product Lab session create/start/stop operations, and Product Lab `.vital` replay request acceptance as part of the product runtime proof.

### 3-2. Runtime files are no longer the service control boundary

Runtime files remain valid for bootstrap, host proxy discovery, health evidence, diagnostics, and support artifacts. They must not become the primary product service control/status boundary in Runtime v2.

| Runtime concern | v2 owner | File role |
|---|---|---|
| Product service list/status | Guest Control API | diagnostic evidence only |
| Product service restart operation | Guest Control API + Postgres operation state | none |
| Product Lab scenarios/sessions | Guest Control API + Lab service | none |
| Guest stack reconcile operation | Guest Control API + Postgres operation state | none |
| VM boot discovery | Guest bootstrap/runtime-state writer | `vm-ip` compatibility file, then typed address provider |
| Host nginx proxy target | Host proxy consuming Guest address/bootstrap readiness | explicit discovery input |
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

`make runtime/proof/no-v1-service-state` is the fast static cleanup proof. It checks that Host product service liveness uses Guest Control API, `RuntimeContainerObservation` is not a production contract, `runtime-state.json` no longer carries container service state, VitalDB observation state, or capability state, Host no longer keeps `RuntimeGuestRuntimeStatePolicy` or runtime-state freshness observation as a runtime-state guestHTTP/vmIP promotion path, host proxy does not parse `runtime-state.json.vmIP` and uses explicit Guest address discovery plus bootstrap HTTP evidence, `runtime-status.json` no longer carries container diagnostics evidence or a VitalDB observation contract field, `RuntimeStatus` no longer carries legacy VitalDB observation state, runtime boot smoke validates product services through Guest Control stack status, Redis backup has no request/result file bridge, `/dev/testkit` product surfaces are absent, runtime config no longer carries TestKit enablement, product packaging includes Lab and excludes TestKit runtime artifacts, VitalDB read-model contracts do not name Host SQLite as a product source, Host SQLite VitalDB projection reads require explicit diagnostics mode behind a dedicated diagnostics adapter, Host status publishing does not write VitalDB observations into Host SQLite, Host runtime health does not promote VitalDB read-model failures into recovery reasons, Host recorder-ingress status reads go through Guest Control API only, and whole-stack start/stop plus Host maintenance commands are absent from the product `RuntimeControlClient` and product client callers. It also checks that whole-stack start/stop is absent from Runtime Control HTTP, PWA, and Swift product presentation surfaces, that runtime-data backup/restore plus update activation/shutdown consume Guest Control maintenance API instead of request/result files, that shared Host/Guest contracts no longer publish legacy `*.request` or `*-result.json` filenames, and that Swift production source no longer carries legacy guest result document contracts or polling evaluators.

The same proof also checks that Guest maintenance capability preflight reads
come from Guest Control `GET /v1/capabilities`. Capability checks must preserve
capability read failure separately from a loaded-but-missing capability, and
they must not use `GuestRuntimeStateDocument.capabilities` as the current
maintenance capability source.

Redis backup no longer has a request/result file bridge in the Guest runtime-state watcher or Redis backup usecase. Product service operations, product read models, and Redis backup maintenance operations must go through Guest Control API and its persisted operation documents.

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
consumed through Runtime Control `/runtime/guest/*`, `/lab/*`, and `/vitaldb/*`
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
POST /v1/maintenance/redis-backup
POST /v1/maintenance/redis-restore
POST /v1/maintenance/datastore-repair
POST /v1/maintenance/update-activation
POST /v1/maintenance/update-shutdown
GET  /v1/operations/{operationId}
```

The Redis backup API creates a persisted Guest Control operation with command
`redis-backup`. On success, the completed operation stores an explicit
`result.archive` path in the Postgres-backed operation document. On failure,
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
Guest Redis backup usecase and runtime-state watcher. Redis backup execution
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

This keeps the UI/API command surface stable while moving the state owner to
Guest/Postgres. `RuntimeGuestControlServiceOperation` now carries an optional
`result` contract so Redis backup `result.archive` and Redis restore
`result.restoredArchive` are preserved when Host reads or returns the operation.

Runtime-data backup and restore now use the same Guest Control maintenance API
for Redis archive creation and restore execution. Host still owns local backup
manifest assembly, host file copying, start-on-boot state capture, and
host-selected archive staging, but Redis operation state comes from
Guest/Postgres operation documents rather than Redis backup/restore
request/result files.

Swift Runtime Control `repairDatastore()` now consumes the Guest Control
maintenance API and returns the Guest operation document through the existing
command response shape. CLI `repair-datastore` also consumes the same Guest
operation, then performs the Host-owned proxy/watchdog restart and health
aftercare without writing or polling datastore repair request/result files.

Update shutdown now uses a two-step Guest Control maintenance API. First,
`POST /v1/maintenance/update-shutdown` accepts explicit `requestId` and
`version`, persists `accepted` and `running`, starts the Guest shutdown
preparation in a background thread, and persists a completed operation when the
Guest reaches `poweroff-ready`. The result preserves
`shutdownPhase=poweroff-ready` and the Redis backup archive path when available.
Second, Host calls `POST /v1/maintenance/guest-poweroff` after it has read the
completed `poweroff-ready` operation.

Host update shutdown consumes this API as its primary path. The Swift shutdown
workflow no longer writes `prepare-update-shutdown.request` or polls
`prepare-update-shutdown-result.json`; it starts the Guest operation, polls
`GET /v1/operations/{operationId}` until `poweroff-ready`, then explicitly
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
runtime. Host-visible Guest document readers are narrowed to bootstrap proof:
`RuntimeGuestBootstrapResultReader` reads bootstrap proof, while
runtime-state decoding readers such as `RuntimeGuestRuntimeStateDiagnosticsReader`
have been removed from production composition. Runtime-state file metadata can
remain as diagnostics evidence, but it is not a Guest state contract. Datastore
repair, Redis restore, update activation, and update shutdown use Guest Control
maintenance operations as their command and operation-state boundary.

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

Current health evaluation also filters legacy runtime-state VM errors. Decoded
`runtimeStateMissing`, `runtimeStateInvalid`, and `runtimeStateStale` values are
kept for older status/event evidence, but they do not become live `vmErrors`,
failure reasons, VM state, or watchdog recovery inputs.

Current health read contracts also no longer carry `runtime-state.json` file
metadata. Host does not read runtime-state mtime as a health input. The
runtime-state file may remain as support/export evidence, but live Host health
uses Guest Control readiness, VM lifecycle, bootstrap proof, and Guest service
status contracts.

Uninstall, VM disk repair, and remaining non-datastore maintenance flows may
still use legacy maintenance file workflows until their workflows are moved
behind explicit Guest APIs. Those paths must not be used as product
service/read-model state.

Guest Control API production composition now treats Postgres as the default
state owner. The default Guest Control usecases create Postgres-backed service
operation and VitalDB read-model repositories, run their schema migrations, and
inject those repositories into the application layer. The former volatile
operation repository has been removed from production runtime helpers; Postgres
unavailability must surface as an explicit Guest dependency failure rather than
falling back to hidden in-memory state.

The Guest compose stack includes `postgres` with `postgres-data`, and the
product `lab` service is configured to use the Postgres session store. Host must
continue to consume Lab, service operation, and read-model state through
Guest/Product APIs instead of reading Postgres directly.

Guest service operations persist service status snapshots in the Guest operation
repository after successful `start`, `stop`, `restart`, and `reconcile`
commands. A post-command status read failure is persisted as a failed operation,
because v2 operation completion requires Guest to produce the explicit service
state contract instead of leaving Host to infer service state from files,
compose diagnostics, or a later poll.

`recorder-ingress` must not use `runtime-state.json` as a replay-control input.
The v1 runtime-state memory guard read `containerServices`, but v2
runtime-state no longer carries product service/container state. Until an
explicit Guest/Product resource API exists, recorder-ingress replay adaptive
memory guard is disabled by default and the product service does not mount
`/run/tirosh/runtime`.
