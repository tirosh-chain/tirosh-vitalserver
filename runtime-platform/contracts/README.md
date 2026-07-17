# Contracts

This directory owns language-neutral, versioned API, event, command, state, and receipt definitions shared across deployable units.

## Canonical sources

- `json-schema/v1/` contains JSON Schema Draft 2020-12 documents. Every persisted or cross-process document has an explicit `schemaVersion` and a stable URN `$id`.
- `openapi/control.v1.json` describes the public Control API major. It references the JSON Schema source; it is not a second model.
- `catalog/v1.json` maps each contract to its owner, boundary, and every canonical schema source.
- `policies/v1/` contains executable cross-owner contract rules, such as the allowed `Operation` transition graph. A service implements its own pure domain policy later; it must conform to this graph.
- `examples/v1/` contains positive and negative decode evidence. No example contains secrets, patient identifiers, waveform values, or raw recorder payloads.
- `compatibility/v1/baseline.json` is a generated, frozen baseline used to reject breaking changes within the `v1` major. New v1 contracts are added only with an explicit compatible extension; an existing baseline cannot be silently regenerated.

## Contract rules

1. `apiVersion`, persisted `schemaVersion`, recorder `protocolVersion`, and provider capability revision are different version axes.
2. `ReadResult` keeps `missing`, `invalid`, `unavailable`, `failed`, `stale`, `empty`, and `unsupported` distinct. None may be formatted or decoded as `available`.
3. `CommandRejection` means the owner did not admit a command and no `Operation` exists. It covers invalid input, revision conflict, and a dependency failure known before forwarding. `CommandAdmissionFailure` preserves the distinct case where admission is unknown; clients retry the exact `requestId` only after the owner recovers. A command admitted for execution returns an `Operation`; an observed execution failure is represented by terminal `Operation.state=failed`.
4. `RuntimeTopology.spec` contains references only. It must never contain endpoint credentials or secret material.
5. Receipt contracts separate ingress durability, each upstream delivery attempt, artifact upload, and indexing. `IngressReceipt` records durable handoff only; `DeliveryReceipt` records one later upstream attempt, including `unknown` delivery outcomes and bounded retry disposition. One successful receipt does not create another.
6. Telemetry correlation has a deliberately closed attribute surface. Patient, waveform, raw packet, endpoint, and credential values are not contract fields.
7. C21 carries Host-owned request ID and expected endpoint revision to one selected Platform Provider. The provider validates correlation but does not create an independent lifecycle ledger or choose another provider.
8. C22 reports installation, VM, service, and capability observations separately. C23 is a delivery plan, while C24 is the only release-proof status source; a pending/unsupported/failed C24 stage never means installation success.
9. C25 is the immutable signed bootstrap language. It contains no `minimumUpdaterVersion`: the current updater verifies/stages its signed next updater and opaque C26 digest, while only the staged next updater parses C26. Missing/invalid trust evidence is a typed bootstrap failure, not a legacy-parser fallback.
10. C27/C28/C29 keep update admission, bootstrap receipt, per-layer evidence, and Host-owned durable recovery state separate. A C29 journal that decodes but fails its bootstrap/receipt/report cross-field correlations is `invalid`, not an available update. Only complete C28 success evidence advances the Host installation release.
11. C35 keeps Guest build desired input, selected builder identity, compiler input/output receipt, and C34 artifact identity separate. Its additive paired Product inputs (`guestProductProcessSupervisorArtifact` and `guestProductProcessDeploymentConfigurationArtifact`) preserve the original non-product C35 shape. C38, C39, and C44 are separate additive C35 sources; C46 is an additional source only when the selected C44 topology is external; `buildEnvironment` identifies the selected `GuestProductBootstrapArtifactComposer`. Product package composition requires the exact applicable sources without changing the frozen pair rule. C35 emits exactly two storage artifacts: writable RAW `guest-root` and a read-only RAW `guest-product-bootstrap` image whose Guest-visible filesystem is ISO9660. A C35 receipt proves only exact build input/output correlation; it does not prove cloud-init installation, systemd installation, Guest boot, Guest Runtime readiness, topology delivery resolution, or clean-Host package installation.
12. C36 makes the Host public HTTP/WebSocket listener, every target route, request bounds, Host header policy, and replacement client-identity policy explicit. It is Host proxy desired configuration, not a Guest/upstream readiness document.
13. C37 makes Guest Runtime and Recorder Gateway executable paths, listeners, separate durable stores, C44 topology path, optional C46 external delivery-configuration path, and replay limits explicit to the Guest Product process supervisor. C37 does not own a delivery endpoint or select a topology; the Supervisor resolves those complete inputs from C37/C44/C46 before it plans Recorder Gateway arguments. It is Guest desired process configuration, not a Guest artifact inclusion, child-process start, Recorder delivery, or upstream-health fact.
14. C38 makes the systemd unit name, Supervisor/C37 invocation paths, restart mode/delay, and install target explicit. It is Guest service-manager desired configuration, not a systemd installed/enabled/running observation or child-process readiness fact.
15. C39 `GuestProductBootstrapConfiguration` makes the NoCloud bootstrap identity, Guest-visible ISO9660 filesystem, every Guest Product payload destination including the C44 topology document and, only for external topology, the C46 delivery configuration document, required Recorder Gateway archive paths, systemd unit path, enabled-unit link path, and link target explicit. C40 is the derived plan delivered to the selected `GuestProductBootstrapVolumeComposer`, which creates a read-only RAW storage image containing the `CIDATA` filesystem. C39/C40 do not say cloud-init installed the payload, systemd observed the service, topology delivery was resolved, or the Guest booted.

