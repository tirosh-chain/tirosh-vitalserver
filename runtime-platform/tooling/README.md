# Tooling

Development-only tooling belongs here. It may validate repository structure, generate explicit artifacts, and run local verification.

Tooling must not become a runtime dependency or infer product state from missing artifacts, logs, or command output.

`verify_reference_fixtures.py` verifies only the quarantined fixture collection: manifest provenance, sanitization declarations, digest integrity, and registration. It never captures or reads legacy source files. `contracts.py` validates canonical contract source and generates the resolved OpenAPI bundle.

`macos_guest_artifact_manifest_composer.py` reads only the explicitly named C35
outputs and writes C34 `MacOSGuestArtifactManifest`. It calculates immutable
digest identity but does not compile, boot, or validate a Guest image.
`guest_product_systemd_service_unit_composer.py` validates C38 and writes one
new systemd unit text; it does not operate systemd.
`guest-product-bootstrap-volume-composer/` contains two explicit release-build
roles: `GuestProductBootstrapArtifactComposer` is the selected C35 builder
which copies declared boot/root artifacts and composes the second storage
artifact, while `GuestProductBootstrapVolumeComposer` converts C40 into a
read-only RAW bootstrap storage image containing a `CIDATA` ISO9660 partition.
Neither command mounts or edits a Guest
root filesystem. `macos_host_package_composer.py` consumes C32–C39 plus C44
and, when C44 selects external VitalServer placement, C46; it binds the
supplied Guest Product supervisor, C37/C38/C39/C44/C46 configuration, C35
builder identity, and the two C35 storage artifacts to C32/C34 provenance.
C46 is a non-secret delivery endpoint contract and deliberately has no
credential field. Its only external identity link is the declared integration
reference; any delivery authentication requires its own future secret contract,
not a cleartext C46 extension.
C46 is optional at the CLI only because bundled C44 does not use it; an
external C44 without C46 is a composition error, not an inferred endpoint.
The current C37 process plan does not yet declare a bundled VitalServer child,
so bundled C44 is also rejected explicitly rather than packaged as a product
that cannot start.
`macos_host_package_verifier.py` repeats that correlation after expanding the
PKG without installing it. None of these tools claim cloud-init, Guest boot,
or clean-host installation evidence.

`guest_artifact_compilation_input_assembler.py` is the C41
`GuestArtifactCompilationInputAssembler`. It reads only the absolute source
paths declared by C41, verifies their immutable identities, and atomically
publishes one C35 input root with a C35 command and C41 receipt. The published
C35 command and receipt do not contain a build-machine source path. It does not
select a builder/base/cache, invoke C35, or claim compile, boot, or install
success. Its input/output ownership boundary is documented in
[Guest Artifact Compilation Input Assembly](../../docs/architecture/guest-artifact-compilation-input-assembly-boundary.md).

`linux_host_package_composer.py` is the Linux release-tool counterpart for
one explicit C48 release. It creates a deterministic `ar`/DEB archive only
after the immutable slot, systemd unit bytes, and C53 bootstrap file match the
manifest hashes exactly. `preinst` rejects an unsupported direct version
upgrade before dpkg unpacks another release. `postinst` invokes the unpacked
payload Manager for C50 `preflight → quiesce → activate → finalize`; it does
not make an install-success decision itself. `prerm` invokes C54 and asks the
Manager to copy only the declared Manager executable and C48 manifest to the
declared, manager-owned purge-only completion transport. The later `postrm`
uses that durable copy, rather than either deleted package payload or
`/var/lib/dpkg/info`, to observe the explicit `removed` dpkg receipt and write
the C54 terminal receipt. A normal `dpkg --remove` then reaches
`deinstall ok config-files`; it deliberately preserves C48-declared mutable
data. The composer never invokes dpkg recursively, treats `apt purge` as
permission to delete data, or claims Linux clean-host/reinstall evidence.

`linux_host_release_input_preparer.py` precedes that composer. It copies five
caller-selected Linux Host executables and C33/C36/C53/C56/C58 documents into
one new C48 release source, writes the three matching systemd unit bytes, and
emits the sole DEB composition document. The agent unit explicitly owns the
`/run/vitalserver-runtime-platform` runtime directory used by its C33 Unix
socket. `make linux-host-release-artifacts-build` performs only the preceding
Linux/amd64 cross-compilation into a caller-named empty directory;
`make linux-host-release-input-prepare` and
`make linux-host-package-compose` each require one explicit absolute JSON
document. None of these commands invokes dpkg/systemd or presents a package as
clean-Host evidence.

