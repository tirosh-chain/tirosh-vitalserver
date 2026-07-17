# Guest Linux Boot Artifact Extraction Boundary

## Purpose

`GuestLinuxBootArtifactExtractor` turns **one explicitly declared, immutable
ARM64 Linux source image** into three named release-build inputs:

1. an uncompressed ARM64 Linux boot-loader kernel image,
2. an initial RAM disk, and
3. a byte-identical raw ext4 root-storage source.

It exists so that a later Guest image build never has to infer a base image,
search a cache, discover `/boot`, or download an operating system. The
extractor owns neither a VM nor a Linux distribution. Its only responsibility
is to verify a declared source image and publish the declared files with their
immutable identities.

## Vocabulary and ownership

| Name | Owner | Meaning |
| --- | --- | --- |
| C42 `GuestLinuxBootArtifactExtractionDeclaration` | Release input author | source image identity, source filesystem layout, guest paths, and output paths to be extracted |
| `GuestLinuxBootArtifactExtractor` | Release build | validates C42, reads the named image, and atomically publishes the declared files |
| C42 `GuestLinuxBootArtifactExtractionReceipt` | Guest Linux boot artifact extractor | correlates declaration digest, source identity, extracted kernel/initrd identities, root-storage identity, and completion time |
| C43 `GuestRootStoragePartitionAssembler` | Release build | copies C42 whole-disk ext4 root storage into an explicit MBR `/dev/vda1` target and publishes its own receipt |
| C41 `GuestArtifactCompilationInputAssembler` | Release input assembler | stages only the accepted C42 outputs and other named product inputs into the C35 input root |
| C39/C40 bootstrap delivery | selected Guest Product bootstrap artifact/volume composer | attaches a declared read-only `CIDATA` volume beside the root base; it does not select, extract, or edit a Linux base |

`sourceImage` is a build-machine input and its absolute path appears only in
C42 declaration. The receipt deliberately contains no build-machine path. A
missing source, non-regular source, SHA-256 mismatch, absent guest boot file,
non-ext4 filesystem, or pre-existing output directory is a typed extraction
failure. None of those meanings is an empty artifact set.

## Flow and capability boundary

```text
immutable ARM64 Linux image + C42 declaration
  -> GuestLinuxBootArtifactExtractor
  -> C42 receipt + boot/Image (decompressed ARM64 Linux kernel) + boot/initrd.img + whole-disk ext4 root source
  -> C43 GuestRootStoragePartitionAssembler + C43 receipt
  -> C43 partitioned root-storage base + C40 read-only bootstrap volume
  -> C41 input assembler
  -> C35 GuestArtifactCompiler
```

The output is intentionally **whole-disk ext4** when the declared source uses
that layout. C43 names the partitioned raw storage layout and the Guest kernel
must then name that partition as its root device. C43 is the
separate owner that creates the explicit partition table, copies the declared
ext4 bytes into the declared partition, and emits its own receipt. Pretending
that a whole disk is
`/dev/vda1`, or silently changing the kernel root argument, would hide a
boot-critical state transition. C39/C40 then provide a second, read-only
`CIDATA` attachment for Guest-owned first-boot installation; they never modify
the C43 root bytes on the Host.

C42 proves only byte extraction. It does **not** prove that the selected
kernel can boot the selected root storage, that the initramfs contains needed
drivers, that systemd starts the Guest Product, or that a macOS package can be
installed. Those claims need later builder, boot-smoke, and C24 clean-host
evidence.

## Current executable evidence

The extractor is implemented as the self-contained Go module
`runtime-platform/tooling/guest-linux-boot-artifact-extractor/`. Its public
command names a C42 declaration, an absent output directory, and an explicit
output destination. After it has extracted and verified every declared
artifact, the extractor itself records `completedAt` in the C42 receipt. It
has focused tests for a successful ext4 extraction, a
source identity mismatch, and a missing declared boot resource. The repository
builds it for macOS/ARM64, Linux/ARM64, and Windows/AMD64.

On 2026-07-17, the executable was run against the explicitly declared Ubuntu
24.04 LTS Noble ARM64 cloud-image root filesystem. The source SHA-256 was
`92ee679ca9b748759aad9811821c1daef62a62608566331d4fc6f0f35ee48932`; the
extractor published a 59,009,416-byte uncompressed ARM64 `boot/Image`, a 29,236,667-byte initial RAM
disk, and a 2,061,500,416-byte byte-identical root-storage source. This is
local extraction evidence only—not a release approval, package, or C24
delivery claim. The resulting C42/C43/C40 artifact set subsequently reached
Ubuntu cloud-init and a serial login prompt through a local ad-hoc-entitlement
VZ supervisor; that distinct native boot evidence is recorded in
[TS-148](../troubleshooting/148_macos_virtual_machine_start_fails_before_guest_boot_console.md).
It is not Apple-signed package-install or Guest Runtime readiness proof. The image provenance is the official
[Ubuntu Noble cloud-image release](https://cloud-images.ubuntu.com/releases/noble/release/).

## Naming rule applied here

The module name is deliberately not `image-extractor`, `ext4-tool`, or an
implementation-step name. `GuestLinuxBootArtifactExtractor` tells a reviewer
the bounded context (Guest Linux), managed concept (boot artifacts), and role
(extractor). `ExecuteGuestLinuxBootArtifactExtraction` makes the filesystem
effect visible, while `ValidateGuestLinuxBootArtifactExtractionDeclaration`
names pure declaration validation. The concrete `go-diskfs` choice is confined
to an adapter-level dependency rather than defining the domain vocabulary.
