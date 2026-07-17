# Cross-platform delivery gate

`release-delivery-plans.v1.json` is a C23 declaration of the artifacts and
service registrations that a release intends to ship. It is deliberately not an
artifact manifest: it has no digest and does not claim that any package exists.

C23 also owns the intended installer release identity. The macOS package
composer and verifier select one plan by explicit document path and plan ID,
then project it as `MacOSHostPackageReleasePlan`. That projection supplies the
product version, expected PKG filename, macOS installer package identifier, and
both required Host service launchd labels; those facts must not be re-entered as
independent package CLI values. C33 and PKG
`PackageInfo` realize the selected C23 identity but do not select a release.
See [Product Delivery Release Identity Boundary](../../../docs/architecture/product-delivery-release-identity-boundary.md).

`release-delivery-proofs.v1.json` is C24. Every plan must have a record for all
eight stages: artifact integrity, SBOM/notices, clean install, service
registration, reboot, update, rollback, and uninstall/reinstall. `pending`,
`failed`, and `unsupported` are valid *reported* states but do not pass
`make release-ready`.

Every verified C24 stage must first record one `ObservedInstallerArtifact`: its
artifact kind, filename, product version, SHA-256, and observation time. The
delivery verifier compares kind/filename/version to the selected C23
`intendedInstallerArtifact` and `productVersion`; the SHA-256 remains an
observed built-byte fact rather than a value C23 invents. Thus an evidence URI
alone cannot turn an older or different package into this release's proof.

A verified macOS `clean-install` record additionally needs an
`ObservedMacOSInstallerReceipt`. C23 owns `macOSInstallerPackageIdentifier`;
the runner must observe that exact receipt and its C23 product version after
the explicit installer effect. A PKG filename/digest is not an installed
receipt, and a receipt must not be inferred from a launchd label.

When C24 `service-registration` is `verified`, it must additionally record
both `ObservedHostServiceRegistration` facts (`host-agent` and
`host-edge-proxy`) with their manager, name, `registrationState=registered`,
and observation time. The delivery verifier compares those facts to C23
`requiredHostServiceRegistrations`; a matching package alone cannot silently
prove a different or partial Host service set.

The checked-in source inventory SBOM is a reproducible pre-release input
inventory. It is not release-artifact evidence. A release runner must generate
a per-artifact SBOM and notices, attach its hash/URI to C24 `sbom-and-notices`,
and run `make release-ready` on the clean Host that produced the evidence.

No plan uses a default data path, VM name, service name, credential, or OS
fallback. C33 `HostAgentDeploymentConfiguration` is the explicit launch input
for every Host Agent service instance; the macOS profile names its C32 Guest VM
configuration from C33. Provider and service configuration are explicit
deployment inputs. Uninstall/reinstall proof must record whether data was
preserved or purged as an operator-selected action; it must never silently
delete a data directory.

`support-matrix.v1.json` makes macOS arm64/launchd the first **planned**
clean-install target. Windows amd64/SCM and Linux amd64/systemd remain planned
targets that reuse C25–C31 update contracts. This matrix is a composition
declaration, not C24 proof or a claim that the corresponding installer exists.

`tooling/guest_artifact_compilation_input_assembler.py` is the C41
`GuestArtifactCompilationInputAssembler`. It alone translates named
build-machine source files into the identity-only C35 input root, C35 command,
and C41 receipt. It does not select missing sources, invoke a builder, or claim
compile/boot/install success. See [Guest Artifact Compilation Input Assembly](../../../docs/architecture/guest-artifact-compilation-input-assembly-boundary.md).

`tooling/guest-linux-boot-artifact-extractor/` is the C42
`GuestLinuxBootArtifactExtractor`. It turns a caller-declared, immutable
whole-disk ext4 ARM64 Linux source image into kernel/initrd/root-storage
release-build inputs and a receipt. It has no authority to acquire an image,
select a Linux release, boot a Guest, or claim C24 evidence. See [Guest Linux
Boot Artifact Extraction](../../../docs/architecture/guest-linux-boot-artifact-extraction-boundary.md).

`tooling/guest_root_storage_partition_assembler.py` is the C43
`GuestRootStoragePartitionAssembler`. It verifies the declared C42 receipt and
whole-disk ext4 root-storage identity, then atomically publishes the explicit
MBR `/dev/vda1` raw-storage base plus a C43 receipt. It cannot select a
partition, materialize Guest files, boot a Guest, or claim C24 evidence. See
[Guest Root Storage Partition Assembly](../../../docs/architecture/guest-root-storage-partition-assembly-boundary.md).

