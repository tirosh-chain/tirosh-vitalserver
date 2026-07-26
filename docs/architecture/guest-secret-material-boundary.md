# Guest archive credential-material boundary

> 상태: **C51 private owner와 C60 local administration projection 구현됨**

## Purpose

An external VitalServer indexed-library archive needs a credential, but that
credential must not become product configuration, Guest Runtime state, an
operation, an archive receipt, telemetry, or a normal HTTP response. This
boundary keeps that rule operational while still allowing a newly installed
Guest Runtime to start.

## Ownership and direction

```text
Operator Console / platformctl
          │ exact C51 request (write-only)
          ▼
Host Agent C52 OS-local administration listener
          │ named route only
          ▼
Guest Runtime C51 secret-material owner ──atomic 0600 file──> /run/vitalserver/secrets
          │ C60 availability/outcome without values
          ▼
Archive provider ──C46 endpoint + current C51──> external VitalServer library
```

- **C46** owns the non-secret credential reference and external endpoint.
- **C51 owner** owns the private value and file permissions. It accepts C51
  only through the named C52 local-administration route.
- **C60** owns the human-readable, non-secret result: reference plus
  `available`, `missing`, `invalid`, or `failed`; provisioning returns only
  `provisioned`, `rejected`, or `failed`.
- **Archive Export** owns the eventual upload/index result. C60 is not an
  archive operation or receipt.

The public Host edge route does not publish this route. Host Agent transport
authorization is C52's operating-system peer-user or named-pipe ACL policy,
not a browser-supplied role flag.

## Lifecycle

1. Guest Runtime validates C37/C46 and starts even when C51 is absent.
2. C60 reports `missing`; this is not readiness or archive success.
3. An authorized local operator supplies the exact C51 document once. The
   owner validates the C46 reference, writes a temporary private file, syncs,
   renames atomically, and verifies its safe shape.
4. C60 returns only a non-secret `provisioned` outcome. The console clears its
   transient input after dispatch.
5. Archive Export opens the current C51 only when it needs an external effect.
   Missing or invalid material produces a known failed export step and durable
   failed receipt. It never becomes anonymous authentication, empty success,
   or an unknown external effect.
6. The C51 file is Guest runtime material and is not packaged or persisted in
   the Guest SQLite database. A Guest restart therefore returns to explicit
   `missing` until the operator re-provisions it.

## Non-negotiable exclusions

- No C51 source examples, package payloads, backups, state tables, operation
  records, receipts, telemetry attributes, ordinary logs, or response bodies.
- No generic `path` or arbitrary request-body forwarding escape hatch in the
  Runtime Console or Host Agent.
- No endpoint guessing, bundled fallback, or credential default when C46/C51
  is unavailable.

## Verification

Focused Guest Runtime tests prove that missing C51 does not prevent boot, C60
does not disclose a user ID or password, provision uses restrictive private
permissions, reference mismatch leaves no file, and an archive action reports
a known failed step if the private material is unavailable. Contract examples
prove C60 carries only non-secret fields.
