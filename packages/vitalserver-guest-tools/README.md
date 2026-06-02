# VitalServer Guest Tools

Guest tools is the Python package installed inside the VitalServer Linux guest.
It owns guest-side operational commands for runtime state, update activation,
shutdown preparation, Redis backup/repair, container logs, and guest
observability.

## Architecture

This package follows a pragmatic DDD and Clean Architecture layout:

```text
tirosh_guest_tools/
  domain/
  application/
  adapters/
    inbound/
    outbound/
  infrastructure/
  contracts.py
```

The package runs only inside the Linux guest. Because Linux system services,
Docker, `/proc`, and the shared runtime mounts are part of this runtime
environment, this package does not introduce generic ports solely to abstract
them. The boundary rule is instead:

- domain owns meanings, value objects, and document contracts.
- application owns guest use case orchestration.
- inbound adapters own external entrypoints such as CLI, daemon loops, and
  request-file polling.
- outbound adapters own Linux probing, Docker/systemd command execution, and
  file writers.
- infrastructure owns settings, logging, installation helpers, and shared
  Linux utilities.
- contracts owns Host/Guest file, command, service, and config field names.

## State Ownership

Guest-owned state must be produced explicitly by the guest. Host code may
collect, export, and display guest output, but it must not infer guest state
from logs, filenames, missing files, command output, or probe absence.

Missing, invalid, failed, stale, and empty values have different meanings and
must remain distinct in code and JSON documents.

## Domain Documents

Document shapes that cross process or Host/Guest boundaries belong in
`domain/`, not in collectors or writers.

Examples:

- `domain.observability.GuestObservabilitySnapshot`
- `domain.runtime_config.RuntimeConfig`
- `domain.runtime_state.GuestRuntimeState`
- `domain.operations.GuestOperationResult`

Outbound adapters may collect Linux values and create these domain objects.
Writers should persist `as_json()` output rather than assembling contract
dictionaries directly.

## Inbound Adapters

Inbound adapters translate external triggers into package behavior.

- `adapters/inbound/cli.py`: console script entrypoints.
- `adapters/inbound/request_file_poller.py`: watches Host-written request
  files and dispatches the matching systemd service.
- `adapters/inbound/observability_daemon.py`: daemon loop started by systemd
  for periodic guest observability snapshots.

CLI command names remain stable for compatibility even when internal adapter
names become more explicit.

## Outbound Adapters

Outbound adapters talk to Linux and persist guest-owned state.

- `adapters/outbound/observability/`: probes systemd, Docker, network, storage,
  runtime files, and writes observability snapshots.
- `adapters/outbound/runtime/`: reads runtime config, probes runtime state, and
  writes runtime state JSON.

Collectors must record probe failures explicitly. A collector failure should be
represented in the produced document, not silently converted into success or an
empty value.

## Infrastructure

Infrastructure modules provide runtime support shared by adapters and
application code:

- settings loading
- logging configuration
- guest tools installation
- shared Linux command helpers
- shared mount/path helpers

These modules may know about the guest environment. They should not define
domain document shapes.

## Settings

Default guest-tools settings live in
`tirosh_guest_tools/resources/guest-tools.toml`. That packaged TOML is the
single source for default values.

`/etc/tirosh/guest-tools.toml` is optional and acts as an explicit override.
The loader merges it over the packaged defaults, so deployment-specific changes
can stay small without duplicating the full settings document.
