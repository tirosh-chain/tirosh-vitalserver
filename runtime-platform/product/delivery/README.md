# Cross-platform delivery gate

`release-delivery-plans.v1.json` is a C23 declaration of the artifacts and
service registrations that a release intends to ship. It is deliberately not an
artifact manifest: it has no digest and does not claim that any package exists.

C23 also owns the intended installer release identity. The macOS package
composer and verifier select one plan by explicit document path and plan ID,
then project it as `MacOSHostPackageReleasePlan`. That projection supplies the
product version, expected PKG filename, macOS installer package identifier, and
all three required Host service launchd labels; those facts must not be re-entered as
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

macOS C23 additionally declares `macOSInstallerSignaturePolicy`. `unsigned`
means the package artifact must explicitly report `Status: no signature`; it
is supported for a hash-bound, operator-installed delivery and does not mean
that Apple signing was silently bypassed. `developer-id` requires the accepted
Apple Installer signature. C24 retains the package SHA-256, identifier,
version, and raw `pkgutil` observation; it never derives trust from a filename
or a successful `installer` effect.

The Windows C24 runner selects the same C23 plan through
`WindowsHostMSIReleasePlan`, so MSI filename/version and the three SCM service
names cannot be re-entered through independent evidence CLI values. It receives
the C48/MSI-owned ProductCode, product root, immutable release root, and mutable
data root separately, then observes them through Windows registry/SCM/PowerShell
command contracts. It also has one explicit C54 `preserve-mutable-data`
`uninstall-reinstall` operation: after reboot evidence it executes `msiexec /x`,
requires the exact C54 completion receipt, observes absent MSI/services/immutable
release root and present data root, and only then executes `msiexec /i`. A WiX
compile, MSI filename, or uninstall exit code is not clean-install or data
preservation proof. See [Windows Clean-Host Release Evidence](../../../docs/architecture/windows-clean-host-release-evidence-boundary.md).

The Linux C24 runner projects the selected plan as `LinuxHostDEBReleasePlan`.
It receives the C48-owned Debian package identifier and immutable/mutable root
paths independently, then records explicit `dpkg-deb`, `dpkg-query`, systemd,
filesystem, and kernel boot-ID observations. A DEB archive, a successful
composer, or `dpkg --install` exit code alone is not Linux clean-host proof.
See [Linux Clean-Host Release Evidence](../../../docs/architecture/linux-clean-host-release-evidence-boundary.md).

The same Linux runner also has one explicit C54 preservation
`uninstall-reinstall` operation. It runs `dpkg --remove` only after reboot
evidence, requires the completed C54 receipt to name the exact installation
and release with `preserve-mutable-data`, observes absent package/services/
immutable root but present data root, and only then runs `dpkg --install` and
observes the reinstalled state. The current Linux C54 package-manager hand-off
does not terminally support purge; it must not be represented as a preserving
removal or a verified C24 purge.

When C24 `service-registration` is `verified`, it must additionally record
all three `ObservedHostServiceRegistration` facts (`host-agent`,
`host-edge-proxy`, and `host-update-handoff-supervisor`) with their manager, name, `registrationState=registered`,
and observation time. The delivery verifier compares those facts to C23
`requiredHostServiceRegistrations`; a matching package alone cannot silently
prove a different or partial Host service set.

The checked-in source inventory SBOM is a reproducible pre-release input
inventory. It includes the Runtime Console source modules and declared direct
Electron/Electron Builder/React/TypeScript sources, while `interfaces/tooling/verify_npm_license_policy.mjs`
checks every third-party package-lock license value against the explicit
permissive policy. It is not release-artifact evidence.
`tooling/release_artifact_sbom_notices.py` is the release-process C24 helper:
it accepts exactly one C23-selected installer, an explicit reviewed subset of
policy component IDs, a matching clean-Host runner ID, and a caller-supplied
timestamp. It publishes an installer-SHA-bound SPDX, an aggregated component
notice file, an evidence document, and a C24 `sbom-and-notices` proof fragment.
It never discovers components, installs the artifact, or edits
`release-delivery-proofs.v1.json`. C74
`tooling/release_delivery_proof_attachment.py` is the only reviewed attachment
workflow: it verifies caller-presented evidence bytes against the fragment SHA,
permits only a `pending` C24 stage to become terminal, and writes a new
immutable proof-set candidate plus review record. It never changes the source
template. `make release-ready` accepts an explicit
`RELEASE_DELIVERY_PLANS_DOCUMENT`, C24 candidate
`RELEASE_DELIVERY_PROOF_SET_DOCUMENT`, and
`RELEASE_DELIVERY_PROOF_ATTACHMENT_REVIEW_DOCUMENT`. It independently fixes
the C74 source to the checked-in canonical C24 template, so an intermediate
candidate cannot become the source of an unverified review chain. See
[Release Delivery Proof Attachment Boundary](../../../docs/architecture/release-delivery-proof-attachment-boundary.md).

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

