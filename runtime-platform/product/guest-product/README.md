# Guest Product deployment

This directory contains Guest-owned desired process configuration. It is not a
Host deployment profile, a Guest readiness observation, or a release-build
receipt.

`guest-product-process-deployment.v1.json` is C37
`GuestProductProcessDeploymentConfiguration`. The Guest Product process
supervisor consumes it and starts exactly three required processes:

- `guest-runtime`, which owns Guest control, Lab, Archive, External Upstream,
  Time Authority, Observation Catalog, and telemetry state in its own SQLite
  store; and
- `recorder-gateway`, which owns Recorder Socket.IO sessions, durable packet
  durable ingress state, cold-path capture, ingress receipts, delivery receipts, and delivery replay.
- `lab-recorder-runner`, which owns the virtual Recorder runtime and terminal
  finalization receipts for Lab scenarios. It publishes a C19 virtual-Recorder
  self-observation through its declared Guest Runtime catalog endpoint, but
  does not own Archive manifests or final upload/index receipt state.

Each field is an explicit desired input. VitalServer placement is owned by
`guest-product-vitalserver-topology-deployment.v1.json` (C44), not by a
conventional loopback address or a guessed local process. C44 names either a
C64 bundled Upstream image-set manager configuration reference plus a declared
Guest-loopback packet-delivery endpoint, or an external integration reference;
it never carries a connection, image-loaded, or credential observation. The Supervisor must consume
the selected topology through `ResolveRecorderGatewayVitalServerDelivery`.
For `external-vitalserver`, C37 names the installed C46
`ExternalVitalServerDeliveryConfiguration` path; the resolver compares the
C44 integration/configuration/provider references with that C46 document
before it creates Recorder Gateway process arguments. C46 separately names the
operator-approved External VitalServer HTTP observation endpoint (exact path
and accepted status codes), indexed-library Archive provider, endpoint,
timeout, and a C51 credential reference. C37 `external-vitalserver-http`
passes only the C46 path and an explicit request timeout to Guest Runtime; it
does not derive a health route from packet delivery. A C37
`vitalserver-indexed-library` Archive selection supplies only
the private C51 path; the Supervisor rejects provider mismatch before Guest
Runtime starts. Guest Runtime itself starts without C51 so its OS-local
administration boundary can report `missing` and accept the one explicit C51
provision command. It rejects unreadable, unsafe-permission, invalid, or
mismatched C51 material before an Archive effect can make an HTTP request. It
never probes or guesses an endpoint. For bundled placement, C39 installs C64 as
an independent Guest service and explicitly creates its initial `unprovisioned`
state. C37 does not start a VitalServer container as a product child; C55→C66→C64
is the only image-load/Compose transition path.

`external-vitalserver-delivery-configuration.reference.v1.json` is deliberately
named as a **reference** C46 source: its `.example` endpoint is useful for
package-composition provenance only and cannot be cited as a deployment-ready
VitalServer target. A real deployment administrator supplies a separately
identified C46 document, then selects a C44 topology whose integration,
provider, and configuration references all agree. The installed Guest path
remains `external-vitalserver-delivery-configuration.json` because that path
names the C46 role consumed by Recorder Gateway, not the build-source variant.
Each `publicServiceVirtioSocketBridges` entry also names its
`guestProductProcessName`; C37 accepts it only when that exact planned child
process owns the declared Guest-loopback target listener. A route may not name
an unplanned process merely because a port is conventional.

The product C37 selects C46's `vitalserver-indexed-library` capability rather
than the deterministic `archive-export-outcome-profile` used only by
acceptance deployments. Therefore a terminal Lab recorder follows the real
contract: Recorder Gateway finalizes raw cold-path packets; Guest Runtime
forms a `.vital` artifact; then the selected library adapter uploads and
verifies indexing. C51 credential material remains outside C39 and the package:
the Guest-local secret owner accepts it only through the C52 OS-authorized Host
Agent local-administration facade, writes the exact C37 path atomically with
private permissions, and checks the C46 reference. It is intentionally
ephemeral Guest runtime material: after a Guest restart the operator provisions
it again through that same local boundary. Until then, Archive Export writes a
known failed receipt rather than stopping Guest Runtime or claiming an upload.
The checked-in `.example` C46 source remains non-operational until a deployment
author replaces it through an explicit deployment input.