The Runtime Console packager writes C71 only after portable artifact-format
checks: a UDIF footer for DMG, a PE header for NSIS, an AppImage Type 2 ELF
header, or all required Debian `ar` members for DEB. A Linux Console DEB may
be built only on a native Linux runner; invoking that target on macOS or
Windows fails before Electron Builder can leave an unrelated archive at a
`.deb` name. The Linux AppImage remains the portable Linux Console artifact.

`windows_host_release_input_preparer.py` precedes
`windows_host_msi_composer.py`. It copies explicitly selected Windows
Host binaries and C33/C36/C53/C56/C58 documents into one new immutable release
input, derives C70 service definitions and C48 hashes from those exact copied
bytes, and emits the matching MSI-composer document. It neither compiles the
binaries nor runs WiX, so it cannot claim an MSI, an SCM registration, or a
clean-Host installation result.

`windows_host_msi_composer.py` first validates one Windows C48 release—Windows MSI ProductCode, numeric MSI
receipt version, exact SCM registration declarations, immutable payload hashes,
and C54's `.exe` completion transport—then always writes a reviewable WiX v4
source document. It writes an `.msi` **only** when the caller explicitly
provides a WiX v4 executable and output path; source generation never pretends
that WiX, Windows Installer, or a clean Windows Host were available. The WiX
sequence runs C50 after `InstallFiles`: a fresh install passes the explicit
`windows-msi-installing` receipt phase, while a same-version repair passes the
ordinary observable receipt. It runs C54 before `RemoveFiles` from the
installed manager, and schedules C54's durable completion manager as a commit
action. Thus Windows leaves the running immutable release to MSI, rather than
asking an executing `.exe` to delete itself or recursively invoking `msiexec`.
Every declared payload file is also connected explicitly to the one MSI
Feature, so authoring cannot silently leave a C48 file outside the install
set. The generated source uses the open-source `WixToolset.Util.wixext`
`WixQuietExec64` action and has no second Manager binary.
`make windows-host-msi-compose` requires the caller to set one absolute
`WINDOWS_HOST_MSI_COMPOSITION` JSON path. That composition names every C48
release source, C53 source, lifecycle-state path, source output, and—only when
an MSI is truly requested—the installed WiX executable plus new MSI output.
There is intentionally no default release fixture or implicit WiX discovery.
`make windows-host-release-artifacts-build` is the preceding cross-compilation
step for an explicit empty output directory. Its six named `.exe` files are
the exact inputs that `windows_host_release_input_preparer.py` accepts; it
does not choose a deployment profile or produce an MSI.
`make windows-host-release-input-prepare` then consumes one caller-owned JSON
preparation document. It requires all source paths, the selected C23 plan,
release slot, ProductCode, and UpgradeCode explicitly. Its output prints the
new C48 path and the exact `windows-host-msi-compose` input; a Windows WiX
runner must still be named separately to produce an MSI.

`guest-linux-boot-artifact-extractor/` is the C42
`GuestLinuxBootArtifactExtractor`. It reads only the named, identity-verified
raw Linux disk in a C42 declaration and atomically publishes its declared
kernel, initial RAM disk, standalone ext4 root-storage copy, and receipt. C42
requires either one exact Guest filesystem path or one separately identified
external artifact for every boot resource; it does not infer a path, download
a replacement, or fall back between the two. Its source filesystem is either
the whole disk or an explicitly numbered partition. Its ownership boundary is
documented in [Guest Linux Boot Artifact Extraction](../../docs/architecture/guest-linux-boot-artifact-extraction-boundary.md).

`guest_linux_source_disk_materializer.py` is the C73
`GuestLinuxSourceDiskMaterializer`. It verifies a caller-selected ARM64 QCOW2
source and atomically converts it to one raw disk plus a receipt; C42 consumes
that receipt when it uses the materialized raw bytes. It does not acquire an
image, select a filesystem/partition, or extract boot artifacts. Its boundary
is documented in [Guest Linux Source Disk Materialization](../../docs/architecture/guest-linux-source-disk-materialization-boundary.md).