On macOS, the operator receives **one** C23-selected Runtime Platform PKG.
C47 selects one already-built `VitalServer Runtime Platform.app`; C48 records
its fixed `/Applications/VitalServer Runtime Platform.app` path, entrypoint,
and complete bundle-tree digest. The PKG composer copies that bundle together
with Host services, while the package verifier expands the PKG and proves the
same C48 identity again. C53 remains the Host-installed bootstrap
configuration consumed by the app; the app still cannot create C52, C53, or a
Host service. An explicit C54 removal proves the same bundle through C49 and
removes it only when its full tree still matches C48; a changed or unreadable
application remains an operator-visible failed removal rather than being
silently deleted.

C71 and C72 remain the standalone Runtime Console artifact/delivery-kit
boundaries for platforms or channels that intentionally distribute a separate
desktop installer. They are not the macOS Runtime Platform installation path.
When used, the composer verifies C23's expected Host-installer name, C71's
Console platform/name/hash/size, and the platform's exact C53 bootstrap path
(Linux is `/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json`).
It does not claim a kit installed successfully; that remains C24 evidence.

`platformctl` is part of the Host installer rather than a third operator-kit
artifact. Each platform's C48 immutable release slot places it at
`current/bin/platformctl` (or `platformctl.exe` on Windows). It is a read-only
operator utility, not a service: it receives an explicitly named C52 local
control descriptor and never discovers installation state, deployment
configuration, or a remote endpoint.

Before an operator starts either OS installer, the release process can verify a
downloaded kit with the named read-only boundary:

```sh
make -C runtime-platform operator-delivery-kit-verify \
  OPERATOR_DELIVERY_KIT_DIRECTORY=/absolute/path/to/operator-delivery-kit
```

It validates the C72 manifest and the exact copied Host-installer and Runtime
Console bytes. After Host installation, an operator can additionally name the
installed C53 bootstrap file with
`OPERATOR_DELIVERY_KIT_VERIFY_BOOTSTRAP_CONFIGURATION=/absolute/path/to/runtime-console-bootstrap.json`;
the verifier checks its schema, OS-specific path, and the C72-recorded hash.
It never discovers that path, installs software, or claims C24 proof.

The Linux product kit selects the native Linux Console DEB when it is built on
the Linux release runner. C71 also permits an AppImage for a portable Linux
Console distribution, but a macOS or Windows workstation must not relabel a
cross-host archive as a Debian package: the packager rejects that request
before emitting C71. The CI Linux runner composes the selected C48 DEB through
real `dpkg` removal lifecycle proof, then publishes its C72 with the native
Console DEB. The Linux and Windows CI jobs retain their C72 kit as a 14-day
GitHub Actions artifact for operator evaluation; this makes the exact installer
bytes and C71/C72 receipts retrievable without treating a CI archive as a
release. The workflow also supports an explicit manual dispatch when an
operator needs a fresh candidate kit without waiting for a new pull request or
`main` push. A downloaded kit is still not a claim that systemd/SCM services, the
external Guest, VitalServer, or a standard operator account are usable; those
are C24 observations from a dedicated clean Host.

The macOS release build still requires the release operator to explicitly
provide C42/C43 Guest boot/root-storage inputs and the ARM64 Node distribution
before C41/C47 assembly. A CI runner must not discover or substitute those
selected inputs. Once assembled, the resulting PKG already contains the
operator app; no second macOS Console installer is required.

`tooling/guest_artifact_compilation_input_assembler.py` is the C41
`GuestArtifactCompilationInputAssembler`. It alone translates named
build-machine source files into the identity-only C35 input root, C35 command,
and C41 receipt. It does not select missing sources, invoke a builder, or claim
compile/boot/install success. See [Guest Artifact Compilation Input Assembly](../../../docs/architecture/guest-artifact-compilation-input-assembly-boundary.md).

`tooling/native_guest_artifact_input_preparer.py` prepares the analogous
amd64 C41 declaration for a Windows Hyper-V or Linux KVM/libvirt Guest. It
copies the selected C37/C38/C39/C44—and only external C44's selected C46—into
a new release workspace, binds architecture-suffixed amd64 artifacts, and
leaves `boot` absent because native UEFI providers boot the raw disk directly.
It rejects an arm64 C39, a missing external C46, and an unused C46 under a
bundled topology before writing any release input. It neither chooses between
Windows and Linux nor composes an MSI/DEB; C62 selects the provider and its
native machine storage separately after C65 exists.

`tooling/guest-linux-boot-artifact-extractor/` is the C42
`GuestLinuxBootArtifactExtractor`. It turns a caller-declared, immutable
raw ARM64 Linux source disk into kernel/initrd/root-storage release-build
inputs and a receipt. Its source filesystem is either the whole raw ext4 disk
or one declared ext4 partition; each boot resource is either an exact Guest
path or a separately identified external artifact. A QCOW2 input must reach
C42 through a C73 receipt. It has no authority to acquire an image, select a
Linux release, boot a Guest, or claim C24 evidence. See [Guest Linux
Boot Artifact Extraction](../../../docs/architecture/guest-linux-boot-artifact-extraction-boundary.md).

