# Guest stack status fails on an invalid SQLite service-status document

## Symptom

After restarting the Helper VM, host runtime health stays `recovering` or
`failed` even though the VM process, host proxy, guest HTTP, Redis UI, and
Swagger UI are reachable.

Guest Control `/runtime/stack` returns HTTP 503 with:

```text
controlDocumentInvalid: control document field is invalid: health
```

## Cause

The VM is running, but Guest Control cannot assemble stack status because a
previously persisted `guest_service_resources` or `service_status_snapshots`
document does not contain an explicit service `health` value.

This is a datastore contract problem, not a VM boot failure. Service health
must remain explicit; missing health must not be silently treated as healthy.

## Fix Direction

Do not replace missing health with a default such as `not_reported`: that would
invent state. Preserve the failure, retain the damaged database as diagnostic
evidence, and repair or replace the affected snapshot only from an explicit
Docker/Compose observation. If no authoritative observation is available, the
resource must remain failed rather than becoming a successful empty status.

## Prevention

When service status contracts change, add an explicit SQLite control-ledger
migration or repair procedure near the schema revision that owns the document.
It may only write values supplied by authoritative inputs. Restart health checks
must preserve invalid persisted state as a typed failure; they must not hide it
with a default health value.
