# Update Shutdown Compose Services Stdout Missing

## Case Metadata

| Field | Value |
|---|---|
| ID | TS-080 |
| Category | Update / Guest containers |
| Owner | Guest tools update shutdown |
| Status | implemented |

## Symptoms

Product update starts and verifies the update bundle, but fails during runtime shutdown before guest activation. Runtime progress shows `apply-bundle` failed at `stop-runtime-services`.

The guest update shutdown log can include:

```text
Guest update shutdown failed at: 'NoneType' object has no attribute 'splitlines'
```

The installed runtime may then rollback and return to healthy, making the failure visible only in `runtime-events.jsonl` and `prepare-update-shutdown.log`.

## Cause

Guest update shutdown stops Compose services in an explicit order. Before stopping services it reads the available service names with:

```text
docker compose config --services
```

The compose wrapper used the generic command runner without stdout capture. As a result, the completed process could have `stdout == None`, but `compose_services()` treated stdout as a string and called `splitlines()`.

This is a guest-tools command output contract bug. Missing command output must not become an internal Python exception or an empty service set.

## Actions

- Read-only Compose commands must request stdout capture explicitly.
- `compose_services()` must report missing stdout and empty stdout as different dependency failures.
- Compose service state inspection must also capture stdout so timeout diagnostics can parse `docker compose ps`.

After the fix, this failure should surface with a guest dependency error code such as `guest-compose-services-output-missing` or `guest-compose-services-output-empty`, not an `AttributeError`.

## Prevention

- Command wrappers must declare whether stdout is part of their contract.
- Missing stdout, empty stdout, non-zero exit, and parse failure are separate meanings and should remain separate in guest-tools code.
- Update shutdown tests must cover command output capture for Compose read operations.

## Related Cases

- [TS-076 Update shutdown compose stop timeout and guest time drift](076_update-shutdown-compose-stop-timeout-and-guest-time-drift.md)
- [TS-035 Update가 Guest capability 계약 없이 request/result worker를 가정함](035_update-guest-capability-contract-missing.md)