`tooling/guest_linux_source_disk_materializer.py` is C73. It converts one
caller-declared ARM64 QCOW2 image to a raw disk with a separate receipt before
C42 is admitted. It neither selects a partition nor extracts boot resources;
see [Guest Linux Source Disk Materialization](../../../docs/architecture/guest-linux-source-disk-materialization-boundary.md).

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
Process Supervisor binary and C37 deployment configuration, the C59 Guest
Product Release Manager binary and configuration, C38
`guestProductServiceManagerDeploymentConfigurationArtifact`, C39
`guestProductBootstrapConfigurationArtifact`, and C44
`guestProductVitalServerTopologyDeploymentArtifact`. The builder produces two
explicit storage artifacts: writable RAW `guest-root` and a read-only RAW
`guest-product-bootstrap` image containing the Guest-visible ISO9660
filesystem. A historical non-product C35 command may name none
of the Product inputs.

`tooling/guest_node_services_bundle_composer.py` produces one explicit
architecture-suffixed C35 input—`guest-node-services-linux-arm64` or
`guest-node-services-linux-amd64`—consumed by the matching C39. Its declared
contents are the caller-supplied matching Linux Node distribution, built
Recorder Gateway, built Lab Recorder Runner, their already-prepared runtime
dependencies, and the selected scenario catalog. It validates the ELF64
machine value before packaging, so a Host Node binary or the other Guest
architecture cannot enter the bundle. It does not download Node, run npm,
compile TypeScript, select a scenario, or start a process. C39 installs that
one bundle under `/opt/vitalserver`; C37 must then reference its Node
executable, both programs, and catalog path exactly.

`tooling/macos_development_release_input_preparer.py` is a development-only
release-input boundary for the unsigned macOS package workflow. It accepts
already-built Host/Guest artifacts plus explicit C42 kernel/initrd and C43
root-storage inputs, copies the selected desired configuration documents into
a new release workspace, and writes C41 and C47 declarations. It does not
download a Linux image or Node distribution, compile any artifact, execute
C41/C35/C47, or claim installation evidence. The resulting C47 selects an
unsigned Installer package and an ad-hoc entitlement signature only for the
VM Supervisor; neither policy is a Developer ID distribution claim. Invoke it
through `make macos-development-release-input-prepare` with a new workspace
whose `artifacts/` directory was prepared explicitly. The command fails rather
than replacing prior declarations, artifacts, package output, or evidence.

`make macos-development-release-artifacts-build` is the preceding executable
artifact-build adapter. It compiles the declared Host and Guest binaries, the
Guest telemetry collector, and the immutable Guest Node Services archive from
an explicitly supplied Linux ARM64 Node distribution. It does not acquire
Node, C42 boot resources, or C43 root storage. All outputs are first built in
one private release-workspace staging directory; only when every declared
artifact is present and non-empty is the directory atomically published as
`artifacts/`. A failed build cannot leave a reusable partial artifact set, and
an existing `artifacts/` directory is always rejected rather than replaced.

`make macos-development-guest-boot-input-assembly` is the separate C42/C43
input workflow. Its caller must provide one immutable raw ARM64 disk, explicit
whole-disk-or-partitioned ext4 layout, source identity/origin/release, and one
source choice for each boot resource. Cloud images may name independently
identified kernel/initrd artifacts; C42 never treats absent `/boot` files as a
reason to guess another source. A QCOW2 source first goes through C73. The
workflow asks C42 for `boot/Image`, `boot/initrd.img`, and standalone ext4
root storage, then asks C43 to make the declared MBR `/dev/vda1` root image.
It publishes the three result paths only below a new `guest-boot-inputs/`
directory after both effects have succeeded. The retained receipt intentionally
contains only output-relative identities; it does not retain a build Host
source path. No source is downloaded or selected by this command.

For a new, empty development release workspace,
`make macos-development-release-package-build` sequences the artifact build,
C42/C43 input assembly, C41/C47 input preparation, and C47 package assembly.
It forwards the same explicit source, identity, topology, and release-ID
variables to each owner. A workspace is intentionally one build attempt: each
completed child output is immutable and an existing output is rejected. A
failed attempt is available for diagnosis but is never reused as a new release.

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
the supplied non-secret C46 delivery-and-library configuration to that provenance. A manually created
or tampered C34/C35/C39/C44/C46 input cannot compose a product PKG, and a
tampered C34/C35 package payload cannot verify. PKG composition and verification
results are build results, **not** C24 artifact-integrity, installation,
registration, listener binding, reboot, update, rollback, or uninstall proof.
They require C23 `ReleaseDeliveryPlan.intendedInstallerArtifact` to agree with the output PKG basename,
all three required Host launchd plist labels, C33 `installation.productVersion`,
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
C51 archive credential material is never package payload or evidence: a later
explicit secret owner provisions it at the C37-declared private Guest path.

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
rather than editing `release-delivery-proofs.v1.json` itself; C74 attaches the
reviewed fragments into a separate immutable candidate. See [macOS Clean-Host
Release Evidence](../../../docs/architecture/macos-clean-host-release-evidence-boundary.md)
and [Release Delivery Proof Attachment](../../../docs/architecture/release-delivery-proof-attachment-boundary.md).