`guest_root_storage_partition_assembler.py` is the C43
`GuestRootStoragePartitionAssembler`. It accepts only a C42 receipt plus the
matching immutable whole-disk ext4 root-storage source and atomically writes
the declared MBR `/dev/vda1` raw-storage base and C43 receipt. It neither
chooses a partition layout nor writes Guest Product files, boots a Guest, or
claims installation evidence. Its ownership boundary is documented in [Guest
Root Storage Partition Assembly](../../docs/architecture/guest-root-storage-partition-assembly-boundary.md).

`macos_development_guest_boot_input_assembly.py` is a development-only C42/C43
workflow adapter. It accepts a caller-selected source image and complete source
identity, composes the two declarations, invokes C42 and C43 in one private
release-workspace staging directory, and publishes the resulting kernel,
initial RAM disk, MBR root storage, and output-relative receipt only when both
effects succeed. It does not acquire a Linux image, persist source-machine
paths into its retained receipt, select C41/C47, or claim Guest boot evidence.

`guest_artifact_compiler.py` is the C35 `GuestArtifactCompiler` release-build
orchestrator. Its required invocation names an absolute C35 command, one input
root, one selected `GuestProductBootstrapArtifactComposer` executable, an
absent output directory, and a positive builder timeout. It verifies every
C35 input and builder executable by size/SHA-256, runs no shell fallback,
rejects undeclared/symlink/empty output, then atomically publishes C34
`macos-guest-artifact-manifest.json` and C35
`guest-artifact-compilation-receipt.json`. It never downloads a Linux base,
searches a previous VM cache, chooses a builder, or claims boot/install proof.
Its exact selected-builder protocol and failure semantics are documented in
[GuestArtifactCompiler](guest-artifact-compiler.md).

`macos_host_package_composer.py` requires the C35 receipt beside C34 plus the
Guest Product process supervisor and C37/C38/C39/C44 configuration sources.
For external topology it also requires C46, checks its C35 consumed-input
identity, and compares C37 path, C39 installation path, C44 references, and
C46 provider identity before it materializes a PKG payload. It checks the
receipt's artifact-set ID, C34 SHA-256/size, C35 selected-builder identity,
and both C35 storage artifacts before it materializes a PKG payload.
It also validates C32 `GuestBootConsoleCapture` as an append-only path below
C33 `installation.dataDirectory`; postinstall creates that explicit empty file
without truncating a prior capture. This gives the long-lived VM supervisor a
declared diagnostic output target, rather than an inferred log filename.
The same C32 names `GuestRuntimeDiskProvisioning`: the immutable C34
`guest-root` release artifact is copied into the package `release` directory,
while the writable `runtimeDiskImagePath` and its receipt remain below C33
`installation.dataDirectory` and are deliberately absent from the payload.
`GuestRuntimeDiskProvisioner` creates those Host-persistent resources only
after it verifies C34 identity. The composer/verifier reject a package that
collapses the immutable release path and runtime attachment into one resource.
They select a C23 `ReleaseDeliveryPlan` explicitly and project it as
`MacOSHostPackageReleasePlan`. Its release-owned package version, expected PKG
filename, and required Host service launchd labels must agree with C33
`installation.productVersion`, the output artifact basename, and PKG
`PackageInfo.version`; none may be inferred from an artifact filename or
re-entered through a duplicate CLI flag.
`MacOSVirtualMachineSupervisorCodeSigning` is a separate required release-build
input from package signing: it signs only the staged
`macos-virtual-machine-supervisor` executable with the explicit
`com.apple.security.virtualization` entitlement, verifies both signature and
embedded entitlement, and never changes the supplied build artifact. A signed
PKG cannot be composed with an unsigned VM supervisor. The corresponding
source entitlement document is
`providers/macos-virtualization/MacOSVirtualMachineSupervisor.entitlements`.
`MacOSInstallerPackageSigning` is a different final-installer concern. The
composer first calls `pkgbuild` only to create a **component candidate**,
because current macOS may place build-Host extended attributes in AppleDouble
`._*` records inside its CPIO `Payload` and `Scripts`. The named
`MacOSInstallerComponentCpioArchive` boundary keeps declared CPIO entries,
removes those metadata carriers, regenerates the declared payload BOM and
`PackageInfo` inventory, and reassembles a distribution-only component
package. Only then does an explicitly selected `productsign` executable sign
the final package. An unsigned selection supplies neither identity nor
`productsign`; a signed selection supplies both and cannot pair with an
unsigned VM Supervisor.
`macos_host_package_verifier.py` repeats the C35-to-C34-to-C32 correlation
after expanding the PKG. For C46, the provenance chain is explicit: C35
records the exact consumed C46 bytes, C34 records the C40 bootstrap-volume
digest, and the verifier compares that C34 digest to the packaged RAW volume.
This is selected-builder provenance, not cloud-init, Guest-image boot, or
package-install proof.

