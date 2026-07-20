# Linux DEB removal loses its completion verifier after package payload deletion

> ID: TS-158
> Category: Packaging / Uninstall
> Owner: Host Installation Manager and dpkg lifecycle transport
> Status: resolved

## Symptoms

`dpkg --remove` can run `prerm` successfully but fail in `postrm`, or report a
successful removal without a C54 terminal receipt. Older package layouts tried
to invoke the Manager from package payload that dpkg had already deleted, or
from an implicit helper in `/var/lib/dpkg/info`.

## Impact

The package database and Host-owned removal journal can disagree. Operators
cannot tell whether declared services, release data, and mutable-data
disposition were completed before dpkg changed its receipt. Retrying with
`dpkg --purge` would risk treating a missing verifier as authorization to
delete persistent product data.

## Cause

`postrm` executes after the DEB data payload is removed. A package payload
binary is therefore not a durable completion transport. dpkg's control area is
owned by the package manager and is not a product contract either. The former
composition did not bind an explicit verifier path that survives the payload
removal boundary.

## Checks

On a test or affected Linux host, inspect the package status and the C54
journal/receipt. Do not delete any data directory while investigating.

```sh
dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' vitalserver-runtime-platform
sudo find /var/lib/vitalserver-runtime-platform -maxdepth 4 -type f -print
```

`deinstall ok config-files` is the normal end state for `dpkg --remove`; it is
not evidence that C48-declared mutable data was purged. A C54 journal with an
absent or unreadable completion transport is a typed removal failure, not a
completed uninstall.

## Actions

Install a package that includes the C54 completion-transport contract. Its
`prerm` copies the exact declared Host Installation Manager executable and C48
manifest to the C48-declared, manager-owned purge-only store before returning
to dpkg. Its `postrm` invokes only those persisted paths. If an older package
is already in the failed state, preserve its C54 journal and mutable data,
collect the dpkg status, and use a reviewed operator recovery procedure; do
not run recursive `dpkg`, `apt purge`, or broad filesystem deletion from a
hook.

## Prevention

C54 now declares `PackageManagerCompletionTransport` in both request and
journal. The domain admits it only below a C48 manager-owned purge-only store,
with fixed Manager and manifest basenames. The Linux adapter creates those
files before the package-manager hand-off, and completion accepts the transient
`removed` receipt only when that same transport is present. The deterministic
DEB acceptance performs real `dpkg --install → --remove` and asserts package
payload removal, persisted C54 terminal receipt, and final
`deinstall ok config-files` status.

## Operational Notes

Normal removal preserves C48-declared mutable data by design. A future purge
workflow must separately prove the requested data disposition and clean-host
reinstall result; it must not infer either from dpkg configuration-file state.

## Related Cases

- TS-037
- TS-042
- TS-112
- TS-139

## Follow-up

- 2026-07-20: C54 completion transport and real Debian lifecycle acceptance
  added for the Runtime Platform DEB composer.
