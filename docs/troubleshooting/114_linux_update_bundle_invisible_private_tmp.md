# Linux update bundle is invisible to the Platform Agent

> ID: TS-114  
> Category: Packaging / Update  
> Owner: Linux update trust inbox  
> Status: resolved

## Symptoms

`POST /platform/update-bundles/apply` returns HTTP 400 with
`update bundle localPath read failed` and `no such file or directory`, even
though an interactive shell can list the archive under `/tmp`.

## Impact

The trusted update cannot start. Retrying the same `/tmp` path does not change
the result, and weakening the service sandbox would expand Host access merely
to accommodate an ambient path.

## Cause

The Platform Agent systemd service uses `PrivateTmp=true`. Its `/tmp` namespace
is intentionally different from the administrator's interactive `/tmp`, so
the local-path owner supplied to the API is genuinely missing from the Agent's
view.

## Checks

Compare the requested path with the service's `PrivateTmp` setting and inspect
the root-owned `/var/lib/vitalserver/inbox` directory. Do not infer visibility
from an interactive shell's successful `ls`.

## Actions

Run `tools/trust-update-linux.py` with the publisher-supplied expected SHA-256.
The tool copies and hashes the same byte stream into the root-only inbox and
prints the exact staged path to pass as the update bundle `localPath`.

## Prevention

The Linux installer creates `/var/lib/vitalserver/inbox` as `root:root 0700`.
Trust provisioning stages `trusted-<sha256>.bundle` atomically as mode `0600`,
and the Agent hashes that exact file again before scheduling apply. The service
keeps `PrivateTmp=true`.

## Operational Notes

On 2026-07-11 the staged 0.2.4 archive completed Platform workflow
`workflow-fe51f1b471921783fabf8878d9b41e90` and installed acceptance run
`4d493a04-5c30-4a9b-ac62-55e92a4ed963` without weakening the sandbox.

## Related Cases

- TS-012
- TS-112

## Follow-up

- 2026-07-11: Reproduced and resolved on the Ubuntu 24.04 x86_64 QEMU runner.