`macos_clean_host_release_evidence_runner.py` is the Release process's macOS
C24 collection workflow. It names its state owner explicitly as
`MacOSCleanHostReleaseEvidenceJournal`; that SQLite file tracks evidence stages
only and is not a replacement for Host Agent or Guest Runtime state. Its
`MacOSCleanHostReleaseEvidenceCommandContract` makes the four external macOS
commands explicit inputs to the run, rather than an ambient execution
environment. The runner binds one C23-selected PKG SHA-256 at run creation,
requires an explicit signed installer-artifact release-identity observation,
then separately observes clean-host receipt and launchd absence, installer
receipt, all three launchd registrations, and a changed boot-session identifier.
The installer effect requires root plus the explicit `--authorize-clean-install`
grant; reboot remains an operator action between a durable checkpoint and its
later observation. It writes C24 proof fragments for review rather than
mutating the canonical proof set. See [macOS Clean-Host Release
Evidence](../../docs/architecture/macos-clean-host-release-evidence-boundary.md).

`windows_clean_host_release_evidence_runner.py` is the corresponding Release
process workflow for one C23-selected MSI. Its separate
`WindowsCleanHostReleaseEvidenceJournal` binds one MSI SHA-256, ProductCode,
explicit product-root path, and Windows command contract. It observes MSI
metadata/Authenticode, registry receipt, all three C23 SCM registrations, and
the CIM boot-session identifier through
`windows_host_installation_observation.py`. Only the explicit
`execute-clean-install --authorize-clean-install` operation invokes `msiexec /i`;
the preserving removal/reinstall operation separately requires
`--authorize-uninstall-reinstall`. The runner never reboots Windows and never
edits the canonical C24 proof document. An unknown
registry/SCM/root result is evidence failure, not clean-host absence. See
[Windows Clean-Host Release Evidence](../../docs/architecture/windows-clean-host-release-evidence-boundary.md).

`linux_clean_host_release_evidence_runner.py` is the Linux counterpart for one
C23-selected DEB. Its own SQLite journal binds the DEB SHA-256, C48-owned
Debian package identifier, immutable product root, mutable data root, and a
declared `dpkg`/systemd/kernel command contract. It treats `dpkg` residual
state and retained roots as non-clean state, not a successful absence. Only
the explicit `execute-clean-install --authorize-clean-install` command invokes
`dpkg --install`; preserving removal/reinstall separately requires
`--authorize-uninstall-reinstall`; reboot stays an operator effect between a
durable boot-ID checkpoint and later observation. See [Linux Clean-Host Release
Evidence](../../docs/architecture/linux-clean-host-release-evidence-boundary.md).

`release_artifact_sbom_notices.py` is a release-process-only C24 helper for the
`sbom-and-notices` stage. It binds the exact C23-selected installer SHA-256 to
an SPDX document and aggregated notices for an explicit, reviewed list of
policy component IDs. It emits an immutable evidence document and a separate
C24 proof fragment for the matching clean-Host runner. It neither discovers
components, installs a package, nor rewrites the canonical proof set.

`release_delivery_proof_attachment.py` is the separate C74 review application.
It takes one explicit C23 document, a source C24 set, C24 fragment files, and
the exact evidence bytes a reviewer inspected. It validates the candidate with
the same C23/C24 verifier, allows only `pending` source stages to settle, and
publishes a new proof-set candidate plus a C74 review record into a previously
absent output directory. It never edits the source template, follows evidence
URIs, uploads evidence, or claims installation success. See [Release Delivery
Proof Attachment](../../docs/architecture/release-delivery-proof-attachment-boundary.md).
Each matching OS clean-host runner supplies the fragment through its explicit
`write-stage-proof-fragment --stage <C24 stage> --output-proof-fragment <new absolute file>`
command. It writes only an absent caller-selected file and never mutates the
runner SQLite journal or canonical C24 template.

