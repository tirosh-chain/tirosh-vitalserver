# Guest Artifact Build Boundary

## Purpose

This boundary turns a named Linux base and named Guest Product release bytes
into a **transportable Guest artifact set**. It does not claim that Linux
booted, cloud-init accepted the transport volume, systemd started a process, or
a Host package was installed.

The key ownership rule is simple: the Host build owns copying and packaging
artifacts; the Guest owns every write to its root filesystem and every systemd
operation after boot.

## Ubiquitous language

| Name | Owner | Responsibility | Must not do |
| --- | --- | --- | --- |
| C42 `GuestLinuxBootArtifactExtractor` | Guest Linux release build | identify kernel, initrd, and a whole-disk Linux root source | choose/download a Linux distribution or claim boot |
| C43 `GuestRootStoragePartitionAssembler` | Guest Linux release build | publish one MBR-partitioned, writable `guest-root` base | install Guest Product files |
| C41 `GuestArtifactCompilationInputAssembler` | release input assembler | copy declared build-machine files into one immutable C35 input root | choose a builder or a base image |
| C35 `GuestArtifactCompiler` | release build orchestration | verify C35 identities, invoke the selected composer, publish C34 and its receipt | mount/edit a Guest root or claim boot |
| `GuestProductBootstrapArtifactComposer` | selected C35 release builder | copy boot/root artifacts and compose the bootstrap RAW storage image from C37/C38/C39/C44 and external-topology C46 | discover sources or mutate Guest root bytes |
| C40 `GuestProductBootstrapVolumeCompositionPlan` | Guest Product bootstrap release composer | specify the immutable RAW storage image and Guest-visible `CIDATA` filesystem | represent Guest runtime state |
| `NoCloudGuestProductBootstrapVolumeAdapter` | C40 adapter | write one read-only RAW image containing an ISO9660 `CIDATA` partition | mount a Guest root or invoke systemd |
| cloud-init bootstrap program | Linux Guest | verify payloads, write Guest files, link/enable/start the declared service | infer a payload or treat a failed step as complete |
| C34 `MacOSGuestArtifactManifest` | C35 output adapter | record bytes, role, storage-image format, and Guest filesystem of boot/root/bootstrap artifacts | retain build-machine paths or prove boot |
| C32 `MacOSVirtualMachineConfiguration` | Host deployment author | name immutable root release input, Host runtime root target, and bootstrap attachment in declared order | attach immutable release bytes as Guest-writable runtime state |

## Artifact flow

```text
C42 Linux boot artifacts → C43 writable guest-root base
     + C37 process deployment + C38 service deployment + C39 bootstrap configuration
     + named Guest Product payload bytes
                                      │
                                      ▼
          C41 immutable C35 input root and selected composer identity
                                      │
                                      ▼
             C35 GuestArtifactCompiler → GuestProductBootstrapArtifactComposer
                                      │
                 ┌────────────────────┴─────────────────────┐
                 ▼                                          ▼
      writable RAW guest-root copy          read-only RAW image → CIDATA ISO9660 partition
                 └────────────────────┬─────────────────────┘
                                      ▼
        C34 role/storage-image-format/Guest-filesystem/digest manifest + C35 receipt
                                      │
                                      ▼
      Host provisioner verifies C34 root → creates C32 runtime root at index 0
                  C32 attaches runtime root and CIDATA at index 1
                                      │
                                      ▼
               Guest cloud-init performs Guest-owned root and systemd effects
```

The two storage artifacts deliberately have different roles:

| ID | Role | Storage image format | Guest volume filesystem | Host attachment | Mutation owner |
| --- | --- | --- | --- | --- |
| `guest-root` | `guest-root-storage` | raw | — | index `0`, writable | Linux Guest after boot |
| `guest-product-bootstrap` | `guest-product-bootstrap-volume` | raw | ISO9660, label `CIDATA` | index `1`, read-only | release build creates it; Guest only reads it |

The C35 compiler rejects an undeclared output, an output symlink, an empty
output, a missing output, duplicate input identity, or a storage artifact that
does not have this exact role/storage-image-format/Guest-filesystem/read-only
intent. C32 and C34 repeat that
intent so the macOS provider and package layer cannot silently reverse it.

## Evidence boundary

The following are presently distinct facts and must remain distinct:

1. C42/C43 prove input extraction and root-storage assembly.
2. C41 proves source selection and copying into a C35 input root.
3. C35/C34 prove selected-builder input/output correlation.
4. Guest boot smoke must prove kernel boot, CIDATA discovery, cloud-init
   completion, and service readiness.
5. C24 must prove package integrity, clean installation, registration, reboot,
   update, rollback, and uninstall on the target Host.

`guest-root` is intentionally writable only after it becomes a Guest runtime
disk. Therefore a boot-smoke harness must first verify the C34 digest of the
release artifact, create a run-scoped writable working copy, and point its
smoke-only C32 document at that copy. It must verify the C34 source digest
again after the Guest stops. Starting a VM directly from the C35/C34 output is
not a valid smoke test: normal Guest writes would turn release provenance into
runtime state and make a later package composition non-repeatable.

The same separation is required for installed product lifecycle: an immutable
release root source and a Host-owned persistent Guest runtime disk have
distinct C32 paths and owners. The package composer proves immutable payload
correlation, while `GuestRuntimeDiskProvisioner` verifies and creates the
separate writable disk before VZ construction. It deliberately rejects an
existing disk whose receipt does not match the configured release identity;
package update preservation, replacement, or migration remains an explicit
C24/update decision rather than an overwrite or default path.

Current focused tests prove that C35 leaves the declared root byte-for-byte
unchanged while it creates a non-empty RAW bootstrap image with a CIDATA ISO9660
partition. A separate local diagnostic smoke now proves that
`GuestRuntimeDiskProvisioner` creates a run-scoped workspace, retains it only
with a matching receipt, and can boot the ARM64 Guest through cloud-init and a
serial login prompt while the C34 source digest remains unchanged. It is still
not signed-PKG installation, Guest Runtime readiness, or C24 package proof.

Related boundaries: [Guest Product Bootstrap Volume](guest-product-bootstrap-volume-boundary.md),
[Guest Root Storage Partition Assembly](guest-root-storage-partition-assembly-boundary.md),
and [macOS Virtual Machine Supervisor](macos-virtual-machine-supervisor-boundary.md).
