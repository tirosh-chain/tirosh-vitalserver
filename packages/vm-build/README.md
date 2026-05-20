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
update-bundle
verify-update-bundle
render-template
```

Example with update migrations:

```sh
uv run --project packages/vm-build vitalserver-vm-build update-bundle \
  --version 0.1.1 \
  --runtime-version 0.1.1 \
  --output-dir .tmp/update-bundles \
  --rootfs-base .tmp/vitalserver-vm-pkg/rootfs-base.raw.gz \
  --migration release/migrations/001-example
```

This package is for build machines only. Installed Mac mini runtime logic stays in
the Swift `vitalserver-vm` CLI.
