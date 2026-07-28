# Host Agent

The Host Agent owns host-local runtime lifecycle, process supervision, filesystem paths, host networking, and provider selection through explicit ports.

It does not inspect Guest internals or infer Guest state. Guest-visible state is published only through versioned contracts.

## Read the bounded context from the package names

The Host Agent is intentionally not organized around generic `domain`,
`application`, or `httpapi` package names. Each internal package identifies
both the Host Agent bounded context and its role.

| Package | Responsibility | It must not do |
| --- | --- | --- |
| `internal/hostagentdomain` | Pure Host-owned lifecycle, update, time, and telemetry policy | Read SQLite, call a provider process, or make HTTP requests |
| `internal/hostagentapplication` | Orchestrate explicit ports and persist Host-owned operation state | Infer Guest state or choose a provider from ambient Host facts |
| `internal/hostagentcontrolhttpapi` | Present `/v1/platform/*` and allowlist the Guest Runtime Control facade | Own lifecycle/update transition policy |
| `internal/hostdeployment` | Decode C33 desired deployment input and resolve the selected provider process command | Own live Host runtime state |
| `internal/adapters/hoststatesqliterepository` | Persist Host Agent state in the Host-owned SQLite store | Decide domain transitions |

The public names preserve the same context: `HostAgentControlApplicationService`
orchestrates the lifecycle/control slice, `HostUpdateApplicationService` owns
the durable update workflow, and `HostAgentControlHTTPServer` is only the HTTP
presentation boundary. `HostAgentControlStateRepository` is a port; its
`HostAgentStateSQLiteRepository` adapter is the only one of those two that
opens SQLite. This makes a stack trace or import list explain who owns a fact
before a reader opens the implementation.

## Host lifecycle control

- Host Agent owns only its own SQLite resources: `PlatformInstallation`, `GuestRuntimeControlEndpoint`, and Host lifecycle `Operation` documents.
- It records a durable `running` operation before invoking the configured Platform Provider process. A terminal provider result is committed atomically with the next Host endpoint observation.
- If that terminal commit fails after an external effect, the returned operation stays `running`; the Host does not fabricate a terminal result or re-run the same request ID's provider effect.
- Lifecycle effects and Host transport probes share the endpoint revision, so this single Host Agent process serializes their endpoint-mutating workflows. A multi-writer Host profile is not supported by this composition.
- A command that cannot safely be admitted returns typed `CommandAdmissionFailure`. `admissionState=unknown` requires retrying the exact request ID after Host recovery; it is not a `CommandRejection`.
- `/v1/platform/*` is Host-owned. Only the documented runtime routes are forwarded, after a Host-owned explicit probe, and successful Guest responses remain raw/unchanged.
- The product executable starts only with `--deployment-configuration <absolute-path>`. C33 `HostAgentDeploymentConfiguration` names its control DB/listen address, installation and Guest endpoint identity, deterministic Guest operational-state backup schedule/destination with explicit `retain-all` v1 retention, selected Platform Provider process, time/telemetry modes, and update-bootstrap mode. Missing or invalid C33 stops startup; it is never replaced by CLI defaults.
- The Host backup scheduler emits one deterministic C76 request/operation identity per UTC interval slot. Restart and retry repeat that identity through Guest Control; the Guest ledger owns idempotency and operation state. Host Agent never scans Guest manifests, files, PostgreSQL tables, or logs to infer backup state.
- For `macos-virtualization`, C33 names C32 `MacOSVirtualMachineConfiguration` and the long-lived `macos-virtual-machine-supervisor` executable. The Host Agent starts that selected supervisor once and exchanges C21/C10 documents over its retained process transport; C32 identifies the Guest kernel, disks, resource allocation, NAT attachment, and unicast MAC address explicitly. The Host Agent never derives VM inputs from its data directory. Windows/Linux C33 profiles name their native VM and Host-service resources plus one explicit ownership mode: `runtime-platform-provisioned` carries a C62 native Guest provisioning configuration to the selected bridge, while `externally-provisioned` deliberately carries no C62 and can only control a separately provisioned named VM.
- Starting the Host Agent process, including `launchd` registration during package installation, does **not** imply a Guest VM lifecycle effect. A Guest start/stop/reboot remains an explicit C9 `GuestLifecycleCommand` with its own request ID and expected Host-owned endpoint revision. The package postinstall script must not invent such a command or treat an absent startup policy as `start`.

The detailed design history and acceptance evidence are in [Host/Guest Control Slice](../../../docs/architecture/host-guest-control-boundary.md).

## Installation and update boundary

- Host Agent owns C29 `HostUpdateJournal` and its optimistic journal revision in the same Host SQLite boundary as the C7 installation resource. A successful C28 report advances the installed release and terminal operation atomically; any other report leaves the release revision unchanged.
- C25 is retained as durable recovery input, while C26 remains opaque. The Host validates/stages the signed next updater through an explicit platform bootstrap port and never imports the next-updater C26 parser.
- `handoff-pending` is persisted before the idempotent native handoff effect. Startup recovery repeats only `bootstrap-staged`/`handoff-pending` handoff; it never guesses whether an `applying` next updater is alive.
- When all three explicit update paths are configured (`--update-bundle-store`, `--update-staging-directory`, and `--update-trust-store`), the Host uses `StagedBundleBootstrapper`: it verifies C25 with the configured Ed25519 trust store, stages the complete bundle atomically, then creates C30 only after C29 is durably `handoff-pending`. C30 carries the original request ID and exact journal revision required for completion before the Host writes a C31 reference into its handoff queue. Supplying only some paths is a startup error. Supplying none selects the explicit unavailable adapter.
- Publishing C31 is a durable handoff request, not a claim that a next updater has already executed. The separate deployment supervisor resolves C31 to C30; layer effect adapters remain product composition responsibilities.
- Host Update Operation Ownership (contract C80) is the explicit Host-local
  coordination read for installation lifecycle consumers. The Host state store
  atomically permits at most one non-terminal Update Journal. `idle` is emitted
  only after the installation and active-journal query both succeed; a missing,
  invalid, failed, or unavailable read never permits install or removal.
- Host Update Interruption Request (contract C81) records exact-owner
  cancellation intent without claiming process termination. The journal keeps
  its existing active state, the ownership projection reports
  `interruptionRequested`, and completion is fenced until the handoff
  supervisor supplies explicit termination evidence.
- Host Update Interruption Confirmation (contract C82) is the only terminal
  settlement path for that request. It fences installation identity/revision,
  Update Journal revision, and interruption request identity, then commits the
  interrupted Operation and Journal atomically with typed process-termination
  evidence.
- C69 is the operator entry boundary for an offline release bundle. The Host-local `update-bundles:import` command accepts one OS-selected directory, rejects links/partial trees/conflicting bytes, and atomically publishes it below the configured bundle store. Its `declared` C25 view means only that immutable bytes are present; C25 signature verification still happens at the existing C27 bootstrap boundary. `update-bundles/{id}:apply` reads that Host-owned declaration and binds it to the normal C27/C29 workflow, so Console and CLI cannot author an envelope or substitute a path after import.

See [Product Composition and Staged Update](../../../docs/architecture/product-composition-and-staged-update.md) for C25–C31 ownership, API scope, acceptance evidence, and remaining native delivery proof.