`tooling/guest_artifact_compiler.py` consumes C35
`GuestArtifactCompilationCommand` and one selected
`GuestProductBootstrapArtifactComposer`. It verifies exact input/builder
identity and atomically emits C34 plus C35 `GuestArtifactCompilationReceipt`;
neither document is Guest boot proof. The additive C35 Product inputs are the
Supervisor and C37 pair, C38
`guestProductServiceManagerDeploymentConfigurationArtifact`, and C39
`guestProductBootstrapConfigurationArtifact`, and C44
`guestProductVitalServerTopologyDeploymentArtifact`. The builder produces two
explicit storage artifacts: writable RAW `guest-root` and a read-only RAW
`guest-product-bootstrap` image containing the Guest-visible ISO9660
filesystem. A historical non-product C35 command may name none
of the Product inputs.

`tooling/guest-product-bootstrap-volume-composer/` contains the selected C35
builder and C40 NoCloud volume adapter. It preserves the RAW root base and
composes a RAW storage image containing `CIDATA` ISO9660 without shell, cache,
`PATH`, or Host root-filesystem
access. `tooling/macos_guest_artifact_manifest_composer.py` is the C34 digest
adapter used by that compiler. `tooling/guest_product_systemd_service_unit_composer.py`
deterministically produces a systemd unit from C38 but does not operate
systemd.

`tooling/macos_host_package_composer.py` and
`tooling/macos_host_package_verifier.py` require the long-lived
`macos-virtual-machine-supervisor` binary, Host Agent binary, Host Edge Proxy
binary, C32, C33, C34, C35 receipt, C36
`HostEdgeProxyDeploymentConfiguration`, and C37/C38/C39/C44/build provenance to
agree exactly where each belongs; an external C44 topology additionally binds
the supplied C46 delivery configuration to that provenance. A manually created
or tampered C34/C35/C39/C44/C46 input cannot compose a product PKG, and a
tampered C34/C35 package payload cannot verify. PKG composition and verification
results are build results, **not** C24 artifact-integrity, installation,
registration, listener binding, reboot, update, rollback, or uninstall proof.
They require C23 `ReleaseDeliveryPlan.intendedInstallerArtifact` to agree with the output PKG basename,
both required Host launchd plist labels, C33 `installation.productVersion`,
and PKG `PackageInfo.version`; a package cannot obtain a release version from an
arbitrary CLI flag.
They also enforce C32 `GuestRuntimeDiskProvisioning`: the PKG carries the
immutable C34 `guest-root` source under `release`, never a writable VM root;
the installed macOS supervisor creates the separately named C33-data-directory
runtime disk only after C34 identity verification. A later release that does
not match an existing runtime-disk receipt requires an explicit update decision
rather than an installer overwrite.

The package verifier additionally rejects a payload that pre-materializes the
`GuestRuntimeDiskWorkspace` or its receipt. Its postinstall script may create
only the C32/C33-declared Host directories and the append-only boot-console
capture; it must not create, copy, or overwrite either mutable runtime file.

For a bundled Guest Product, C33 `GuestRuntimeControlEndpoint` and C37
`guestRuntime.listener` are one cross-boundary contract: C33 provides the
Host-owned reachable address, while C37 owns the Guest Runtime control listener
port and its current HTTP transport. The composer rejects a package when those
two port/transport declarations disagree; it does not guess an alternate Guest
service from a default port.

See [Guest Artifact Build Boundary](../../../docs/architecture/guest-artifact-build-boundary.md),
[Guest Product Bootstrap Volume Boundary](../../../docs/architecture/guest-product-bootstrap-volume-boundary.md),
[Guest Product Process Supervisor Boundary](../../../docs/architecture/guest-product-process-supervisor-boundary.md),
[Guest Product Service Manager Boundary](../../../docs/architecture/guest-product-service-manager-boundary.md),
[MacOSVirtualMachineSupervisor](../../../docs/architecture/macos-virtual-machine-supervisor-boundary.md),
and [Host Edge Proxy Boundary](../../../docs/architecture/host-edge-proxy-boundary.md)
for the remaining clean-host proof boundary.

`macos_clean_host_release_evidence_runner.py` is the separate C24 collection
workflow. Its `MacOSCleanHostReleaseEvidenceJournal` owns only release evidence
run state, never Host/Guest runtime state. It emits reviewed C24 proof fragments
rather than editing `release-delivery-proofs.v1.json` itself. See [macOS
Clean-Host Release Evidence](../../../docs/architecture/macos-clean-host-release-evidence-boundary.md).
