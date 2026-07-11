# Linux Native Provider Compose project mismatch

> ID: TS-113  
> Category: Runtime health / Guest containers  
> Owner: Linux Native Runtime Provider  
> Status: resolved

## Symptoms

The installer starts Compose containers, but the Native Provider cannot find
the expected Product Stack or its readiness check remains in `starting`.

## Impact

Installed acceptance times out even though containers with similar names may
be visible. Inferring ownership from those names can target the wrong Compose
project.

## Cause

The installer and Provider invoked Compose from different paths without an
explicit shared project name. Compose therefore derived project identity from
ambient directory state.

## Checks

Compare the configured `composeProjectName` with `docker compose ls` and the
`com.docker.compose.project` label on the running containers.

## Actions

Set the Native Provider's required `composeProjectName` to the installer-owned
value and invoke every Compose command with `--project-name`.

## Prevention

Linux installation writes the explicit `vitalserver` project identity. Native
Provider configuration rejects a missing project name, and pure command tests
assert that every Compose invocation carries the same explicit argument.

## Operational Notes

Container name similarity is diagnostic context only; it must not become the
Runtime Provider's state or ownership contract.

## Related Cases

- TS-030
- TS-095

## Follow-up

- 2026-07-11: Fixed during Linux x86_64 installed acceptance and verified with
  eleven running services.
