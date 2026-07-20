# Guest Runtime

The Guest Runtime owns Guest control-plane resources and its Guest-owned SQLite
state. `GuestProductProcessSupervisor` owns the lifetime of the Guest Runtime
and Recorder Gateway processes; the Guest Runtime must not start, stop, or
infer Recorder Gateway process state.

It consumes Host-provided configuration and runtime contracts. It does not own host filesystems, host process state, or host-provider behavior.

## Code language and responsibility map

The source names make the Guest-owned boundary visible before opening an
implementation file. `GuestRuntimeTopologyApplicationService` is the application owner of
one `RuntimeTopology`, its idempotent topology-apply operation, capability
projection, and readiness projection. It depends on the narrow
`GuestRuntimeTopologyStateRepository` port; that port cannot mutate Lab, archive, time,
catalog, or telemetry resources.

The selected SQLite adapter is named
`GuestRuntimeStateSQLiteRepository`: it is a Guest Runtime state owner using
SQLite, not a generic shared `Repository` and not Host state. The HTTP adapter
is `GuestRuntimeControlHTTPServer`, with
`NewGuestRuntimeControlHTTPServerWithModules` making every optional use-case
owner explicit at composition time. Its module fields name their owned
concepts (`ExternalUpstreamIntegration`, `OutboundRelayTarget`,
`GuestTimeAuthority`, `RecorderObservationCatalog`, and
`GuestTelemetryPipeline`) instead of generic labels such as `External` or
`Time`. Its source modules follow the same language:

| Layer | Durable module | Role |
| --- | --- | --- |
| Domain | `internal/guestruntimedomain/guest_runtime_contract_documents.go`, `runtime_topology_operation_policy.go` | Guest Runtime versioned documents and pure topology-operation transitions |
| Application | `internal/guestruntimeapplication/guest_runtime_topology_application_service.go` | topology/operation/capability/readiness workflow only |
| Application | `internal/guestruntimeapplication/guest_runtime_application_ports.go` | explicit Guest Runtime persistence, clock, identifier, and provider ports |
| Adapter | `gueststatesqliterepository/` | Guest-owned SQLite state persistence, partitioned by Lab, archive, integration, and operational resources |
| Adapter | `vitalserverindexedlibrary/` | C46-selected indexed-library archive adapter and the separate C51 private credential-material owner |
| Presentation adapter | `internal/guestruntimecontrolhttpapi/guest_runtime_control_http_server.go` | versioned control request decoding and explicit result formatting |

Names such as `Service`, `Repository`, `Server`, `New`, and `runtime.go` are
not used for this boundary on their own. A short name is acceptable only when
the enclosing package/type already preserves the owner and managed concept.

## Cross-aggregate vocabulary is explicit

Lab lifecycle and Archive Export are distinct state owners. Their only
cross-aggregate ordering use case is named
`GuestRuntimeLabArchiveLifecycleCoordinator`; it depends on the narrow
`GuestRuntimeLabResourceCommandWorkflow` and
`GuestRuntimeArchiveRetentionAndExportWorkflow` ports, plus an explicit
`LabArchiveLifecycleCoordinationClock`. It must not read the Lab service's
private clock, either aggregate's SQLite tables, or a presentation model.

## External Archive credential material is not Guest Runtime state

For an external `vitalserver-indexed-library` Archive provider, C46 carries
only the credential **reference**. C51 carries the secret value and is owned by
`VitalServerIndexedLibraryCredentialMaterialFileOwner`, never by the SQLite
repository. Guest Runtime can start with C51 absent; C60 then reports the
explicit `missing` state through the named Host Agent C52 local-administration
facade. A local provision command atomically writes the private file and
returns only a non-secret outcome. It is intentionally unavailable through the
Host public edge and never appears in an operation, receipt, telemetry, or a
normal response.

Archive Export opens the C51 material only when an upload/index effect is due.
If it is missing or invalid, the adapter returns a known failed export step so
the Archive owner records a failed receipt rather than treating the condition
as a successful, empty, or unknown upload.

Likewise, the running `Operation` admitted before a resource observation or
effect is not an External Upstream concept. The package-local
`newGuestRuntimeOwnedResourceRunningOperation` describes the shared workflow
fact without making Time Authority, Observation Catalog, Outbound Relay, or
Telemetry Pipeline appear to depend on External Upstream. It only moves the
pure domain operation through `requested → accepted → running`; the caller's
bounded context still supplies the operation kind and owned resource identity.

## Guest runtime control

- The service owns its own SQLite database passed through `--state-db`; it never reads Host Agent state or any other service database.
- `GET /v1/runtime/topology`, `GET /v1/runtime/operations/{id}`, `GET /v1/runtime/capabilities`, and `GET /v1/runtime/readiness` return explicit `ReadResult` documents.
- `POST /v1/runtime/topology:apply` validates a versioned command, applies only a Guest-owned `RuntimeTopology`, and stores an idempotent Guest operation. Reusing a request ID with different input is rejected.
- A topology write whose atomic commit outcome cannot be known returns typed `CommandAdmissionFailure` rather than claiming that no operation exists. Recovering clients retry the exact request ID only.
- `RuntimeTopology` is a singleton Guest-owned resource. Its command workflow is serialized by the single Guest Runtime owner process so simultaneous retries preserve request-ID idempotency and revision guards.
- This composition has no VitalServer upstream adapter. A successfully persisted topology therefore reports `status.readState=unsupported` and `connection.state=not-checked`; it does not claim upstream connectivity or data delivery.

For product deployment, run the C37-driven `GuestProductProcessSupervisor`:

```sh
guest-product-process-supervisor \
  --deployment-configuration /absolute/guest-product-process-deployment.json
```

The standalone Guest Runtime command remains useful only when a test or an
operator supplies every listener, SQLite path, provider reference/outcome,
time, and telemetry flag explicitly. It no longer selects product defaults.
