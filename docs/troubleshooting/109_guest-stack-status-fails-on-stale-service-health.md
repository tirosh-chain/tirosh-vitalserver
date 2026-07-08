# Guest stack status fails on stale service health document

## Symptom

After restarting the Helper VM, host runtime health stays `recovering` or
`failed` even though the VM process, host proxy, guest HTTP, Redis UI, and
Swagger UI are reachable.

Guest Control `/v1/stack/status` returns HTTP 503 with:

```text
postgresOperationDocumentInvalid: postgres service operation document field is invalid: health
```

## Cause

The VM is running, but Guest Control cannot assemble stack status because a
previously persisted `guest_service_resources` or `service_status_snapshots`
document does not contain an explicit service `health` value.

This is a datastore contract problem, not a VM boot failure. Service health
must remain explicit; missing health must not be silently treated as healthy.

## Fix Direction

Run a Guest Control repository schema migration that upgrades old documents
with missing or empty `health` to the explicit value `not_reported`.
Subsequent live service observation overwrites that migrated value with the
current Docker-reported health.

## Prevention

When service status contracts change, add explicit Postgres document migrations
near the schema migration that owns the affected read model. Restart health
checks must not be able to fail forever on pre-existing documents that can be
migrated without inventing healthy state.
