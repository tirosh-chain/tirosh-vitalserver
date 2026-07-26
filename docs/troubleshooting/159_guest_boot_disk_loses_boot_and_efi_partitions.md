# C43 root-only disk assembly drops the boot partitions

> ID: TS-159  
> Category: Guest artifact compilation / macOS virtualization / Packaging  
> Owner: Guest boot disk assembly (C43)  
> Status: active

## Symptom

A release package can be composed successfully and the macOS Supervisor can
return C21 `start` with `observedState=running`, but the actual Guest never
reaches runtime readiness. The Host bridges may accept a connection briefly and
then reset it while the Guest serial console reports a sequence like:

```text
Timed out waiting for device /dev/disk/by-label/BOOT
Timed out waiting for device /dev/disk/by-label/UEFI
Dependency failed for /boot.mount
Dependency failed for /boot/efi.mount
You are in emergency mode.
```

`start=running` is only the macOS Virtualization controller's state. It is not
proof that Linux mounted its required filesystems, cloud-init ran, or the Guest
Runtime became available.

## Cause

The old C43 implementation accepted C42's extracted standalone ext4 root
partition and copied it into a newly generated MBR disk at `/dev/vda1`. The
source Ubuntu disk was GPT and also contained its own EFI and `/boot`
partitions. Its root filesystem's `fstab` continued to require those labels,
but C43 had discarded their bytes.

The old output could therefore pass file identity and ext4 checks while being
neither a complete UEFI disk nor a bootable representation of the selected
source image.

The Ubuntu source used for the repair also keeps `vmlinuz` and `initrd.img` in
the separate `BOOT` partition. C42 owns one declared ext4 filesystem and must
not silently discover another partition. Trying to make C42 traverse that
partition with the current ext4 reader panicked on the real image, so accepting
that source kind would have converted a build dependency failure into a late
installer failure.

## Verification

Before treating a package as installable, collect three separate facts:

1. C43 receipt: source C42 receipt correlation, GPT root partition index/start
   sector, source/target size, and SHA-256 are valid.
2. VZ boot console: the complete GPT disk does not report missing `BOOT` or
   `UEFI` labels and reaches the declared Guest readiness contract.
3. Package installation acceptance: the package is installed on a clean Host
   and its Host/Guest readiness contract succeeds.

The first fact alone is build evidence. It cannot replace the latter two.

## Fix direction

C43 now takes the complete C42-correlated GPT source disk—not C42's extracted
root partition—as its boot-disk source. It validates the primary GPT header and
partition-entry checksums, caller-declared root partition `1`, explicit start
sector, and ext4 superblock, then copies the entire disk byte-for-byte. C41's
macOS development input adapter accepts only this explicit GPT partition-1
layout so an incompatible source fails before C42/C43 effects begin.

A previously built release workspace must not be reused. Re-materialize the
caller-selected source through C73 if needed, run C42/C43 with a new workspace,
then rebuild the package and execute the VZ boot/readiness smoke before
installation.

For a source whose boot bytes are outside C42's selected filesystem, the
release author first materializes those exact bytes as separate artifacts and
declares each as C42 `external-artifact` with its source origin, release, size,
and SHA-256. This is an explicit release-input step, not a C42 fallback. A
future multi-partition reader may be introduced only after it handles the real
image without panic and has an explicit contract and acceptance coverage.

## Prevention

- Do not convert a source root partition into a synthetic disk when the source
  has an EFI, boot, or other required partition.
- Keep the Guest root device, GPT partition index, and partition start sector
  explicit through C43 and C32; do not infer them from a file name or probe.
- Treat VZ controller `running`, package composition, and an installer success
  as separate facts from Guest readiness.
- Retain the boot console as Host-owned diagnostic evidence and make a missing
  readiness contract a release failure, not a retry/default path.

Related boundaries: [Guest Boot Disk Assembly](../architecture/guest-root-storage-partition-assembly-boundary.md),
[Guest Artifact Build](../architecture/guest-artifact-build-boundary.md), and
[Golden Disk Runtime Boot Proof Gap](070_golden-disk-runtime-boot-proof-gap.md).
