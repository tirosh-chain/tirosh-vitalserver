# Guest Root Storage Partition Assembly Boundary

## Purpose

`GuestRootStoragePartitionAssembler` is the C43 Release-build owner that turns
one C42 **whole-disk ext4** root-storage output into one explicit raw Guest
root disk with an MBR root partition. It exists because `whole-disk ext4`
and `/dev/vda1` are different storage facts:

- C42 publishes the source filesystem unchanged as `/dev/vda` bytes.
- C43 writes an MBR, names `/dev/vda1`, and copies those C42 bytes into that
  exact partition.
- The later Guest-owned bootstrap can then use that disk as its root storage;
  C43 itself never writes Guest Product files.

No component is allowed to collapse those three facts into an implicit
“root disk.” A guest kernel root argument, MBR sector offset, partition type,
and filesystem bytes must agree by explicit contracts.

## Vocabulary and ownership

| Name | Owner | Meaning |
| --- | --- | --- |
| C42 receipt | Guest Linux boot artifact extractor | identity evidence for the whole-disk ext4 root-storage output |
| C43 `GuestRootStoragePartitionAssemblyDeclaration` | Release input author | C42 receipt identity, source root-storage identity, and all target MBR/root-partition facts |
| `GuestRootStoragePartitionAssembler` | Release build | verifies C42 receipt/source identities and atomically writes one declared MBR-partitioned raw disk |
| C43 `GuestRootStoragePartitionAssemblyReceipt` | Guest root storage partition assembler | correlates C42 receipt, source identity, MBR layout, target raw-storage identity, and completion time |
| C32 `LinuxBootResources.guestRootDevicePath` | Host deployment author | carries the C43-proven Guest root partition into the kernel boot contract | derive a Guest partition from a Host file path |

No C39/C40 bootstrap configuration belongs to this table. C43 publishes only
the base disk identity; C39 describes Guest Product bootstrap intent and C40
describes the separate read-only `CIDATA` delivery volume.

The C43 declaration contains the build-machine paths only while C43 reads them.
The C43 receipt contains no source or receipt absolute path. A missing C42
receipt, receipt SHA mismatch, C42 root identity mismatch, unreadable source,
missing ext4 superblock signature, unsupported MBR partition size, or existing
output directory is a typed failure—not a blank disk and not a valid C39 base.

## Flow

```text
C42 receipt + whole-disk ext4 root storage
  -> C43 GuestRootStoragePartitionAssemblyDeclaration
  -> GuestRootStoragePartitionAssembler
  -> MBR (/dev/vda, start sector 2048, type 0x83)
  -> copied ext4 bytes in /dev/vda1
  -> C43 receipt + explicit raw root-storage base
  -> C41 input assembler -> C35 Guest artifact build
  -> C40 read-only `CIDATA` bootstrap volume
  -> Guest cloud-init owns all later root filesystem writes
```

C43 has no authority to download a Linux image, choose a root device, change a
kernel command line, add a second partition, resize a filesystem, write Guest
Product files, or boot a VM. C42 remains the ext4 source-image reader; C43
only verifies the C42 evidence chain and a defensive ext4 superblock signature
before its byte-placement effect.

C32 is a different owner and has a different responsibility: it explicitly
names `guestRootDevicePath=/dev/vda1` and requires the kernel command line to
carry `root=/dev/vda1`. This is not C32 inferring C43 internals; it is the
deployment author carrying the C43-published Guest-visible partition fact
across the Host/Guest boot boundary. A C32 configuration that names only the
raw Host disk image, or uses `root=/dev/vda`, is invalid for this C43 layout.

## Current executable evidence

`runtime-platform/tooling/guest_root_storage_partition_assembler.py` is the
portable C43 implementation. Its command requires a declaration, an absent
output directory:

```sh
python3 tooling/guest_root_storage_partition_assembler.py \
  --guest-root-storage-partition-assembly-declaration /absolute/C43.json \
  --output-directory /absolute/absent-output-directory
```

After it has written and verified the declared storage image, the assembler
records `completedAt` in its own C43 receipt. A release declaration or command
caller may choose inputs and an output destination, but cannot predeclare that
operational completion fact.

Focused tests cover successful MBR assembly and the two important no-output
failure cases: a tampered C42 receipt and a source with no ext4 signature.
On 2026-07-17 the tool accepted the actual C42 Ubuntu Noble ARM64 root-storage
output (2,061,500,416 bytes) and produced a 2,062,548,992-byte target raw disk.
The target has one MBR Linux partition, type `0x83`, beginning at sector 2048;
the partition bytes hash back to the C42 source identity. This is C43 storage
assembly evidence only. It does not prove C40 materialization, kernel boot,
systemd startup, package installation, or C24 clean-host delivery.

## Naming rule applied here

`GuestRootStoragePartitionAssembler` carries its bounded context (Guest),
managed concept (root storage partition), and effect role (assembler).
`execute_guest_root_storage_partition_assembly` visibly performs an effect;
`DeclaredWholeDiskRootStorage` and `DeclaredPartitionedRootStorage` prevent a
reviewer from confusing the source and target layouts. Names such as
`disk-builder`, `mbr-tool`, or `image-converter` would hide the C42/C43
contract boundary and are intentionally avoided.
