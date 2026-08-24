# Guest Update Artifact Owner Closes an Idempotent Upload

> ID: TS-222
> Category: Update / Guest Control / Artifact ownership
> Owner: Guest Tools
> Status: active

## Symptoms

A signed update reaches the current Guest endpoint, but importing an artifact
already present in the Guest content-addressed store fails on the Host:

```text
NSURLErrorDomain Code=-1005 "The network connection was lost."
```

If Guest Runtime is rolled back before Container, the same failure can recur
while importing the Container rollback artifact.

## Cause

`ImmutableUpdateArtifactStore.import_stream` verified and returned an existing
destination without consuming the incoming HTTP body. The Guest server closed
the request while the Host upload task was still sending bytes.

The rollback workflow also used simple reverse apply order. That replaced the
Guest owner code before the Container rollback finished.

## Fix Direction

- Consume exactly the declared Content-Length and verify the incoming SHA-256
  even when the destination digest already exists.
- Keep the existing immutable artifact and return its owner reference only
  after both stored and incoming content have been verified.
- When the existing destination is corrupt or unreadable, still consume the
  full declared body first, then return an explicit stored-artifact corruption
  failure (HTTP 500 `updateStoredArtifactCorrupt`) instead of closing the
  connection mid-upload. Never replace the corrupt file or report success.
- Preserve the incoming short-body/read-failure reason and the stored
  corruption reason separately when both are present, so the Host can act on
  each typed cause.
- Roll back Host Platform, then Container, then Guest Runtime so the current
  Guest owner remains available for Container compensation.

## Prevention

Content-addressed idempotency includes the transport body contract; existence
alone is not success evidence. Stored corruption is its own typed failure and
must never be masked by an incoming-body check or repaired implicitly.
Rollback order must model control-plane ownership, not only reverse data-layer
dependency order.

## Related Cases

- [TS-221: Signed update bundle owns a Host loopback Guest endpoint](221_signed-update-bundle-owns-host-loopback-guest-endpoint.md)
