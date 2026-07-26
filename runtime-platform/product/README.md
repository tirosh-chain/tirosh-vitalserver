# Product Composition

This directory will compose deployable services into explicit topology profiles and deployment manifests.

Topology selection is configuration, not a runtime inference. Profiles must name their state owners and supported upstream placement explicitly.

`profiles/`, `time/`, and `observability/` contain owner-neutral product declarations. They do not implement upstream, Time Authority, or telemetry policy; those remain inside the owning Host/Guest service and are exposed only through C16–C20 contracts. `deployment-profiles/` is intentionally separate: each named directory composes the C32/C33/C36 desired inputs for one explicit Host OS, provider, upstream placement, and public-edge combination. It is neither a generic profile bucket nor a runtime-state owner.

`platform-providers/` names one explicit OS provider selection and its C21/C10/C22 Platform Provider process boundary. C33 `HostAgentDeploymentConfiguration` supplies every Host Agent startup input. The macOS C33 profile additionally names C32 `MacOSVirtualMachineConfiguration`, a Host-owned deployment contract distinct from a lifecycle request. C36 `HostEdgeProxyDeploymentConfiguration` independently supplies the Host public HTTP/WebSocket route and client-identity trust boundary; it does not expose Guest control paths by inference. C35 `GuestArtifactCompilationCommand` gives `GuestArtifactCompiler` immutable builder/source input; its C34 `MacOSGuestArtifactManifest` and C35 receipt give the package composer exact Guest artifact identity. `delivery/` declares C23 release plans, C24 proof status, a source-inventory SBOM, and the first delivery support target. `update/` explains the C25–C31 bootstrap/staging/handoff composition boundary. These files never turn a planned package or a pending proof into installed/released state.

`guest-product/` owns the C37 `GuestProductProcessDeploymentConfiguration` that the
Guest-local `GuestProductProcessSupervisor` consumes and C38
`GuestProductServiceManagerDeploymentConfiguration` that declares the systemd
unit which starts that Supervisor. C37 names the Guest Runtime and Recorder Gateway
executable/process inputs, their separate durable stores, the exact Recorder
delivery endpoint placement, and replay bounds. C38 names the Supervisor/C37 paths,
restart behavior, and systemd install target. C35 retains its frozen Supervisor+C37
input pair and adds C38 as a separate source; a product package composer verifies all
three against the C35 receipt. This is selected-builder input provenance, not
cloud-init installation, systemd installation, or boot proof.
