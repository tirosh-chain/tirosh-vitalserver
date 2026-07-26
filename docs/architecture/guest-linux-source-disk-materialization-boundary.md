# Guest Linux Source Disk Materialization Boundary

## Purpose

C73 `GuestLinuxSourceDiskMaterializer` converts exactly one caller-declared
ARM64 QCOW2 source image into one raw disk image. It exists because a cloud
image's QCOW2 container format and the raw bytes consumed by C42 are different
artifacts with different identities.

It is deliberately not an image downloader, partition selector, boot-artifact
extractor, Guest provisioner, or package installer.

## Ownership and flow

```text
release caller selects QCOW2 + origin + digest
                 │
                 ▼
C73 verifies source → qemu-img convert -O raw → raw disk + C73 receipt
                                                     │
                                                     ▼
                                    C42 verifies raw identity and receipt
```

The caller owns source acquisition and the selected `qemu-img` executable.
C73 owns only the conversion effect and its receipt. C42 owns selection of the
raw disk's ext4 filesystem and extraction of the boot/root inputs; it does not
reinterpret the QCOW2 URL as the identity of raw bytes.

## Contract and failure rules

- The declaration fixes the QCOW2 source's absolute build path, HTTPS origin,
  release text, size, SHA-256, ARM64 architecture, and desired raw output ID.
- C73 first verifies the exact QCOW2 bytes, then requires `qemu-img info` to
  report `qcow2`; it runs only fixed conversion arguments and requires a raw,
  sector-aligned output.
- The receipt retains source and raw identities but no build-machine path.
- A missing tool, wrong source format, failed conversion, invalid output, or
  existing output directory fails the operation. No empty raw disk or partial
  receipt is published.

## What C73 does not prove

A C73 receipt is not proof that the raw disk contains ext4, that a selected
partition is bootable, that kernel/initrd resources exist, that a VM booted,
or that a package was installed. Those facts belong to C42/C43, Guest boot
acceptance, and C24 respectively.

## Verification

```sh
make -C runtime-platform guest-linux-source-disk-materializer-test
```

The release invocation is explicit and requires a caller-created C73
declaration and new output directory:

```sh
make -C runtime-platform guest-linux-source-disk-materialize \
  GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_DECLARATION=/absolute/c73.json \
  GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_OUTPUT_DIRECTORY=/absolute/new-output \
  GUEST_LINUX_SOURCE_DISK_QEMU_IMG_EXECUTABLE=/absolute/qemu-img
```

Related boundaries: [Guest Linux Boot Artifact Extraction](guest-linux-boot-artifact-extraction-boundary.md)
and [Guest Root Storage Partition Assembly](guest-root-storage-partition-assembly-boundary.md).
