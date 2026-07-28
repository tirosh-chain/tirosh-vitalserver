# Product update composer

`product-update-composer` is the release-process owner that prepares one
complete Product update payload before signing.

Its build-local input selects:

- the next updater that will interpret the detailed update specification;
- an optional bundled-Upstream Container image-set transition;
- the required Guest Product release transition;
- an optional Host Platform release transition, always emitted last;
- one immutable effect executor and configuration identity per selected layer;
- explicit reverse rollback artifacts when available.

The input structure keeps each layer's transition and effect executor under
the layer that owns them:

```text
ProductUpdateComposition
├── bundledUpstreamImageSet (optional Container layer)
│   ├── apply / rollback
│   └── effectExecutor
├── guestRuntime (required)
│   ├── productRelease
│   │   └── apply / rollback
│   └── effectExecutor
└── hostPlatformRelease (optional, always last)
    ├── apply / rollback
    └── effectExecutor
```

The tool copies regular non-symlink source artifacts into a new immutable
workspace, derives their SHA-256 and size from copied bytes, generates the
layer-specific executor configurations, and writes:

- `payload/product-update.json`, the detailed Product Update Specification;
- `release-bundle-composition.json`, the generic bootstrap signer input; and
- the complete selected `payload/` tree.

The generic `release-composer` remains the only signer. Runtime state,
activation, and rollback outcomes remain owned by the installed layer-specific
managers and their typed receipts.

For the currently concrete macOS arm64 path:

```sh
product-update-composer \
  --composition /absolute/release/product-update-composition.json \
  --output-directory /absolute/release/prepared-product-update

release-composer \
  --composition /absolute/release/prepared-product-update/release-bundle-composition.json \
  --payload-directory /absolute/release/prepared-product-update/payload \
  --private-key /absolute/release/release-key.base64 \
  --trust-store /absolute/release/update-trust-store.json \
  --output-directory /absolute/release/signed-bundles
```

Both output directories must be new. Neither tool replaces existing release
evidence. The signer rejects a private key whose derived public key is not
present under the declared signing key ID in the selected Host Update Trust
Store.
