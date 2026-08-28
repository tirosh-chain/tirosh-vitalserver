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
the same value. The verify command now persists a verification receipt after
successful `InstalledRuntimePaths` resolution. `prove-update-bootstrap`
reads that receipt from `InstalledRuntimePaths.defaultInstalled`, not from
the proof process environment. It correlates the document to the current
update identity, the product-installed VM home
`/Library/Application Support/VitalServerHelper/vm`, the product-installed
trust store, and root `uid=0`/`euid=0`. That proves a root
`verify-update-bootstrap` execution over that bundle at the product-installed
path. It does not prove the caller was MacPlatformAgent. Two processes that
share a non-product `VITALSERVER_VM_HOME` cannot redefine the expected owner. Public CLI and apply-smoke can write the same
receipt. Success against the installed trust store, absence of
`/var/root/.tirosh`, logs, or the current Platform Agent launchd environment
must not be treated as that proof.

The receipt lives at:

```text
/Library/Application Support/VitalServerHelper/update-bootstrap-verification/<update-id>.json
```

It is owned by the verifier/runtime boundary, not by immutable staging. Apply
must not replace this path. `canonicalPayloadSHA256` rejects a later bundle
that reuses the same `updateId` with a different payload. It does not prove a
fresh verify for the current apply; a prior root verify of the same digest
still satisfies proof. `uid`/`euid` come from the process identity adapter.
Proof compares them to explicit expected values; validation does not hardcode
root.

apply-smoke's installed CLI verify exists so prove has its mandatory receipt.
That is root installed-CLI evidence, not Platform Agent evidence.

## Follow-up

A real MacPlatformAgent verify field run remains unproven. Distinguishing
MacPlatformAgent from operator-run root CLI now has an explicit dual-owner
correlation contract (TS-229). Do not treat CLI apply-smoke as that run. Do
not mark the field run proven until an installed MacPlatformAgent verify exists.

Inspect the receipt directly:

```sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))' \
  "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/<update-id>.json"
```

Missing, unreadable, permission-denied, and decode-failed receipts stay
distinct from a successful verify. Do not reconstruct the home from source
defaults or from the current Platform Agent environment.

## Related Cases

- [TS-196: Helper UI uses the legacy update bundle engine](196_helper_ui_uses_legacy_update_bundle_engine.md)
- [TS-219: Swift bootstrap verifier rejects specification payload](219_swift-bootstrap-verifier-rejects-declared-payload.md)
- [TS-227: prove-update-bootstrap rejects persisted layer evidence](227_prove_update_bootstrap_rejects_persisted_layer_evidence.md)
- [TS-228: prove-update-bootstrap rejects verify-update-bootstrap receipt](228_prove_update_bootstrap_rejects_verification_receipt.md)