16. `--extend-baseline` is only for additive v1 contracts after compatibility
passes. `--replace-baseline-for-unreleased-contracts` is a deliberately named,
separate authority for an intentionally unreleased contract redesign. It must
not be used after a v1 artifact has external consumers; that case requires a
new versioned contract and migration.
17. C41 keeps Host build-machine source selection outside C35. Its declaration names every selected source and one new assembled input root; its receipt records C41 declaration, C35 command, builder, and input byte identities without retaining source absolute paths. C41 success is neither C35 compilation, Guest boot, systemd startup, nor package installation evidence.
18. C42 keeps a release-approved Guest Linux source image outside both C41 and C35. Its declaration names one source image identity, whole-disk ext4 layout, and exact Guest paths for the kernel and initial ramdisk. Its receipt records only immutable input/output identities, not a build-machine path. C42 success is neither C35 compilation, Guest boot, systemd startup, nor package installation evidence.
19. C43 accepts only the identity-verified C42 whole-disk ext4 root-storage output and copies it into one explicitly declared MBR root partition. Its declaration and receipt make the C42 receipt correlation, partition table, Guest disk/partition paths, sector size, and target raw-storage identity explicit. C43 success is neither C40 bootstrap-volume composition, Guest boot, C35 compilation, nor package installation evidence.
20. C32 `LinuxBootResources.guestRootDevicePath` makes the C43-published Guest root partition explicit in the Host boot deployment. The matching kernel `root=` argument is validated as the same value; Host disk-image paths never imply a Guest root device.
21. C44 is the Guest Product release author's single desired VitalServer placement declaration. `bundled-vitalserver` requires an explicit service artifact, process identity, Guest-loopback delivery listener, and state directory; `external-vitalserver` requires both the C16 external integration reference and a deployment-owned external delivery-configuration reference. It carries no endpoint/credential material and no availability, process, or delivery fact. C41, C35, C39, and C40 preserve and install C44 before package publication; for external topology they must preserve the referenced C46 as well. C37 activation must consume an explicit delivery-resolution result before a bundled or external data plane can be claimed.
22. C46 is external deployment-administrator desired configuration, not a network observation. For a C44 external topology, C41/C35/C39/C40 preserve and install its exact non-secret source at the C37-declared Guest path. It binds one C44-selected C16 reference and complete provider identity to one explicit Socket.IO delivery endpoint and acknowledgement timeout. The Supervisor rejects missing, unreadable, invalid, mismatched, or Guest-loopback C46 input; it does not infer an endpoint or select a bundled fallback.
23. C47 makes one macOS product-package release build reproducible without moving C41/C35/package-adapter ownership into a generic script. Its declaration names C23 selection, C41/C35 execution destinations/times, Host artifacts, deployment documents, separate PKG and VM-supervisor signing inputs, package/verification executables, and a new receipt destination. It derives Guest package sources from C41 and verifies them against actual C35 output. Its receipt retains declaration/C41/C35/C34/PKG identities without build-machine source paths. C47 build success is not package signing acceptance, clean-Host installation, service registration, Guest boot/readiness, update, rollback, uninstall, or C24 proof.

## Local verification

Create the root-local virtual environment once, then run all checks:

```sh
make -C runtime-platform bootstrap-contract-tools
make -C runtime-platform check
```

The verifier checks JSON Schema meta-validity, example decode failures, OpenAPI validity, operation transition invariants, and `v1` compatibility against the frozen baseline.

After an additive contract has passed compatibility verification, extend the baseline deliberately:

```sh
make -C runtime-platform contract-extend-baseline
```

This command first rejects any mutation of an already baselined `v1` schema or public operation, then records only the compatible current source as the new reference point. It is not a mechanism for accepting a breaking change.
