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

- `observe-footprint` is the read-only C49 command. It reads C48 and derives
  the one `installation-manager-journal` C50 store and fixed journal/receipt
  filenames from that declaration; callers cannot redirect the observation to
  arbitrary state paths. It never writes a journal or receipt, reconciles a
  service, or activates a release.
- `preflight` admits a clean install, a same-release reinstall, or a
  same-release repair. It observes the release catalog and the declared
  launchd plist bytes as well as receipt, slot, link, data, and journal; it
  blocks direct version-changing package installation, stale footprint,
  unreadable state, and a transaction that may already have changed services.
  A blocked preflight returns its typed receipt to the Installer log but does
  not create a C50 receipt, journal, or product data directory: an operation
  that was never admitted must not become a future installation footprint.
  As a one-time historical migration, it also admits an exact decoded
  `blocked` receipt left by the pre-fix package only when C49 proves that it is
  the sole file below the manager-owned transaction store and no package,
  release, launchd, Host Agent, or VM state exists. The admitted preflight
  replaces that receipt with its normal durable transaction state. Any extra
  receipt residue remains a stale-footprint cleanup boundary.
  A leftover `preflight-verified` journal is explicitly retryable because
  preflight itself has no service effect, but only when its own
  manager-owned C48 journal directories are the sole remaining mutable
  footprint. Host Agent or VM data remains an explicit cleanup boundary.
  Before admitting a same-release reinstall or repair, it reads C80 Host
  Update Operation Ownership through the C52 Host-local administration
  descriptor. Only an exact, current-installation `available/idle` result is
  admitted. Missing, invalid, failed, unavailable, mismatched, or active
  ownership blocks before C50 persistence or service effects. A C49-proven
  clean Host does not require C80 because no installed Host Agent exists to
  own that contract.
- `quiesce` accepts only the exact preflight-verified transaction, first
	persists `services-quiescing`, stops the C48-declared native services, and
	then advances the journal to `activation-pending`. Each platform adapter
	defines its explicit missing-service protocol; a generic command failure is
	never converted into an implicit retry.
- `activate` applies only the C48-declared activation mechanism to the already
	verified immutable slot and records `activated`: macOS/Linux use a symbolic
	link and Windows uses a directory junction.
- `finalize` reconciles only the C48-declared native service registrations
	after activation, then records `completed`. Package scripts do not run a
	service manager directly.
- `recover` is the explicit compensating workflow. It marks a preflight-only
  journal `recovered`, or—after proving the immutable slot—re-activates and
  reconciles the exact declared release before recording `recovered`. It never
  guesses an old release or deletes mutable state.
- `remove` is the separate C54 product-removal lifecycle. It requires an
  explicit `--data-disposition`: `preserve-mutable-data` stops and removes only
  the declared package, service registrations, activation link, immutable
  release, and—on macOS—the C48-proved `/Applications/VitalServer Runtime
  Platform.app` bundle while retaining mutable stores and a durable removal
  receipt;
  `purge-all-product-data` additionally removes the declared top-level mutable
  stores, returns its typed receipt on stdout, and intentionally leaves no
  in-product journal or receipt. It blocks unreadable resources, diverged
  immutable content, service definitions, or the macOS operator application,
  another release in the catalog or activation link, and an unfinished
  installation transaction. It is never an implicit PKG script fallback.
  `completed` means this manager owns and has removed the package receipt (the
  macOS `pkgutil --forget` protocol) and C49 proved the application bundle is
  absent. Linux
  and Windows package databases are instead owned by dpkg/MSI. Linux reaches
  `awaiting-package-manager` after the declared immutable payload is gone;
  Windows reaches it in an MSI pre-`RemoveFiles` action after C49 proves only
  the exact declared immutable release remains. In both cases the manager
  prepares C54's durable completion transport, returns control to the package
  manager, and never recursively removes its receipt or claims a clean Host.
  Every removal admission requires the same exact C80 `available/idle`
  observation before C54 persistence or destructive effects.
- `staged-update` is the C68 version-changing release transaction. It reads
  and proves the active `current` C48 before it accepts the archive, persists
  its operation and candidate below that active C48's Installation Manager
  store, then quiesces, publishes, activates, and reconciles in order. A
  `succeeded` C68 result is written only after it records the target C48's
  completed C50 journal/receipt in the target's declared transaction store.
  This keeps the next C49 observation coherent with the `current` slot; a
  stale C50 record for the previous release is never silently accepted. Only
  then may the C67 executor project a successful C55 effect.
	The archive layout derives service-definition names from C48.platform
	(`.plist` for launchd, `.service` for systemd, `.json` for SCM); it does not
	select a format from the Host executing the manager. macOS/Linux use the
	symbolic-link compare-and-swap effect, while Windows proves and replaces the
	C48 directory junction under service quiescence with an explicit restore
	path if the replacement cannot complete.
- `staged-update-recover` is an operator-requested C68 repair, not a retry or
  rollback. It accepts only a prior `failed` or `unavailable` C68 operation
  whose last durable state was service-quiescing, release-publishing, or
  activating. It re-reads the proven `current` C48 and reconciles *that*
  release's declared services. It neither replays archive publication, guesses
  whether an interrupted activation completed, nor switches `current`. Its
  separate receipt keeps the original failed update visible. A successful
  recovery also writes a `recovered` C50 journal/receipt for the explicitly
  observed current C48 release before its own receipt is terminal.

Each C48 `activation.referenceKind` explicitly selects the Host filesystem
mechanism: `symbolic-link` on macOS/Linux and `directory-junction` on Windows.
The manager must reject a mechanism that does not match its declared platform;
it must never select one from the current Host or replace a junction with a
symbolic link. The shared C49 filesystem observer takes its package receipt,
service registration, and activation observations from named native adapters
instead of treating macOS behavior as the cross-platform default. Linux has
explicit dpkg/systemd observation, systemd lifecycle effects, and deterministic
DEB composition. Windows has explicit MSI registry observation, SCM/junction
lifecycle effects, and a WiX v4 source composer. Compiling that source and
exercising it on a clean Windows Host remain separate delivery evidence; no
macOS executable claims either proof.

The macOS package runs preflight before Installer writes payload bytes, but all
service effects happen in postinstall after the immutable C48 slot exists.
The postinstall trap invokes `recover` on a failed quiesce/activate/finalize
sequence. If payload delivery itself fails, no service effect has run and a
later preflight can safely supersede its leftover preflight-only journal.

The C49 observer and C50 writer reject symbolic links in every existing path
component, not only at the final file. The manager therefore never follows a
symbolic data-directory ancestor while reading or writing transaction state.

For a declared system launchd service, C49 observation and C50 service
quiescence/reconciliation recognize only documented no-service responses: the
legacy launchctl status `3`, or macOS 26 status `113` accompanied by the exact
declared-service `Could not find service` response. Other command results
remain typed observation/effect failures rather than being softened into an
absent state.

The staged Host Updater remains the only boundary for a version-changing
release. This manager must not parse C26 or convert a direct PKG overwrite
into an update.

The C80 read is an explicit fail-closed admission guard, not yet an atomic
cross-process lifecycle claim. An update can still race with installation or
removal after the idle read. The follow-up coordination contract must make
claim acquisition and update admission mutually exclusive in the Host-owned
SQLite transaction; callers must not treat this guard as proof that the
time-of-check/time-of-use race is solved.

There is no automatic stale-state cleanup. C54 is an explicit operator command
and must not be hidden in a package script. It accepts only the C48-declared
paths and uses the C49 observation before and after effects; manual residual
content, a changed release catalog, or a failed destructive transaction stays
visible for inspection rather than being silently erased.