The Guest Runtime SQLite path and Recorder Gateway durable ingress-state directory remain
different owner stores.

`guest-product-bootstrap-configuration.v1.json` is the explicit arm64
selection for the macOS-native Guest. `guest-product-bootstrap-configuration-amd64.v1.json`
is the explicit amd64 selection for the Windows Hyper-V and Linux KVM/libvirt
Guests. They are distinct C39 desired inputs because C35 must receive the
exact architecture-suffixed binary artifacts. Selecting one from the host
platform, or falling back from one architecture to the other, is not allowed.

The C37 document is independently validated and executed by
`services/guest-product-process-supervisor/`. C35 has an explicit additive
migration pair: `guestProductProcessSupervisorArtifact` and
`guestProductProcessDeploymentConfigurationArtifact`. A product package
requires both exact input identities, the separate C38
`guestProductServiceManagerDeploymentConfigurationArtifact`, C39
`guestProductBootstrapConfigurationArtifact`, C44
`guestProductVitalServerTopologyDeploymentArtifact`, and the selected builder
identity in C35 `buildEnvironment`. An external C44 topology additionally
requires `externalVitalServerDeliveryConfigurationArtifact`; a bundled topology
instead requires the paired `guestBundledUpstreamImageSetManagerArtifact` and
`guestBundledUpstreamImageSetManagerConfigurationArtifact`. Neither topology
may carry the other topology's payload as an unused fallback. C37 is the sole desired
process configuration for Guest Runtime: C35/C39 do not carry a second generic
`guestRuntimeConfigurationArtifact` because no Guest process consumes it.
An installed payload must be either an executable, a C37/C38/C44/C46 desired
document, or a configuration document with an explicit consumer. C51 is never
a C35/C39/package payload: a secret owner provisions it at the C37-declared
private path and it has no build-source fallback.

The four `*-bundled-vitalserver.v1.json` documents and
`guest-bundled-upstream-image-set-manager-configuration.v1.json` are the
corresponding C37/C39/C44/C64 reference inputs for a Guest-owned bundled
VitalServer/Redis placement. They omit C46 entirely. C37 passes C44's exact
configuration path to the archive adapter and marks external-upstream
observation explicitly `unsupported`; C39 installs C64; C44 declares only the
Guest-loopback packet, observation, and indexed-library endpoints; and C64
starts at `unprovisioned`. This preserves the distinction between a packaged
manager and a loaded/active image set.

`guest-product-release-manager-configuration.v1.json` is C59
`GuestProductReleaseManagerConfiguration`. Its binary and configuration are
also required C35 inputs. C39 installs them in the immutable release and
enables the manager as a **separate** systemd service. That service owns
release-archive staging, `current` link activation, health-gated rollback, and
its own durable operation journal. It stays available while it restarts the
distinct Guest Product service. C59 exposes its control contract on its own
Guest AF_VSOCK listener; C32 declares the paired Host-loopback bridge. It is
not routed through Guest Runtime, because restarting the Guest Product must
not sever the request that triggered the restart. Host code never writes a
Guest release directory or its operation journal.

`guest-product-service-manager-deployment.v1.json` is C38
`GuestProductServiceManagerDeploymentConfiguration`. It is consumed by the
release-build `guest_product_systemd_service_unit_composer`, which produces a
systemd unit for the Supervisor. systemd owns unit enable/start/restart/stop;
the Supervisor owns only its two child process lifetimes.

That correlation proves the selected Guest builder received the exact
Supervisor, C37, C38, C39, C44, and—only for external topology—C46 bytes. C39
fixes the complete Guest-owned bootstrap destination, archive entry-mode and
symbolic-link policy, systemd-link,
C44 topology-file, and optional C46 delivery-configuration-file vocabulary;
C40 turns those declarations into a read-only `CIDATA` volume. The selected
builder has a focused test that preserves raw-root bytes while producing the
bootstrap volume, but that does **not** prove cloud-init installed/started the
unit, that the Guest booted, that external endpoint connectivity completed, or
that Recorder delivery completed. Those are separate builder-output, Guest
smoke, and runtime evidence boundaries.
