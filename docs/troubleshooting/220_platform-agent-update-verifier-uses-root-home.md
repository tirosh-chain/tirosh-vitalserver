# Platform Agent Update Verifier Uses Root Home

> ID: TS-220
> Category: Update / Runtime Control
> Owner: macOS runtime
> Status: resolved

## Symptoms

The installed launcher verifies a stable update when its installed runtime home
is explicit, but verification started from the PWA fails:

```text
error: unavailable(
  path: "/var/root/.tirosh/config/update-bootstrap-trust-store.json"
)
```

The installed trust store is present at:

```text
/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json
```

## Cause

The Platform Agent runs as root. Its non-privileged verification adapter started
`vitalserver-vm` without the installed `VITALSERVER_VM_HOME` environment
contract. The launcher therefore resolved its documented per-user development
default below `/var/root/.tirosh`.

Privileged mutation commands already used the installed runtime home through the
shell command factory, but the read-only verification path bypassed that
factory.

## Fix Direction

- Process execution accepts an explicit environment overlay while preserving
  the inherited process environment.
- The Runtime Control update verifier supplies
  `VITALSERVER_VM_HOME=/Library/Application Support/VitalServerHelper/vm`.
- Process runner tests prove both the explicit runtime home and inherited
  `PATH` remain available.
- PWA verification must be tested through the installed Platform Agent, not
  only by invoking the launcher from a developer shell.

## Prevention

Installed path selection is a Host contract. A process must receive the
installed runtime home explicitly; it must not derive product state from the
service account's home directory.

Keep separate field proofs for direct CLI execution and the Runtime Control
worker because they have different process owners and environment boundaries.

## Evidence

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime verify-update-bootstrap \
  <bundle.tar.gz>
```

The PWA `POST /platform/update-bundles/verify` operation must then complete
against the same bundle and installed trust store without referencing
`/var/root/.tirosh`.

## Related Cases

- [TS-196: Helper UI uses the legacy update bundle engine](196_helper_ui_uses_legacy_update_bundle_engine.md)
- [TS-219: Swift bootstrap verifier rejects specification payload](219_swift-bootstrap-verifier-rejects-declared-payload.md)
