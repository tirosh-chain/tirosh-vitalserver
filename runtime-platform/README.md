# Runtime Platform

`runtime-platform/` is the independent implementation root for the next VitalServer runtime platform.

The implemented capabilities are: a versioned contract kernel; independently
persisted Host and Guest control state; a typed macOS virtual machine supervisor,
Host-owned HTTP/WebSocket edge proxy, and allowlisted public facade; a Recorder Gateway data plane with durable ingress
state, delivery replay, and delivery receipts; Guest-owned Lab and Archive lifecycles; explicit
external-upstream, relay, time, Recorder observation, and OpenTelemetry
boundaries; selected Windows/Linux native provider bridges and delivery-proof gates;
Guest Product process supervision with C37 process and C38 systemd service-manager
deployment contracts; explicit macOS Installer package-signing composition,
Windows C48/C70-to-WiX MSI input composition with a dedicated SCM service
runner, Host-owned update journaling,
staged next updater planning, and durable handoff recovery. It deliberately contains no
copied legacy source or runtime compatibility layer.

The parent repository remains a behavior reference while the new platform is built. New production code in this root must not import, execute, or depend on `../apps`, `../packages`, or their modules. Reference fixtures may be added only under `acceptance/reference-fixtures/` and must be used through explicit acceptance harnesses.

## Verify the boundary

Run the dependency-free boundary check from the repository root:

```sh
make -C runtime-platform boundary-check
```

For the complete contract and boundary suite, create the root-local virtual environment once:

```sh
make -C runtime-platform bootstrap-contract-tools
make -C runtime-platform check
```

The checks verify the required responsibility layout, reject symlinks and legacy source coupling in production paths, validate quarantined fixture provenance and integrity, and validate the versioned contract source. The dedicated GitHub Actions workflow runs the complete suite when this root changes.

## Responsibility map

- `contracts/` — versioned transport and state contracts shared across deployable units.
- `services/` — deployable product services; each service owns only its declared process-local state.
- `providers/` — host-specific adapters behind provider contracts.
- `product/` — product composition and explicit topology profiles.
- `acceptance/` — executable behavior contracts and separately quarantined reference fixtures.
- `tooling/` — development-only guards, generators, and verification tools.

For the two Host/Guest process boundaries that are easiest to confuse during
on-call work, start with [Host Edge Proxy](services/host-edge-proxy/README.md)
and [Guest Product Process Supervisor](services/guest-product-process-supervisor/README.md).
Those documents state the C36/C37 desired-input boundary, process/state owner,
and the effects each service is allowed to perform.

The current direct/runtime dependency scope and source-inventory SBOM gate are recorded in [DEPENDENCIES.md](DEPENDENCIES.md).

Before adding a persistent directory, package, public type, function, contract,
or artifact, apply the repository's [domain language and module naming
rules](../docs/architecture/domain-language-and-module-naming.md). Names must
make the owner, bounded context, boundary, and role readable without relying on
implementation history or an implicit deployment convention.

The target design and delivery plan live in [the architecture documentation](../docs/architecture/vnext-implementation-plan.md). Start with [Host/Guest Control Slice](../docs/architecture/host-guest-control-boundary.md), [Host Edge Proxy Boundary](../docs/architecture/host-edge-proxy-boundary.md), [Guest Artifact Build Boundary](../docs/architecture/guest-artifact-build-boundary.md), [Guest Product Process Supervisor Boundary](../docs/architecture/guest-product-process-supervisor-boundary.md), [Guest Product Service Manager Boundary](../docs/architecture/guest-product-service-manager-boundary.md), [Guest Product Release Activation Boundary](../docs/architecture/guest-product-release-activation-boundary.md), [Recorder Gateway Data Path](../docs/architecture/recorder-gateway-data-path.md), [Lab, Artifact Export, and Deletion Lifecycle](../docs/architecture/lab-archive-deletion-lifecycle.md), [External Upstream, Time, and Observability](../docs/architecture/external-time-observability.md), [Cross-platform Provider and Delivery](../docs/architecture/cross-platform-delivery.md), [Product Composition and Staged Update](../docs/architecture/product-composition-and-staged-update.md), and [macOS Development Installation Evidence](../docs/architecture/macos-development-installation-evidence-boundary.md). C24 is intentionally pending until matching OS clean-host runners attach evidence for the C23-selected package policy, installation, services, reboot, update, rollback, and removal lifecycle; an unsigned package is accepted only when C23 explicitly selects `unsigned` and C24 retains its observed identity.

The matching C24 runner never edits the source proof template. A release reviewer
uses [Release Delivery Proof Attachment](../docs/architecture/release-delivery-proof-attachment-boundary.md)
to verify fragment/evidence bytes and publish a separate immutable C24 candidate;
`make release-ready` receives that candidate together with its C74 review record,
while independently pinning the reviewed source to the checked-in canonical C24
template. A copied template or an unreviewed/intermediate candidate is not a
release assertion input.
