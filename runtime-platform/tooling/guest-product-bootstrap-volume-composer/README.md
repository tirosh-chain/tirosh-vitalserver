# Guest Product Bootstrap Volume Composer

`guest-product-bootstrap-volume-composer` is the release-build adapter that
creates one immutable NoCloud bootstrap storage image for one explicitly declared Guest Product
bootstrap. It does **not** edit a Linux root filesystem. The Ubuntu Guest's
cloud-init process owns the later write to its own ext4 root filesystem.

The name records the bounded context, managed concept, and role:

- **Guest Product**: the installed Guest runtime, recorder gateway, and their
  deployment configuration;
- **bootstrap volume**: the immutable, read-only NoCloud delivery medium; its
  Host-facing storage image and Guest-facing filesystem are named separately;
- **composer**: the release-build effect which translates an explicit plan into
  that medium.

The input plan identifies every source byte, final Guest destination, archive
operation, and service-unit link. The composer verifies those inputs before it
builds a RAW disk image containing one `CIDATA` ISO9660 partition with
`meta-data`, `user-data`, a bootstrap script, and the integrity-pinned payload.
No Host path search,
filesystem mount, root-image edit, or implicit source selection is permitted.

The generated cloud-init script is a Guest-owned effect: it verifies every
payload byte on the attached NoCloud volume, installs declared files, extracts
the declared recorder archive, enables the **declared** `serviceUnitName`, and
records completion only after all of those steps succeed. The service unit is
not an internal composer constant; C38 must make it explicit in the C40 plan.

The Recorder Gateway archive has two deliberately separate declarations:
`entryModePolicy` preserves archive file modes, while
`symbolicLinkPolicy=allow-relative-links-to-declared-regular-files` allows only
relative Node.js-style links whose resolved target is a regular file declared
by the same archive. The adapter rejects absolute links, escape paths,
directory/link-chain targets, hard links, and every other unsupported tar entry
type before the Guest receives the delivery volume.

`source` declaration order has no domain meaning. The composer sorts source
identities before generating the verification program and payload directory, so
equivalent plans produce the same ordering rather than inheriting incidental
map or caller order.

## Build evidence

```sh
make -C runtime-platform guest-product-bootstrap-volume-composer-test
make -C runtime-platform guest-product-bootstrap-volume-composer-cross-platform-build
```

The target compiles the selected C40 adapter for macOS ARM64, Linux ARM64, and
Windows AMD64. That proves the Host-side volume composer is portable; it does
not claim that a Guest has booted, cloud-init has discovered and mounted
`CIDATA`, or systemd
has started the declared service.
