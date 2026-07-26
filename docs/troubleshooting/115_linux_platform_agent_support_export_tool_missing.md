# Linux Platform Agent restarts because support export tool is missing

> ID: TS-115  
> Category: Packaging / Update  
> Owner: Linux offline release assembly  
> Status: resolved

## Symptoms

`vitalserver-platform-agent.service` repeatedly exits with status 1. Its journal
reports:

```text
platform delivery support export tool is unavailable
path=/opt/vitalserver/current/tools/support-export-linux.py: no such file or directory
```

Runtime Provider and Runtime Controller may still be active, but the Platform
API and PWA are unavailable.

## Impact

Platform lifecycle commands, update API calls, and support export cannot be
used. Retrying the Agent does not help because startup validation correctly
rejects a configured effect tool that is not present.

## Cause

An intermediate Linux installer migration published `supportExportTool` in the
Platform Agent configuration, but that release's install transaction did not
copy `support-export-linux.py` from the offline package into the immutable
release `tools` directory. Configuration and release contents therefore
described different capabilities.

## Checks

Compare all three explicit owners:

1. `delivery.supportExportTool` in `/etc/vitalserver/platform-agent.json`.
2. The resolved `/opt/vitalserver/current` immutable release.
3. The tool inventory and checksums in the offline bundle.

Do not remove the configuration field merely to make startup succeed; that
would hide an unavailable configured capability.

## Actions

Run a newer checksum-verified offline installer directly. This recovery path
does not depend on the unavailable Platform API. The installer must stage the
support tool into the new immutable release before switching `current` or
restarting the Agent, then complete installed acceptance.

## Prevention

The Linux bundle builder includes and checksums `support-export-linux.py`. The
installer copies it into `tools` before activation. Installed acceptance now
requires `canExportLogs=true`, schedules `POST /platform/support-exports`,
waits for the durable workflow, and re-hashes the managed artifact. A release
cannot pass installation when config advertises the tool but the executable is
missing.

## Operational Notes

On 2026-07-11 the Ubuntu 24.04 x86_64 QEMU runner reproduced the 0.2.5 startup
failure. Offline 0.2.6 installation recovered the Agent and passed acceptance
run `3e2073d4-62aa-470c-b212-612c929037de`. Support workflow
`workflow-32ea7b1220e28c26c868ee8688d8208a` produced a 41,318-byte root-only
artifact with SHA-256
`92d93c6b412ad16146a9de32df70c067414fcd5716edf3c334ca632bd906b1e8`.

## Related Cases

- TS-112
- TS-114

## Follow-up

- 2026-07-11: Reproduced, repaired, and verified on the Linux installed acceptance runner.
