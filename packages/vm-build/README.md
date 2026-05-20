# VitalServer VM Build

Build-machine tooling for preparing VitalServer VM artifacts.

```sh
uv run --project packages/vm-build vitalserver-vm-build --help
```

Commands:

```text
ubuntu
cloud-init
docker-images
rootfs-base
nginx-bundle
update-bundle
verify-update-bundle
render-template
```

Create an immutable rootfs base from a clean VM disk:

```sh
uv run --project packages/vm-build vitalserver-vm-build rootfs-base \
  --source .tmp/vitalserver-vm-golden/runtime/vm-disk.img \
  --output .tmp/vitalserver-vm-pkg/rootfs-base.raw.gz
```

Build the pinned nginx bundle declared in `vm-build.toml`. The default input is the local release artifact cache at `.artifacts/nginx/macos/bin/nginx`; create that artifact from the pinned local source before bundling:

```sh
make vm-nginx-artifact

uv run --project packages/vm-build vitalserver-vm-build \
  --config apps/vitalserver-vm-launcher/Support/Build/vm-build.toml \
  nginx-bundle \
  --bundle-dir .tmp/vitalserver-vm-pkg/nginx-bundle
```

The artifact cache is not committed. The bundle command validates the binary against the pinned `expected_version` and copies non-system dylibs into the package bundle.

Example with update migrations:

```sh
uv run --project packages/vm-build vitalserver-vm-build update-bundle \
  --version 0.1.1 \
  --runtime-version 0.1.1 \
  --output-dir dist/update-bundles \
  --rootfs-base .tmp/vitalserver-vm-pkg/rootfs-base.raw.gz \
  --migration release/migrations/001-example
```

Update bundle contract:

| artifact | builder behavior | installed runtime apply behavior |
|---|---|---|
| `rootfs-base.raw.gz` | copied into bundle and listed as `rootfs-base` | verified, backed up, and used to replace installed rootfs base |
| migrations | copied under `migrations/` | verified and executed if executable |

Runtime `.pkg`, app replacement, and runtime tool replacement are not part of the
current update bundle contract. Add a new artifact type and Swift apply behavior
together when that update path is needed.

`signature` is currently written as `unsigned`. It is a fixed bundle slot for
release hardening, not an active cryptographic verification step yet.

This package is for build machines only. Installed Mac mini runtime logic stays in
the Swift `vitalserver-vm` CLI.
