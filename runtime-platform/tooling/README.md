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

`guest-linux-boot-artifact-extractor/` is the C42
`GuestLinuxBootArtifactExtractor`. It reads only the named, identity-verified
whole-disk ext4 Linux image in a C42 declaration and atomically publishes its
declared kernel, initial RAM disk, raw root-storage copy, and receipt. It does
not acquire a distribution, infer guest boot paths, convert a whole disk to a
C39 partition, boot a Guest, or claim installation evidence. Its ownership
boundary is documented in [Guest Linux Boot Artifact Extraction](../../docs/architecture/guest-linux-boot-artifact-extraction-boundary.md).

`guest_root_storage_partition_assembler.py` is the C43
`GuestRootStoragePartitionAssembler`. It accepts only a C42 receipt plus the
matching immutable whole-disk ext4 root-storage source and atomically writes
the declared MBR `/dev/vda1` raw-storage base and C43 receipt. It neither
chooses a partition layout nor writes Guest Product files, boots a Guest, or
claims installation evidence. Its ownership boundary is documented in [Guest
Root Storage Partition Assembly](../../docs/architecture/guest-root-storage-partition-assembly-boundary.md).

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
receipt, both launchd registrations, and a changed boot-session identifier.
The installer effect requires root plus the explicit `--authorize-clean-install`
grant; reboot remains an operator action between a durable checkpoint and its
later observation. It writes C24 proof fragments for review rather than
mutating the canonical proof set. See [macOS Clean-Host Release
Evidence](../../docs/architecture/macos-clean-host-release-evidence-boundary.md).

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
