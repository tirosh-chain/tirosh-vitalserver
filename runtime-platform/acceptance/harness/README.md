# Acceptance Harness

The acceptance harness will provision test topology, drive public contracts, and collect observable outcomes.

It is the only place that may connect reference fixtures to executable acceptance scenarios. It must report unavailable dependencies explicitly.

`test_host_guest_control.py` builds the real Guest Runtime and a clearly test-only Host composition, then talks to their public HTTP endpoints. It does not import a service package, read a SQLite database, or call private functions. The test-only Host provider deliberately keeps the Guest process alive after reporting `stopped`; this proves the facade honors its explicit Host-owned provider observation instead of probing around it or inferring a different Guest state.

Its `platformctl` acceptance uses the same public route for Host lifecycle,
Lab create/resource commands, external-upstream apply, and topology apply.
It first reads a Guest-owned Lab resource and carries the published revision
into a `hide` command. It also proves an external integration must be
configured before topology references it. The harness never supplies a remote
URL, header, credential secret, generic JSON payload, or private database path
to the CLI.

Host application and HTTP tests separately inject state-store outcome failures. They prove that command admission ambiguity is a typed `CommandAdmissionFailure`, while a failure after a durable `running` operation exists cannot replay the provider effect or claim a terminal result. The black-box harness remains limited to public contracts and does not inspect those injected stores.

`test_recorder_gateway.py` first builds the isolated Gateway package, then invokes `recorder_gateway_scenario.mjs`. The script uses an installed Socket.IO v2 client to exercise the Gateway's v4-compatible adapter and returns only public HTTP/Socket.IO contract facts. Python validates C5 and C13 with the runtime-platform contract repository; no Gateway-private durable ingress-state file is read by the acceptance harness.

`test_lab_recorder_runner_gateway.py` starts the production Runner and Gateway
Node entrypoints with temporary, process-owned state. It drives the Runner's
published HTTP command/read resources and the Gateway's public capture/read
resources only. The test confirms the real Socket.IO join, packet ingress,
finalization, C45 packet-sequence digest, and Runner C19 publication request;
it does not open Gateway durable state, replace Gateway with a fixture, or
claim Archive success.

`test_lab_archive_deletion.py` builds a real Guest Runtime binary and drives `LabSession`, `VirtualRecorder`, `ArtifactExport`, and deletion receipt routes through HTTP. Its configurable Archive provider is an explicit acceptance adapter, not a VitalServer multipart stub. The harness checks only contract-shaped public resources and operations; it neither opens Guest SQLite nor interprets a raw artifact object.

`test_external_time_observability.py` builds real Guest Runtime and test-only Host Agent binaries, then exercises C16–C20 through their public routes. It deliberately launches separate provider profiles for available, unavailable, and unknown outcomes. This makes it possible to prove that neither topology, relay, time, Catalog, nor telemetry changes its semantic result because another profile or a previous test happened to succeed. The harness never reads either owner database.

`test_cross_platform_delivery.py` builds the real Host Agent against a portable bridge fixture and drives its public lifecycle routes. It proves C21 request/revision correlation, durable request-ID replay behavior, selected-provider failure, and no provider fallback without reading Host SQLite. It does **not** claim a Hyper-V or libvirt installation; C24 keeps actual OS clean-host proof explicitly pending until its corresponding runner provides evidence.

`test_installation_update_foundation.py` builds the test-only Host composition, `release-composer`, the independent `host-updater`, and `host-update-handoff-supervisor`. It submits one C31 queue entry to the C56 supervisor, which verifies only C31/C30/C25 before selecting the staged updater. The updater alone reads C26, accepts fixture-produced C55 receipts, writes C28, and returns C27 through the Host Agent C52 Unix socket. The harness validates C57 and proves that `completion-submitted` is distinct from C29's terminal `succeeded` update state. It also proves deterministic and Ed25519-signed bundle handoff, durable handoff-before-effect, restart re-handoff, request/report replay, explicit bootstrap failure, and rejected layer order without opening Host SQLite. Package activation, concrete layer replacement, and clean-host proof remain outside this harness.
