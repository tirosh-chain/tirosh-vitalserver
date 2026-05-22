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
  --helper-version 0.1.1 \
  --bundle-kind product-update \
  --target-platform macos-arm64 \
  --component helperUI=0.1.1+macos.1 \
  --component updater=0.1.1 \
  --component supervisor=0.1.1 \
  --component vmDriver=0.1.1+macos.1 \
  --component serviceStack=2.3.4-stack.1 \
  --component vitalServer=2.3.4 \
  --output-dir dist/update-bundles \
  --app-bundle .tmp/vitalserver-vm-pkg/update-artifacts/app-bundle.tar.gz \
  --runtime-tools .tmp/vitalserver-vm-pkg/update-artifacts/runtime-tools.tar.gz \
  --nginx-bundle .tmp/vitalserver-vm-pkg/update-artifacts/nginx-bundle.tar.gz \
  --guest-deploy .tmp/vitalserver-vm-pkg/update-artifacts/guest-deploy.tar.gz \
  --migration release/migrations/001-example
```

The command writes `dist/update-bundles/update-bundle-<version>.tar.gz`.
`verify-update-bundle` accepts that tarball directly.

Update bundle contract:

The builder should emit one of two bundle kinds:

| bundle kind | intended UI | scope |
|---|---|---|
| `product-update` | Update tab | Helper UI, Updater, Supervisor, VM Driver, Service Stack, services, host proxy assets, migrations |
| `vm-image-update` | Danger Zone | VM Image/rootfs/base OS/kernel/initrd class artifacts |

| artifact | builder behavior | installed runtime apply behavior |
|---|---|---|
| `app-bundle.tar.gz` | copied into bundle when `--app-bundle` is provided | verified and used to replace the Helper app bundle |
| `runtime-tools.tar.gz` | copied into bundle when `--runtime-tools` is provided | verified and used to replace Updater/Supervisor/VM Driver tools |
| `nginx-bundle.tar.gz` | copied into bundle when `--nginx-bundle` is provided | verified and used to replace the host nginx bundle |
| `guest-deploy.tar.gz` | copied into bundle when `--guest-deploy` is provided | verified, staged for the guest, and activated through the guest update flow |
| `rootfs-base.raw.gz` | copied into bundle only when `--rootfs-base` is provided | verified, backed up, and used to replace installed rootfs base |
| migrations | copied under `migrations/` | verified and executed if executable |

Rootfs is intentionally optional. Product updates should omit `--rootfs-base`;
VM Image updates should provide it explicitly and should be routed through a
Danger Zone flow.

`signature` is currently written as `unsigned`. It is a fixed bundle slot for
release hardening, not an active cryptographic verification step yet.

This package is for build machines only. Installed Mac mini runtime logic stays in
the Swift `vitalserver-vm` CLI.
