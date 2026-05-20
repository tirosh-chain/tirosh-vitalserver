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

Build the pinned nginx bundle declared in `vm-build.toml`:

```sh
uv run --project packages/vm-build vitalserver-vm-build \
  --config apps/vitalserver-vm-launcher/Support/Build/vm-build.toml \
  nginx-bundle \
  --bundle-dir .tmp/vitalserver-vm-pkg/nginx-bundle
```

Example with update migrations:

```sh
uv run --project packages/vm-build vitalserver-vm-build update-bundle \
  --version 0.1.1 \
  --runtime-version 0.1.1 \
  --output-dir dist/update-bundles \
  --rootfs-base .tmp/vitalserver-vm-pkg/rootfs-base.raw.gz \
  --migration release/migrations/001-example
```

This package is for build machines only. Installed Mac mini runtime logic stays in
the Swift `vitalserver-vm` CLI.
