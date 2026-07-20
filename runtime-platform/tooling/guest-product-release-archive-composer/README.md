# Guest Product release archive composer

`guest-product-release-archive-composer` turns one explicitly selected Guest
Product release tree into a new deterministic C59
`application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip` artifact.

It accepts only a non-symlink source directory and writes only a new archive.
The archive contains directories, regular files, and relative symbolic links
that resolve to regular files inside that same release tree. This is the same
safe link shape that the C59 Guest Product Release Manager can stage. Devices,
sockets, absolute links, escaping links, source traversal, and output
replacement are rejected.

The tool does not choose the release ID, read `/opt/vitalserver/current`,
activate the archive, or sign an update. The release process supplies its
result as the explicit apply or rollback archive source to
`guest-product-release-update-composer`.

```sh
guest-product-release-archive-composer \
  --release-source-directory /absolute/release-tree \
  --output-archive /absolute/release-artifacts/guest-product-0.3.0.tar.gz
```
