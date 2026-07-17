# Guest Product deployment

This directory contains Guest-owned desired process configuration. It is not a
Host deployment profile, a Guest readiness observation, or a release-build
receipt.

`guest-product-process-deployment.v1.json` is C37
`GuestProductProcessDeploymentConfiguration`. The Guest Product process
supervisor consumes it and starts exactly two required processes:

- `guest-runtime`, which owns Guest control, Lab, Archive, External Upstream,
  Time Authority, Observation Catalog, and telemetry state in its own SQLite
  store; and
- `recorder-gateway`, which owns Recorder Socket.IO sessions, durable packet
  durable ingress state, cold-path capture, ingress receipts, delivery receipts, and delivery replay.

Each field is an explicit desired input. VitalServer placement is owned by
`guest-product-vitalserver-topology-deployment.v1.json` (C44), not by a
conventional loopback address or a guessed local process. C44 names either a
bundled VitalServer service deployment or an external integration reference;
it never carries endpoint or credential material. The Supervisor must consume
the selected topology through `ResolveRecorderGatewayVitalServerDelivery`.
For `external-vitalserver`, C37 names the installed C46
`ExternalVitalServerDeliveryConfiguration` path; the resolver compares the
C44 integration/configuration/provider references with that C46 document
before it creates Recorder Gateway process arguments. It never probes or
guesses an endpoint. Bundled activation remains explicitly unsupported until a
C37 process plan and C39 payload for the declared bundled service exist.

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
The Guest Runtime SQLite path and Recorder Gateway durable ingress-state directory remain
different owner stores.

The C37 document is independently validated and executed by
`services/guest-product-process-supervisor/`. C35 has an explicit additive
migration pair: `guestProductProcessSupervisorArtifact` and
`guestProductProcessDeploymentConfigurationArtifact`. A product package
requires both exact input identities, the separate C38
`guestProductServiceManagerDeploymentConfigurationArtifact`, C39
`guestProductBootstrapConfigurationArtifact`, C44
`guestProductVitalServerTopologyDeploymentArtifact`, and the selected builder
identity in C35 `buildEnvironment`. An external C44 topology additionally
requires `externalVitalServerDeliveryConfigurationArtifact`; a bundled
topology must not carry it as an unused fallback. C37 is the sole desired
process configuration for Guest Runtime: C35/C39 do not carry a second generic
`guestRuntimeConfigurationArtifact` because no Guest process consumes it.
An installed payload must be either an executable, a C37/C38/C44/C46 desired
document, or a configuration document with an explicit consumer.

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
