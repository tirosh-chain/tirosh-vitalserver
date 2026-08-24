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

Direct CLI verification can name the installed runtime home in the invoking
shell:

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime verify-update-bootstrap \
  <bundle.tar.gz>
```

That is operator intent, not proof that the root Platform Agent worker used
the same value. `prove-update-bootstrap` and apply-smoke do not have a
persisted/observable owner for the verify process environment. Success against
the installed trust store, absence of `/var/root/.tirosh`, logs, or the
current Platform Agent launchd environment must not be treated as that proof.

## Follow-up

Field proof of TS-220 is blocked until verify persists an explicit document
that records the resolved installed runtime home used to open the trust store.
The smallest producer-side contract is a verify admission/receipt written by
`verify-update-bootstrap` after `InstalledRuntimePaths` resolution, containing
at least:

- `schemaVersion`
- `command` = `verify-update-bootstrap`
- `resolvedRuntimeHome` = the exact `VITALSERVER_VM_HOME` used
- `trustStorePath` = the path actually opened
- `updateId` / bundle identity
- `observedAt`
- process owner identity (`uid`/`euid`)

Missing, unreadable, and decode-failed receipts must stay distinct from a
successful verify. Do not reconstruct the home from source defaults or from
the current Platform Agent environment.

## Related Cases

- [TS-196: Helper UI uses the legacy update bundle engine](196_helper_ui_uses_legacy_update_bundle_engine.md)
- [TS-219: Swift bootstrap verifier rejects specification payload](219_swift-bootstrap-verifier-rejects-declared-payload.md)
- [TS-227: prove-update-bootstrap rejects persisted layer evidence](227_prove_update_bootstrap_rejects_persisted_layer_evidence.md)
