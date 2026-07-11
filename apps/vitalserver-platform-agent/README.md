# VitalServer Platform Agent for Windows and Linux

This is the shared headless Platform Agent core for Windows/Hyper-V and
Linux/Native Runtime Providers. It intentionally does not replace the macOS
Swift reference implementation.

The binary exposes owner-neutral `/platform/*` resources, serves the shared PWA,
and keeps missing, invalid, unavailable, and failed owner reads distinct. A
configuration file is mandatory; missing configuration is startup failure, not
an implicit disabled state.

Current bring-up status:

- shared Platform contract and explicit durable resource readers exist;
- Linux and Windows binaries cross-compile from the same source;
- Linux reads structured systemd state through D-Bus and Windows reads the
  Service Control Manager API; no command-output parsing is used;
- the Windows binary implements the Windows Service control protocol and the
  Linux package includes a hardened systemd unit;
- dependencies are vendored with their license files for offline builds
  (`go-systemd` Apache-2.0, `godbus` BSD-2-Clause, `x/sys` BSD-3-Clause);
- Linux includes a Native Runtime Provider process supervised by systemd. It
  owns the explicit `starting` / `bootstrapping` / `running` / `stopping` /
  `stopped` / `failed` lifecycle, starts the common bundle with Compose, and
  publishes the Runtime endpoint only after the Runtime Controller readiness
  endpoint succeeds. Compose output is never interpreted as Runtime state;
- Linux provider shutdown runs `docker compose down --remove-orphans` without
  the volume deletion flag, so managed Runtime data remains outside the
  disposable process/container lifecycle;
- Windows includes a Hyper-V Runtime Provider Windows Service using the same
  lifecycle state machine. Its effect adapter invokes fixed `Get-VM`,
  `Start-VM`, and graceful `Stop-VM -Shutdown` scripts. The configured VM name
  is passed through process environment, PowerShell output is not parsed as
  state, and a forced power-off is deliberately not used;
- Provider start, stop, and restart commands use systemd D-Bus on Linux and
  SCM APIs on Windows. A completed command means the OS service effect
  completed; the response separately returns the Provider-owned lifecycle and
  never fabricates `running` from the service-manager result;
- canonical `/runtime/*` routes are forwarded through an explicit allowlist to
  the Runtime Controller endpoint owner; Platform credentials are removed
  before forwarding and endpoint-unavailable and transport-failed remain
  different responses;
- update, rollback, uninstall, and support export use one durable Platform
  workflow owner. Support export writes only to a platform-managed directory
  and publishes an explicit artifact path, SHA-256, and byte size; callers do
  not choose a Host path;
- Windows provisioning now validates the Hyper-V feature, VHDX checksum,
  internal switch/NAT identity, managed VM disk/switch identity, Linux Secure
  Boot template, and writes an explicit provision owner document. It refuses
  to replace mismatched existing VM or network resources;
- the Hyper-V image compiler accepts only a passed `linux/amd64` rootfs proof
  with a staged native-mount deploy payload, verifies an EFI System Partition,
  converts the system and persistent Runtime data disks to dynamic VHDX, and
  carries a NoCloud ISO that configures the fixed internal address and native
  mount layout. This avoids a Windows Host shared-folder dependency;
- production validation of the product Hyper-V VHDX, Windows artifact
  assembly, and installed acceptance remain open.

Generate the publisher-side digest catalog only after the final archives are
immutable:

```sh
python3 scripts/build_update_trust_catalog.py \
  --archive dist/VitalServer-Linux.tar.gz \
  --archive dist/VitalServer-Windows.zip \
  --output dist/trusted-bundle-digests.json
```

Deliver the archive identity through authenticated release metadata separate
from the archive itself. The installed Linux/Windows trust tools require that
publisher-provided digest and verify the exact local byte stream before
enabling update apply.

Run tests and cross-build both product targets:

```sh
make platform-agent/proof
```

Build the Linux offline artifact only from explicit Runtime Bundle and Docker
image archive inputs:

