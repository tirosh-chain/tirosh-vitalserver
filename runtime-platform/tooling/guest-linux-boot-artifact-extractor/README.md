# Guest Linux Boot Artifact Extractor

`guest-linux-boot-artifact-extractor` is the C42 release-build executable.
It reads one explicitly declared whole-disk ext4 Linux source image and
atomically publishes exactly the declared **uncompressed ARM64 Linux boot
image**, initial RAM disk, raw root-storage copy, and C42 receipt. The source
image's gzip `/boot/vmlinuz` representation is never passed through as though
it were a `VZLinuxBootLoader` input.

It does not download or select an operating system, inspect an existing VM,
build a partition table, change kernel arguments, boot a VM, or claim a
package-install result. The caller owns source acquisition and C42
declaration; a later explicit root-storage layout assembler converts the
whole-disk source into the C43 raw root base before C35 composes the separate
C40 bootstrap volume.

```sh
guest-linux-boot-artifact-extractor \
  --guest-linux-boot-artifact-extraction-declaration /absolute/C42.json \
  --output-directory /absolute/absent-output-directory
```

The extractor writes `completedAt` into its C42 receipt after it has extracted
and verified the declared artifacts. Callers do not supply that operational
fact as a command argument.

The command fails without publishing an output directory when the declaration,
source identity, guest filesystem, declared boot resources, or output contract
is invalid. Published C42 receipts intentionally omit the local source path.

Run focused verification from `runtime-platform/`:

```sh
make guest-linux-boot-artifact-extractor-test
make guest-linux-boot-artifact-extractor-cross-platform-build
```
