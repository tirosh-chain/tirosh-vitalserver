# Guest Product release update composer

`guest-product-release-update-composer` is a release-process tool. It turns
one explicit build-local source selection document into a new prepared payload
for the existing generic `release-composer`.

It owns no Host or Guest runtime state and does not sign a bundle. Its output
contains exactly these release-selected bytes:

- `payload/host-updater`, the C25-selected next updater;
- one Guest Product archive for C26 apply and, only when selected, one archive
  for its reverse rollback transition;
- the C55 `guest-product-release-effect-executor` binary;
- generated C61 executor configuration, with the fixed Host-loopback C32 to
  C59 endpoint and explicit release compare-and-swap transitions;
- generated C26 `product-update.json`; and
- `release-bundle-composition.json`, the input that generic
  `tooling/release-composer` uses to calculate C25 artifacts and sign them.

The input's absolute source paths are deliberately build-local. They are read
once as regular, non-symlink files, copied to a new output workspace, and then
replaced by C26 payload-relative paths plus calculated SHA-256 and size. They
are not emitted as C25/C26/C61 values and therefore never become a Host or
Guest runtime dependency.

The currently concrete C32 bridge is the macOS arm64 Virtualization provider,
so this composer rejects other targets instead of pretending that the same C61
activation path exists on Windows or Linux. Cross-platform C25–C31 contracts
remain shared; a platform acquires a concrete update effect only with its own
explicit bridge/effect configuration.

Usage:

```sh
guest-product-release-update-composer \
  --composition /absolute/release/guest-product-release-update-composition.json \
  --output-directory /absolute/release/prepared-guest-product-update

release-composer \
  --composition /absolute/release/prepared-guest-product-update/release-bundle-composition.json \
  --payload-directory /absolute/release/prepared-guest-product-update/payload \
  --private-key /absolute/release/release-key.base64 \
  --output-directory /absolute/release/signed-bundles
```

Both output directories must be new. Neither tool replaces existing release
evidence.