```sh
make platform-agent/package/linux \
  LINUX_PLATFORM_VERSION=2.0.0 \
  LINUX_RUNTIME_BUNDLE_VERSION=2.3.4 \
  LINUX_RUNTIME_BUNDLE_DIR=/absolute/path/to/portable-runtime-bundle \
  LINUX_RUNTIME_IMAGES_ARCHIVE=/absolute/path/to/runtime-images.tar
```

The builder rejects non-linux/amd64 binaries, missing PWA or Compose inputs,
symlinks in staged trees, and image archives without a Docker or OCI manifest.
The archive contains a checksum-verified installer. Releases live under
`/opt/vitalserver/releases/<version>` while mutable Runtime data remains under
`/var/lib/vitalserver`; activation changes the `current` symlink and restores
the previous release if installed API acceptance fails. Building the archive
is proof of artifact composition, not proof that installation succeeded on a
Linux host.

Windows packaging is an explicit two-stage process. First build a non-
distributable `acceptanceCandidate` from the compiled Hyper-V image:

```sh
make platform-agent/package/windows-acceptance-candidate \
  WINDOWS_PLATFORM_VERSION=2.0.0 \
  WINDOWS_RUNTIME_BUNDLE_VERSION=2.3.4 \
  WINDOWS_HYPERV_IMAGE_DIR=/absolute/path/to/hyperv-image
```

Install that candidate on the Windows Hyper-V acceptance runner and copy back
the generated `windows-hyperv-acceptance.json`. Then seal the distributable
candidate:

```sh
make platform-agent/package/windows \
  WINDOWS_PLATFORM_VERSION=2.0.0 \
  WINDOWS_RUNTIME_BUNDLE_VERSION=2.3.4 \
  WINDOWS_HYPERV_IMAGE_DIR=/absolute/path/to/hyperv-image \
  WINDOWS_HYPERV_ACCEPTANCE_MANIFEST=/absolute/path/to/windows-hyperv-acceptance.json
```

The resulting deterministic ZIP is a release candidate, not an MSI and not a
claim that another Windows host passed. MSI/WiX (or an equivalent enterprise
installer), signing, clean-host install, update, rollback, and data-preservation
acceptance remain delivery gates.

The acceptance candidate carries `state=acceptanceCandidate`, an explicit
pending proof document, and no acceptance run ID. Windows update rejects that
state. The sealed ZIP carries `state=releaseCandidate` and is accepted only
when the returned proof binds the exact Agent, Provider, PWA, Hyper-V image,
and packaging/config tree hashes. This avoids both circular proof requirements
and accepting unproved installer-script changes.
The publisher trust-catalog builder independently rejects an unsealed Windows
candidate, so it cannot be allowlisted as an update archive.

After a sealed ZIP passes its second clean-host install, the bundled
`acceptance-uninstall-reinstall-hyperv.ps1` proves standard removal and
reinstallation of those same sealed bytes. It preserves and compares the
explicit ProgramData config/token owners, uses a Runtime Controller settings
marker to prove guest data, requires the same data VHDX identity and
`preserved-existing` provisioning result, and requires a new host-local install
acceptance run. It never mounts or interprets the guest data disk from Host
code. This runner, reboot acceptance, update/rollback acceptance, support
export, and clean uninstall still have to run on an actual supported Windows
Hyper-V host; inclusion in the ZIP is not execution evidence.

`acceptance-clean-uninstall-hyperv.ps1` is the terminal Windows gate. It requires
an output path outside managed ProgramData, invokes the explicit `clean` mode,
waits for the external uninstall proof, and independently checks that Program
Files, ProgramData, system/data disks, seed, Services, VM, NAT, and switch are
absent. The uninstaller writes `postconditionsPassed=true` only after those
checks, never before attempting the destructive cleanup.

The publisher/build host must finally run
`make platform-agent/proof/windows-lifecycle`. The verifier consumes the sealed
base/update ZIPs plus clean-host, reboot, post-reboot Runtime, update/rollback,
standard uninstall/reinstall, and terminal clean-uninstall manifests. It checks
ZIP inventories and chains release-manifest hashes, versions, boot identity,
support evidence, and host-local acceptance transitions into one
`windows-runtime-v2-lifecycle-acceptance` document. Individually passed but
unrelated manifests cannot satisfy this gate.