`macos_release_package_assembly.py` is the release-build application workflow
above those adapters. Its low-level
`MacOSReleasePackageAssemblyRequest` and
`assemble_and_verify_macos_release_package` coordinate one caller-declared C41
input assembly, its C35 compiler invocation, one C23-bound PKG composition,
and an explicit expanded-PKG verification. The workflow derives the selected
C35 builder only from the C41 receipt and rejects a package request whose
C34/C35/kernel/initrd/storage source paths are not exactly the declared C35
outputs.

For an operator-facing, reproducible entry point, C47
`MacOSReleasePackageAssemblyDeclaration` now supplies that request through one
explicit `--assembly-declaration` path. It names the C23 selection, C41/C35
execution destinations/times, Host artifacts, deployment documents, signing
inputs, PKG/pkgutil executables, and one new C47 receipt destination. It
rejects pre-existing or overlapping C41/C35/PKG/receipt output paths before
the first C41 copy, derives package Guest-output paths from C41, then checks
them again against actual C35 output. The emitted
`MacOSReleasePackageAssemblyReceipt` preserves C41/C35/C34/PKG identity
without build-machine source paths. C47 neither supplies a default
source/topology/signing identity nor turns a package build into C24
installation evidence. See [macOS Release Package
Assembly](../../docs/architecture/macos-release-package-assembly-boundary.md).
`make macos-release-package-assembly` exposes the same workflow only when the
caller supplies `MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION`; it has no
implicit declaration path.

`guest-product-release-update-composer/` is the product-specific release
preparation tool for the concrete C61 Guest Product update effect. It copies
only explicitly selected regular source artifacts to a new payload workspace,
derives C61 and C26 immutable identities from those bytes, and emits input for
the generic C25 signing tool. It never signs an update, activates a Guest
release, or reads Host/Guest runtime state.

`guest-product-release-archive-composer/` forms the C59-compatible immutable
tar+gzip artifact from one explicit Guest Product release tree. It preserves
only the safe filesystem shapes C59 can stage and hands its digest-bearing
output to the update composer; it never reads the active release or activates
one.

`host-platform-release-archive-composer/` forms the rigid C68 Host Platform
release archive from a release-process-selected C48 release tree, its three
declared service-definition files, and the C53 Runtime Console bootstrap. It
verifies every supplied byte against C48 and rejects undeclared release files,
then emits only `release/`, `service-definitions/`, and
`operator-interface/`. It neither selects `current` nor writes Host update
state; C68 remains the Host Installation Manager's runtime boundary.

`host_platform_release_transition_evidence.py` is the release-process reader
for the later C24 `update` and `rollback` stages. It binds exact C29, C28,
C55, C48, and C49 JSON input bytes to the selected C23 target plan and writes
a new evidence document only when the C29/C55 source documents satisfy their
published schemas and their IDs, layer, operation, artifact SHA-256, and
C28/C55 correlation agree **and** C49 proves the declared C48 package,
immutable slot, `current` activation, service definitions, C50 paths, and
terminal transaction. It cannot execute an update, activate/restore C48,
infer the active release from a package receipt, or edit canonical C24 proof
state. An OS clean-Host runner still has to establish the physical clean-Host
conditions before C24 can be marked verified.

The macOS, Windows, and Linux clean-Host evidence runners now expose
`record-host-platform-update` and `record-host-platform-rollback`. Each command
requires an explicit C23 document plus C29 journal, C55 receipt, C48 manifest,
and C49 footprint paths; it invokes the transition reader and immediately
re-observes the native package receipt, all three service registrations, and
the platform's declared product roots where the runner owns that observation.
The runner writes a failed C24 fragment when that contract chain or the fresh
OS observations disagree. It never executes an update itself. A successful
update and a failed-update rollback are distinct scenarios, so one evidence
journal deliberately rejects an attempt to record both.

`guest-bundled-upstream-image-set-archive-composer/` creates the deterministic
C64 image-set archive from explicit local Compose and OCI/Docker image archive
inputs. It writes the `image-set.json`, `compose.yaml`, and `images/*.tar`
layout that C64 validates, but does not interact with Docker or Guest state.
Its output identity is an explicit C66/C55 input rather than a side effect of
Guest Product bootstrap.
