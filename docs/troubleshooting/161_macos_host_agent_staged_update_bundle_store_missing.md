# macOS Host Agent exits when the staged update bundle store is absent

> ID: TS-161
> Category: Packaging / Host installation / Update
> Owner: macOS Host package postinstall (C23)
> Status: fixed; clean-install verification pending

## Symptom

A newly installed Runtime Platform package registers the three launchd
services, but `com.tirosh.vitalserver.host-agent` repeatedly exits with status
`1`. The C52 local-administration descriptor is absent, so `platformctl` and
the Runtime Console have no usable local control endpoint.

The Host Agent diagnostic is explicit:

```text
Host update bootstrapper initialization failed: configure update bundle store:
directory is missing, not a directory, or a symlink:
/Library/Application Support/VitalServerRuntimePlatform/data/update-bundles
```

## Cause

C33 selects the `staged` update-bootstrap adapter and explicitly names both
`bundleStoreDirectory` and `stagingDirectory`. The adapter deliberately
requires both directories to exist; it must not create or substitute one when
the installer did not provide the declared Host-owned store.

The macOS C23 postinstall script created the C33 state database directory and
the C56 handoff staging directories, but omitted C33
`updateBootstrap.bundleStoreDirectory`. Package composition succeeded because
the former verification checked the immutable payload and script provenance,
not whether every startup-required mutable directory was created.

## Fix direction

The C23 postinstall composer now includes C33
`updateBootstrap.bundleStoreDirectory` in its declared Host runtime directory
set. It is created before the installation manager activates launchd services.
The focused package-composer test asserts that the generated script contains
the declared bundle-store path.

## Verification

Before accepting a macOS package:

1. Run `make -C runtime-platform macos-host-package-composer-test`.
2. Install on a clean Host and confirm that the declared bundle-store directory
   exists before `com.tirosh.vitalserver.host-agent` starts.
3. Confirm that the Agent remains running and atomically publishes C52.
4. Confirm that `platformctl` and the packaged Runtime Console can read C52
   through the authorized local-administration transport.

## Prevention

- Every declared startup-required mutable Host path must be created by the
  installer before the service that owns it is activated.
- Do not make a service create missing package-owned deployment directories as
  a fallback; absence is an installation defect and must remain visible.
- Package verification must distinguish immutable payload proof from
  clean-install service-start proof.

Related boundaries: [Host installation lifecycle](../architecture/host-installation-lifecycle.md),
[Operator control surface](../architecture/operator-control-surface.md), and
[C23 macOS package composer](../../runtime-platform/tooling/macos_host_package_composer.py).
