# Direct Helper PKG repair, upgrade, or downgrade is blocked before effects

> ID: TS-139
> Category: Packaging / Host state persistence
> Owner: macOS package install lifecycle
> Status: contained by the 0.2.1 fresh-only contract

## Symptoms

Installing a VitalServer Helper 0.2.1 PKG while the product receipt already exists now fails in
preinstall with an explicit intent:

```text
package install preflight blocked blockers=
package-install-intent-unsupported:intent=same-version-repair
identifier=ai.tirosh.vitalserver.helper
installedVersion=0.2.1 targetVersion=0.2.1
```

An older receipt produces `intent=upgrade`; a newer receipt produces `intent=downgrade`. These
states are not retried as fresh install. A receipt catalog or info read failure remains
`package-receipt-read-failed` and does not become absence.

Before this containment, direct PKG reinstall could stop installed services and import or mutate
Host state before PackageKit replaced the payload. Payload or postinstall failure could then leave
services stopped, reset settings, resize a disk, expose an external proxy listener, or delete
runtime state during cleanup.

## Cause

The former package flow collapsed every receipt-present state into a generic `reinstall` mode.
It did not distinguish same-version repair, upgrade, and downgrade, and it had no transactional
candidate payload activation or rollback boundary. Preinstall therefore performed SQLite
initialization/migration, proxy inspection, and service stop before payload success was known.

Receipt absence was also derived from human-readable `pkgutil --pkg-info` error text. That made a
command, permission, decode, or receipt database failure capable of looking like a clean target.
The schema v1 install contract carried no target version, so postinstall could not prove that the
contract belonged to the payload that was actually installed.

The repository install helper had another ordering violation: when `--install-settings` was
provided, it wrote `/private/tmp/tirosh-vitalserver-install.json` before Installer preinstall.
A receipt-present install could therefore mutate Host input even though the package would later
be blocked.

## Fix

VitalServer Helper 0.2.1 direct PKG installation is fresh-only.

Receipt observation now uses two structured owner reads:

1. successful `pkgutil --pkgs` output supplies exact package-id membership;
2. only for an exact member, `pkgutil --pkg-info-plist` supplies strict `pkgid` and
   `pkg-version`.

Catalog failure, plist command failure, invalid UTF-8, plist decode failure, missing or duplicate
required keys, identifier mismatch, and an empty or non-numeric dotted version are explicit read
failures. Human stderr such as `No receipt ...` is diagnostic text only and never creates absence.

A pure numeric version policy classifies:

- no receipt as `fresh`;
- equal installed and target versions as `same-version-repair`;
- lower installed version as `upgrade`;
- higher installed version as `downgrade`.

Only `fresh` is admitted. Every receipt-present intent blocks before SQLite
initialization/migration, proxy mutation, service stop, or install contract write. The generic
reinstall effect branch was removed from preinstall.

An admitted fresh preinstall writes schema v2 `package-install-contract.json` with:

- exact `packageIdentifier`;
- `targetVersion`;
- explicit `intent=fresh`.

Postinstall validates all four contract fields before provisioning. A missing/unreadable contract,
schema mismatch, package-id mismatch, target mismatch, or non-fresh intent is a hard failure.
`pkgbuild --version`, generated `Constants.launcherVersion`, and the install workflow target all
come from release manifest `helperVersion`.

`vitalserver-devtools macos-package-install` performs the same versioned receipt preflight before
writing optional install settings or invoking `sudo installer`.

## Checks

Inspect the owner state without interpreting command failure as absence:

```sh
sudo pkgutil --pkgs | grep -Fx 'ai.tirosh.vitalserver.helper'
sudo pkgutil --pkg-info-plist ai.tirosh.vitalserver.helper | plutil -p -
```

If the exact receipt is present, direct 0.2.1 PKG repair/upgrade/downgrade must fail before service
or Host-state effects. Verify that:

```sh
ls -l '/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite'
launchctl print system/ai.tirosh.vitalserver.helper.vm
```

The contract path used by PackageKit is in its Scripts sandbox and is normally visible through
the install log. Tests should use an injected contract path and assert that it remains absent on
every blocked intent.

The built package metadata must agree with the launcher target:

```sh
tmp_dir="$(mktemp -d)"
pkgutil --expand dist/VitalServerHelper-0.2.1-dev.pkg "${tmp_dir}/expanded"
sed -n '1p' "${tmp_dir}/expanded/PackageInfo"
```

`identifier` must be `ai.tirosh.vitalserver.helper` and `version` must equal the release manifest
`helperVersion` and generated launcher version.

For a supported fresh retry, use the explicit uninstall/reset workflow and prove that the receipt,
product-owned paths, and managed services are absent. Do not delete only the receipt or only the
files to manufacture a fresh state.

## Operator action and data continuity warning

`standard uninstall -> fresh install` is a containment recovery sequence, **not** a
data-preserving repair or upgrade. Standard uninstall stops and removes the live runtime,
including the VM and Host SQLite state. It first creates the supported Redis backup and moves
selected product-owned retained material to a run-specific directory under:

```text
/Library/Application Support/VitalServerHelper-retained-uninstall-data/
```

Configured external Vital Files may remain in place, but a later fresh install does not
automatically discover, import, or restore the removed VM, Host settings, Redis/Postgres data, or
the retained run. Before uninstalling, record the generated backup and retained paths and export
every datastore required by the deployment. After fresh install, use the explicit supported
restore workflow and reapply Host settings; verify the restored databases before resuming service.

If live VM, SQLite, or database continuity is required, do not present uninstall/fresh-install as
the repair path. Keep the installed runtime stopped and intact until a staged transactional
updater or a separately validated backup/restore maintenance plan is available.

## Prevention

- Receipt absence must come from successful exact catalog membership, never error text.
- A receipt must include a strictly decoded identifier and version.
- Same-version repair, upgrade, and downgrade are different intents and must not share a generic
  reinstall effect path.
- A blocked intent must stop before every mutation, including optional install-settings write.
- Preinstall and postinstall must share a version-bearing contract tied to package metadata.
- Direct version-changing install remains blocked until candidate activation, durable intent,
  compensation, and rollback are implemented and proven.
- Failed cleanup must not delete persistent runtime state or convert a failed receipt into fresh.

## Related Cases

- [TS-134 PKG fresh install Host settings materialization](134_pkg-fresh-install-host-settings-before-materialization.md)
- [TS-155 Host installation transaction strands services after payload failure](155_host_installation_transaction_strands_services_after_payload_failure.md)
- [TS-164 Historical warm reinstall Guest Docker stop timeout](164_pkg-reinstall-guest-docker-stop-timeout.md)
- [Host runtime state persistence](../runtime/macos/host-runtime-state-persistence.md)
