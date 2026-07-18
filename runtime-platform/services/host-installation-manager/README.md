# Host Installation Manager

The Host Installation Manager owns product installation state on one Host. It
is a one-shot installation boundary, not a long-running product service and
not a replacement for the Host Agent.

It consumes the release-owned C48 `HostProductInstallationManifest`, observes
the C49 `HostInstallationFootprint`, and writes C50 transaction journals and
receipts. Package scripts only invoke this executable with explicit paths.
They do not decide whether an existing receipt, service, data directory, or
activation link is safe to overwrite.

Current commands:

- `preflight` admits a clean install, a same-release reinstall, or a
  same-release repair. It observes the release catalog and the declared
  launchd plist bytes as well as receipt, slot, link, data, and journal; it
  blocks direct version-changing package installation, stale footprint,
  unreadable state, and an unfinished transaction.
- `quiesce` accepts only the exact preflight-verified transaction, stops the
  C48-declared launchd services, and durably advances the journal to
  `activation-pending`. A launchctl failure is a failed transaction, not an
  implicit retry or an absent service.
- `activate` atomically points the explicit `current` release link at the
  already verified immutable slot and completes a previously quiesced
  transaction.

The staged Host Updater remains the only boundary for a version-changing
release. This manager must not parse C26 or convert a direct PKG overwrite
into an update.

The current implementation deliberately has no automatic stale-state cleanup
or uninstall command. An explicit future cleanup workflow must name its data
preservation/purge policy and must not be hidden in a package script.
