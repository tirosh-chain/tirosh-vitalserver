# macOS `launchctl` missing-service response blocks a clean Runtime Platform install

> ID: TS-156
> Category: Packaging
> Owner: Host Installation Manager macOS adapter
> Status: active

## Symptoms

The macOS Installer shows **“The installation failed”** while installing
`VitalServerRuntimePlatform-*.pkg`. `/var/log/install.log` identifies
`./preinstall` as the failing script and contains a structured C50 receipt
similar to:

```json
{
  "state": "blocked",
  "issue": {
    "code": "macos-service-observation-failed",
    "message": "launchctl exited with status 113",
    "dependency": "launchctl"
  }
}
```

On macOS 26, a read-only query for a declared but not-yet-installed service
returns:

```sh
launchctl print system/com.tirosh.vitalserver.host-agent
# exit 113
# Could not find service "com.tirosh.vitalserver.host-agent" in domain for system
```

The expected clean-install state is that the Runtime Platform package receipt,
release slot, `current` link, launchd plists, registrations, and mutable data
are all absent.

## Impact

The package stops before its payload is copied. Runtime Platform does not
become installed and the existing VitalServer Helper installation is not
changed. Older affected packages may create a manager diagnostic receipt below
`/Library/Application Support/VitalServerRuntimePlatform/data`; that residue is
not proof of a partial product installation.

## Cause

The C49 macOS adapter originally treated only `launchctl print` exit status
`3` as a declared service absence. macOS 26 uses status `113` plus an explicit
service-specific stderr response. The adapter therefore turned a clean Host
fact into an observation failure and C50 correctly blocked the install rather
than guessing.

The affected pkg may also predate the C50 package-script correction and run
`quiesce` during preinstall. It is a historical build candidate, not a current
installation artifact.

## Checks

```sh
tail -n 200 /var/log/install.log | grep -A8 -B8 'VitalServerRuntimePlatform'

pkgutil --pkgs | grep 'com.tirosh.vitalserver.runtime-platform'

launchctl print system/com.tirosh.vitalserver.host-agent
```

Use the final command only as a read-only observation. An absent Runtime
Platform service on a clean Host is expected.

## Actions

1. Do not retry a historical pkg from `runtime-platform/.tmp/`.
2. Build a new C47 package after the Host Installation Manager fix.
3. Verify its expanded scripts: preinstall must invoke only C50 `preflight`;
   quiesce/activate/finalize belong to postinstall.
4. Install the new artifact on a clean test Host and retain its C47 receipt and
   Installer log as C24 evidence.
5. If an older failed package left only the manager diagnostic receipt, install
   the fixed newly built package. C49 accepts this one historical state only
   after decoding its C50 identity and proving that the receipt is the sole
   manager-owned transaction residue; it does not delete a directory as an
   install workaround. Any extra file, symbolic link, malformed receipt, or
   Host/VM data remains explicitly blocked for review.

## Prevention

The macOS adapter now recognizes status `113` only when stderr names the exact
declared missing service. The same narrow protocol is used by C49 observation
and by C50 quiesce/reconciliation, so a clean Host cannot advance past
preflight only to fail while booting out an already-absent service. A status
`113` for another service or any other launchctl failure remains blocked. Unit
fixtures cover both cases, and a Darwin-only read-only test invokes
`launchctl print` for a generated missing service name on the build Host.

Blocked C50 preflight now emits its receipt to Installer stdout without
persisting a journal, receipt, or product data directory. The first durable
transaction state remains an admitted `preflight-verified` journal.

For the historical package behavior, the fixed manager has one narrow
transition: a valid `blocked` receipt for the declared installation with no
journal and no other content below the declared manager-owned transaction root
is observed as `legacy-blocked-preflight` and replaced by an admitted
preflight's normal transaction state. It is not a generic residue cleanup or a
fallback for unreadable state.

## Related Cases

- TS-155 — payload failure after service quiescence
- TS-136 — uninstall leaves a product service loaded

## Follow-up

- 2026-07-19: reproduced on macOS 26.5.2; Installer failed in preinstall with
  `launchctl exited with status 113` before payload delivery.
