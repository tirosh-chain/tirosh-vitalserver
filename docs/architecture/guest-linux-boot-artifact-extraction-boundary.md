# Guest Linux Boot Artifact Extraction Boundary

## Purpose

`GuestLinuxBootArtifactExtractor` turns **one explicitly declared, immutable
ARM64 raw Linux source disk** into three named release-build inputs:

1. an uncompressed ARM64 Linux boot-loader kernel image,
2. an initial RAM disk, and
3. a standalone raw ext4 root-storage source.

It exists so that a later Guest image build never has to infer a base image,
search a cache, discover `/boot`, or download an operating system. The
extractor owns neither a VM nor a Linux distribution. Its only responsibility
is to verify declared source bytes and publish the declared files with their
immutable identities.

## Vocabulary and ownership

| Name | Owner | Meaning |
| --- | --- | --- |
| C73 `GuestLinuxSourceDiskMaterializationReceipt` | source-disk materializer | evidence that an approved QCOW2 source became the raw disk C42 consumes |
| C42 `GuestLinuxBootArtifactExtractionDeclaration` | Release input author | raw source identity, whole-disk-or-partitioned ext4 layout, exact boot source choice, and output paths |
| `GuestLinuxBootArtifactExtractor` | Release build | validates C42, reads the named image, and atomically publishes the declared files |
| C42 `GuestLinuxBootArtifactExtractionReceipt` | Guest Linux boot artifact extractor | correlates declaration digest, source identity, extracted kernel/initrd identities, root-storage identity, and completion time |
| C43 `GuestRootStoragePartitionAssembler` | Release build | copies C42 whole-disk ext4 root storage into an explicit MBR `/dev/vda1` target and publishes its own receipt |
| C41 `GuestArtifactCompilationInputAssembler` | Release input assembler | stages only the accepted C42 outputs and other named product inputs into the C35 input root |
| C39/C40 bootstrap delivery | selected Guest Product bootstrap artifact/volume composer | attaches a declared read-only `CIDATA` volume beside the root base; it does not select, extract, or edit a Linux base |

`sourceImage` is a build-machine input and its absolute path appears only in
C42 declaration. The receipt deliberately contains no build-machine path. A
missing source, non-regular source, SHA-256 mismatch, absent selected Guest
boot file, external boot-artifact identity mismatch, non-ext4 filesystem, or
pre-existing output directory is a typed extraction failure. None of those
meanings is an empty artifact set.

## Flow and capability boundary

```text
declared ARM64 QCOW2 -> C73 raw disk + receipt + C42 declaration
  -> GuestLinuxBootArtifactExtractor
  -> C42 receipt + boot/Image (decompressed ARM64 Linux kernel) + boot/initrd.img + standalone ext4 root source
  -> C43 GuestRootStoragePartitionAssembler + C43 receipt
  -> C43 partitioned root-storage base + C40 read-only bootstrap volume
  -> C41 input assembler
  -> C35 GuestArtifactCompiler
```

The C42 declaration selects either the whole raw disk as ext4 or exactly one
numbered ext4 partition. In the partitioned case, C42 publishes the selected
partition's bytes as a new **standalone whole-disk ext4** root source; it does
not pass a GPT/MBR source through to C43. Every boot resource separately names
either a Guest filesystem path or an external artifact with its own identity.
There is no filename search and no fallback between source kinds.

C43 names the eventual partitioned raw storage layout and the Guest kernel
must then name that partition as its root device. C43 is the separate owner
that creates the explicit partition table, copies the C42 standalone ext4
bytes into the declared partition, and emits its own receipt. Pretending that a
whole disk is `/dev/vda1`, or silently changing the kernel root argument, would
hide a boot-critical state transition. C39/C40 then provide a second,
read-only `CIDATA` attachment for Guest-owned first-boot installation; they
never modify the C43 root bytes on the Host.

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
has focused tests for whole-disk and explicit-partition extraction, selected
Guest-path resources, external boot artifacts, source identity mismatch,
external-artifact tampering, and a missing declared boot resource. The
repository builds it for macOS/ARM64, Linux/ARM64, and Windows/AMD64.

Historical whole-disk C42/C43/C40 boot evidence remains useful only for that
old declared source shape. It is not evidence for the new QCOW2->C73->
partition-source path, package installation, Guest Runtime readiness, or C24
delivery. The new path requires its own fresh release build and later boot
acceptance evidence.

Related boundaries: [Guest Linux Source Disk Materialization](guest-linux-source-disk-materialization-boundary.md),
[Guest Root Storage Partition Assembly](guest-root-storage-partition-assembly-boundary.md),
and [Guest Product Bootstrap Volume](guest-product-bootstrap-volume-boundary.md).

## Naming rule applied here

The module name is deliberately not `image-extractor`, `ext4-tool`, or an
implementation-step name. `GuestLinuxBootArtifactExtractor` tells a reviewer
the bounded context (Guest Linux), managed concept (boot artifacts), and role
(extractor). `ExecuteGuestLinuxBootArtifactExtraction` makes the filesystem
effect visible, while `ValidateGuestLinuxBootArtifactExtractionDeclaration`
names pure declaration validation. The concrete `go-diskfs` choice is confined
to an adapter-level dependency rather than defining the domain vocabulary.
