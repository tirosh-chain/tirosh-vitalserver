# Runtime v2 cross-platform conformance

Runtime v2 conformance checks the contract shared by macOS, Windows, and Linux. It does not treat a successful macOS build as evidence that Windows or Linux is implemented.

## Read-core scope

The default suite checks the smallest owner-neutral, read-only API surface needed before adding platform-specific behavior. Its single checked-in route source is [`runtime-v2-route-manifest.json`](runtime-v2-route-manifest.json).

The manifest is a build-time contract, not a runtime configuration file. It records whether a route is handled by the Platform Agent or forwarded to the Runtime Controller; it never grants wildcard forwarding or turns a missing route into a success. Each read-core entry also names its neutral OpenAPI `operationId`, and the proof rejects any method, path, or operation-id drift.

| Owner | Resource | Required meaning |
| --- | --- | --- |
| Platform Agent | `GET /platform` | installation, Platform service roles, Runtime Provider state, endpoint, and explicit failures |
| Platform Agent | `GET /platform/capabilities` | closed set of Platform capabilities using Runtime Provider vocabulary |
| Platform Agent | `GET /platform/operations` | explicit active operation, install read, and lease read |
| Platform Agent | `GET /platform/runtime-endpoint` | loaded, missing, unavailable, and failed endpoint reads stay distinct |
| Platform Agent | `GET /platform/runtime-provider` | Apple VM, Hyper-V VM, or Native provider lifecycle through one contract |
| Runtime Controller | `GET /runtime/capabilities` | owner version and unique capability identifiers |
| Runtime Controller | `GET /runtime/services` | unique product service identifiers |
| Runtime Controller | `GET /runtime/stack` | explicit stack state, observation time, services, and probe failures |

## Extension and command scope

The following published Runtime v2 routes are outside the default read-only run because they are optional capabilities or commands. They remain subject to feature conformance and installed-platform acceptance; adding one to the default run requires an explicit manifest and validator change.

| Owner | Resource | Required meaning |
| Runtime Controller | `GET`/`PUT /runtime/settings` | product settings read state and explicit apply operation |
| Runtime Controller | `POST /runtime/admin-password` | secret-bearing command with no password read-back |
| Runtime Controller | `GET`/`PUT /runtime/redis-relay/settings` | Relay config read without secret material (`usernameConfigured`/`passwordConfigured` only) and explicit username/password preserve/replace/clear apply |
| Runtime Controller | `GET /runtime/events` | Runtime-owned operation event page and opaque cursor |
| Runtime Controller | `POST /runtime/maintenance/datastore/repair` | optional Guest-owned datastore maintenance operation, negotiated through `maintenance:datastore-repair:create` |
| Runtime Controller | `GET /runtime/lab/sessions` | explicit persisted Lab session collection; absence, failure, and empty remain distinct |
| Runtime Controller | `POST /runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start|stop` | control one recorder only after explicit session-state and ownership validation |

The Platform response must not expose `vmIP`, `vmState`, `guestHTTP`, Redis UI probes, Swagger UI probes, or product service state. A platform that does not need one of the fixed service roles still reports that role with an explicit unavailable or not-installed state; it does not omit the role and ask a client to infer why. Platform service state uses the canonical values `running`, `stopped`, `not-installed`, `unavailable`, `read-failed`, `permission-denied`, and `failed`. Every service entry carries explicit nullable `readError`; launchd `loaded/not loaded` wording is not part of the cross-platform wire contract.

## Common status presentation

PWA, macOS SwiftUI, Windows, and Linux clients use the same three presentation groups even though their Platform Providers differ:

| UI group | Owner contract | Contents |
| --- | --- | --- |
| Platform services | `GET /platform` | fixed OS-owned Platform roles and their explicit service/read states |
| Runtime product services | `GET /runtime/stack` plus `GET /runtime/services/{service}/resource` | observed container/process state beside desired/control state; each product service appears once |
| Access endpoints | explicit Platform endpoint/probe/link contracts | public access and support links only when a provider reports them |

`redis-ui` and `swagger-ui` are Runtime product services. A client must not add separate `Not reported` endpoint rows merely because links are known. Likewise, a healthy observed process with a missing spec, failed resource read, or `ReconcileBlocked=true` condition is a warning, not green success. Empty, unavailable, read-failed, and healthy remain different UI states.

A client that keeps this group visible must continue reading the Runtime stack owner;
refreshing Platform health alone does not refresh Runtime product-service state. A
provider-specific Host shell may display `Initializing` while its explicit Provider
lifecycle is `starting` and its explicit Guest-control readiness input is
`missing-vm-ip`. Clients must not derive that readiness state by matching a localized
API error. Once initialization ends, Runtime stack read failures remain visible until
a successful owner read replaces them.

Linux Native has no Guest VM, while macOS and Windows use VM providers. Therefore `Host` and `Guest` are implementation details, not the common section names. Platform-specific screens may expose provider details below these groups, but must not merge Platform ownership into Runtime product state.

Installation state and installed version come from the Platform-owned install document. An executable, symlink, service registration, or filename is not evidence of an installed product. Linux uses `/var/lib/vitalserver/install.json` and Windows uses `C:\ProgramData\VitalServer\install.json`; missing, unconfigured, invalid, and read-failed owner states remain distinct.

## Commands

Provider lifecycle mutations use the canonical routes
`POST /platform/runtime-provider/start`, `stop`, and `restart`. Their response
keeps the OS service effect (`completed|failed`) separate from the included
Provider lifecycle resource. These mutations are exercised by platform
acceptance rather than the default read-only conformance run so a contract
check never starts or stops an installed Runtime unexpectedly.

### Guest datastore maintenance

Datastore repair is a Runtime Controller extension, not a Host repair command.
When the Runtime Controller advertises
`maintenance:datastore-repair:create`,
`POST /runtime/maintenance/datastore/repair` requests the Guest-owned repair
and returns `202 Accepted` with the persisted
`RuntimeGuestControlServiceOperation`. The response preserves the operation
identity, command `repair-datastore`, state, timestamps, and typed failure;
it must not be translated into Host shell output or an empty successful
response. A failed terminal operation remains an explicit operation document
in that `202` response.

The common PWA repair controls in this boundary are limited to Runtime Provider
restart when the Platform capability permits it and datastore repair when the
Guest capability above is present. It does not render or call proxy repair or
VM-disk repair. Those actions are optional platform-maintenance extensions
(for example, a macOS native repair workflow), not portable Runtime Controller
behavior. A platform that does not offer such an extension must report it as
unavailable through its explicit platform contract; the PWA must not probe
undocumented routes or turn a `404` into an inferred disabled state.

Test the conformance rules without a live runtime:

```sh
make runtime/proof/conformance
```

Validate a live Platform Agent and Runtime API gateway:

```sh
make runtime/conformance \
  RUNTIME_V2_CONFORMANCE_BASE_URL=http://127.0.0.1:18321
```

For an authenticated endpoint, set `VITALSERVER_RUNTIME_CONTROL_TOKEN`. To check only one owner during platform bring-up, pass an explicit mode:

```sh
make runtime/conformance \
  RUNTIME_V2_CONFORMANCE_BASE_URL=http://127.0.0.1:18321 \
  RUNTIME_V2_CONFORMANCE_ARGS=--platform-only
```

`--runtime-only` checks the Runtime Controller surface. Transport failure, HTTP failure, JSON decode failure, and contract failure are reported separately; none becomes an empty successful response.

## Platform acceptance matrix

Conformance is necessary but does not prove installation or lifecycle behavior. Each platform must record these additional results.

| Gate | macOS / Apple VM | Windows / Hyper-V VM | Linux / Native |
| --- | --- | --- | --- |
| live conformance | required | required | required |
| offline package install | PKG/DMG | MSI | DEB/RPM/tar |
| installed health and PWA | required | required | required |
| service start/stop/restart | launchd | Windows Service | systemd |
| Product Stack smoke | Compose in VM | Compose in VM | native Compose |
| update and rollback | required | required | required |
| user and Runtime data preservation | required | required | required |

An unavailable platform runner is an unexecuted acceptance item, not a pass. Runtime v2 cross-platform completion requires evidence from all three columns.

The Linux offline artifact builder and checksum/install transaction now exist.
It requires an explicit portable Runtime Bundle directory and Docker/OCI image
archive, keeps immutable releases separate from `/var/lib/vitalserver` data,
and restores the previous release pointer when installed API acceptance fails.
Linux Native Redis Relay status uses a dedicated root-owned Unix-domain socket
mounted read-only into the relay container. The Runtime Controller keeps its
general API on loopback; the socket handler exposes only the Relay status
`PUT` mutation. VM runtimes keep the Guest Control HTTP transport inside their
Guest network.
For an existing Linux installation, the installer adds only missing private
transport values to `/etc/vitalserver/runtime.env`. It rejects a non-empty
legacy status-owner URL, duplicate owner values, or a mismatched explicit
value instead of silently changing transport. The installer backs up that
owner before migration and restores it if the enclosing transaction fails;
an operator must make an intentional configuration change to leave a legacy
URL transport.
On 2026-07-11 the resulting `linux/amd64` archive was exercised in an
independent Ubuntu 24.04 x86_64 QEMU machine. Clean offline installation,
0.2.0 to 0.2.1 update, an interrupted 0.2.2 update with restoration to 0.2.1,
and same-version reapplication all completed with explicit evidence. A later
0.2.3 candidate also exercised an explicit Platform Agent configuration
migration and preserved its rollback lineage across same-version reapplication.

The installer writes
`/var/lib/vitalserver/proof/linux-native-acceptance.json`. A passed document
requires the Runtime Provider lifecycle owner, Platform contract, Runtime
capabilities/services/stack, product settings, Runtime event page, and common
PWA to be reachable after systemd installation. A direct installation also
requires an actual managed support-export workflow and verifies its artifact
path, digest, and byte size before installation state can be published. An
installer running inside `update-apply` instead verifies the capability and
records the enclosing operation identity without trying to overwrite the
single durable workflow owner. The latest 0.2.9 update acceptance run was
`035cead8-1996-4f30-adf8-37937d96b1a3`; its separate post-update full
acceptance run was `0deaed7b-113c-46cc-be21-bb539dee0000`. The interrupted
update returned exit status 143, restored `current` to `releases/0.2.1`, and
removed the uncommitted 0.2.2 release.
The same installed acceptance performs a Platform API Native Provider
stop/start round trip, waits for explicit `stopped` and `running` lifecycle
documents, and proves Runtime Controller capabilities are reachable again
before the installer publishes `install.json`.

Linux keeps the active install intent in the root-only
`/etc/vitalserver/install-transaction.json` and writes the immutable payload
completion receipt to `/etc/vitalserver/release-complete/<version>.json` only
after the release-path Guest Tools venv install succeeds. A same-version retry
may resume an incomplete release only with that matching transaction; an
existing `release.json` by itself is never completion evidence. Existing
installations that predate the receipt are migrated only when their current,
root-owned install owner and acceptance run match the requested release. The
transaction remains after interruption and is removed only after the new
`install.json` is atomically published. A resumed first install with no prior
release preserves its partial Host owners and the transaction if another run
fails; it does not infer which partial files are safe to delete.

The Linux Platform Agent now exposes a durable current Platform workflow and
schedules bundle verification as an independent transient systemd operation.
Its default delivery policy is `verify-only`. Update apply is reported as a
capability only when configuration explicitly selects `sha256-allowlist` and a
root-owned digest document is available; the Agent hashes the exact archive
again immediately before scheduling apply. A missing or invalid trust document
is an unavailable dependency, while a digest absent from the allowlist is an
untrusted bundle. Neither state is converted into a successful verification or
an implicitly disabled operation. Linux publisher trust provisioning now
copies and hashes the same byte stream into a root-owned `0700` inbox, writes a
`0600` digest catalog/config transaction, and restores both owners if Agent
restart fails. It does not weaken systemd `PrivateTmp` or derive trust from the
archive it is asked to trust. The live trusted apply workflow
`workflow-fe51f1b471921783fabf8878d9b41e90` completed against the staged 0.2.4
archive and passed installed acceptance run
`4d493a04-5c30-4a9b-ac62-55e92a4ed963` while preserving the existing data
markers. Windows still requires its real-host execution evidence.

The publisher-side catalog is generated from the final immutable archives,
not on an installation target:

```bash
python3 scripts/build_update_trust_catalog.py \
  --archive dist/VitalServer-Linux.tar.gz \
  --archive dist/VitalServer-Windows.zip \
  --output dist/trusted-bundle-digests.json
```

The command prints the catalog SHA-256 and each archive identity. Release
automation must publish the archive and the catalog digest through separate
authenticated release metadata. The target administrator verifies that
metadata, then passes the exact archive path and publisher-provided archive
digest to `trust-update-linux.py` or `trust-update-windows.ps1`. The target
tools never trust a digest merely because they computed it locally.
The catalog builder also inspects Windows ZIP state and refuses an unsealed
`acceptanceCandidate`, a pending proof, or a missing installed acceptance
identity. A bootstrap artifact therefore cannot enter the publisher allowlist
by mistake.

Platform support export is also a durable workflow at
`POST /platform/support-exports`. The caller supplies no filesystem path.
Linux writes a root-only archive under `/var/lib/vitalserver/support`, Windows
writes under `%ProgramData%\VitalServer\support`, and macOS writes under its
managed product support directory. A completed workflow must contain the
absolute artifact path, lowercase SHA-256, and byte size. Product settings,
Platform API configuration, token owners, secrets, and datastore contents are
outside the collector allowlist.

On the independent Ubuntu 24.04 x86_64 machine, support workflow
`workflow-32ea7b1220e28c26c868ee8688d8208a` completed during the 0.2.6
installed acceptance. It published a 41,318-byte archive with SHA-256
`92d93c6b412ad16146a9de32df70c067414fcd5716edf3c334ca632bd906b1e8`.
The manifest recorded every owner, systemd status, and journal source with a
distinct state and archive path. A direct scan of the archive for the actual
Platform API token byte sequence returned false. Local proof copies are
`linux-native-0.2.6-acceptance.json` (SHA-256
`4438b9d1d172f44767e52a5ca82c1df89c17d8ed653622dbe53cb90d8b8307b1`)
and `linux-support-export-workflow.json` (SHA-256
`3c28999a568748f5cfbdf14be6d25e31b3148154727d2b42c8ab0e754c7127a9`).

The final 0.2.9 trusted update completed as Platform workflow
`workflow-bb613dbfe95b3cbddc1504a6bef615ca`, publishing release evidence for
Platform 0.2.9 and Runtime Bundle 0.2.0. The post-update full acceptance then
completed support workflow `workflow-01ca0f8db554ef7683cb88539bfac802`.
Its managed artifact was 41,652 bytes with SHA-256
`79e253a5491420f98910592a129bb93f492c7e23f74cf4661d7e87d665bdb34f`;
the actual API token byte sequence was absent. Local proof copies and hashes
are:

- `linux-native-0.2.9-update-acceptance.json`:
  `1296359d5656b14fade99cc75934a3f7b76287e2f81e6d18332ff655985423be`
- `linux-native-0.2.9-post-update-acceptance.json`:
  `4dbc7680b871cca3f5b89d4f25c09cdb02524ce407ea2f4b7d69413fb65976c0`
- `linux-support-export-0.2.9-workflow.json`:
  `c27c202b9346ee65df5c4c58afb80e031b3faeb2c998c22d8e65de0744be13a6`

The installed acceptance run ID was
`3e2073d4-62aa-470c-b212-612c929037de`. That same 0.2.6 installation recovered
an explicit 0.2.5 packaging failure in
which config named the support tool but the immutable release omitted it; the
pre-activation copy and installed acceptance now prevent that mismatch.
The publisher tool generated the 0.2.6 Linux archive digest
`fe9dd18e01350b0c39038c13267ec990c7d6e91f825bc934d429348d6afd44ac`
and deterministic catalog digest
`63b0127597ebffd0e0cadd9230a7789268acfab88a2f74c22d99e40a972e08eb`.

Linux release rollback is a separate Platform workflow at
`POST /platform/releases/rollback`; it is not represented as a caller-selected
backup path. The install owner supplies `previousRelease`, the existing atomic
symlink/install-owner restoration remains the rollback effect, and a transient
wrapper publishes accepted, running, completed, or failed workflow state. The
capability is distinct from backup rollback so clients do not reuse one
operation's meaning for the other.

Each release stores the three systemd unit files that belong to that release.
When an update encounters an older release that predates those snapshots, the
installer performs one explicit migration before activation: it validates the
currently installed units and writes all three into the Host-owned migration owner
`/etc/vitalserver/release-systemd-units/releases/<version>` through a
temporary directory and atomic publish. The immutable old release is not
modified. A pre-existing migration snapshot must be root-owned, complete, and,
for a fresh or non-resumed reapplication, byte-identical to the current units.
For a matching resumed transaction, the snapshot is the immutable
previous-release source while the live units can already belong to the candidate
release. That path validates the snapshot but deliberately does not compare it
with live units; it also refuses to create a missing snapshot from candidate
state and preserves the transaction for the same verified-bundle retry.
Otherwise missing, partial, or mismatched snapshots are a hard update/rollback
failure, never a reason to guess from the new release. Rollback restores the
target release's bundled units or its explicit migration snapshot before daemon
reload and service restart. This owner is deliberately outside the Guest Runtime
Controller write scope; Guest-controlled runtime data cannot alter the Host
rollback unit source. If install rollback cannot restore the previous units, it
preserves a snapshot created for that migration rather than deleting the only
explicit source needed for the next recovery attempt.

`delivery.rollbackTool` is deliberately different from the other Linux delivery
tools: installation records the new release's immutable absolute path
`/opt/vitalserver/releases/<version>/tools/rollback-linux.py`, rather than the
moving `current` symlink. The durable Platform Agent configuration is preserved
when a rollback switches `current` back to an older release, so a second
rollback still invokes the implementation that knows both the bundled-unit and
migration-snapshot contracts. `updateTool`, uninstall, and support-export stay
current-symlink tools. Configuration migration accepts only the old explicit
current-symlink form or an existing release-owned rollback tool; an unavailable
or invalid owner is a hard migration failure and the update rollback restores
the previous configuration.

Each Linux bundle also installs
`tools/acceptance-update-rollback-linux.py`. On a trust-configured supported
host it creates an explicitly selected mutable-data sentinel, schedules the
update, waits for the matching durable operation and install-owner version,
schedules owner-selected release rollback, verifies the original versions,
and proves the sentinel is byte-identical after both transitions. Its manifest
is the required update/rollback/data-preservation evidence; unit tests of the
runner are only workflow tests, not machine acceptance.

After installing from an extracted release bundle, standard uninstall and
same-bundle reinstall are exercised from that extraction (not from the
installed release that the workflow removes):

```bash
sudo ./VitalServer-Linux/packaging/acceptance-uninstall-reinstall-linux.py \
  --bundle-directory "$PWD/VitalServer-Linux" \
  --api-token-path /etc/vitalserver/secrets/platform-api-token \
  --install-document /var/lib/vitalserver/install.json \
  --operation-document /var/lib/vitalserver/run/platform-workflow.json \
  --data-sentinel /var/lib/vitalserver/data/uninstall-reinstall.sentinel \
  --output-manifest /var/lib/vitalserver/proof/linux-uninstall-reinstall-acceptance.json
```

The output is release evidence only when `status` is `passed`; a script copied
into the bundle or a unit-test result is not machine acceptance.

On 2026-07-11 the 0.2.4 bundle passed this workflow on the independent Ubuntu
24.04 x86_64 QEMU machine. Standard uninstall removed `/opt/vitalserver` and
the install owner, then same-bundle offline reinstall passed installed
acceptance run `d899021b-7d1e-4cef-a29d-f66f0acf220b`. The enclosing proof run
`b1e2b4e0-ab25-4d1a-82a0-e8db47074cb2` preserved the mutable owner digest,
Postgres volume identity, and its generated Runtime data sentinel. The older
Vital Files sentinel, Postgres row, and Redis key were also checked explicitly
after reinstall and remained present.

The initial live transaction compared nine Platform/Runtime owner files and
secrets by SHA-256 and checked an explicit Vital Files sentinel, Postgres row,
and Redis key after update, interrupted rollback, and idempotent reapplication.
The later 0.2.3 candidate intentionally migrated only the Platform Agent
delivery document; the other eight owner/secret hashes and all three data
sentinels remained identical. Three platform services were active, the Runtime
Provider owner returned `running`, and all eleven Compose services remained
running after rollback; a transient `starting` health value was preserved as
such rather than guessed healthy.

Linux install and rollback owners also record the kernel boot ID. The bundled
`tools/acceptance-reboot-linux.py` refuses to pass on the same boot, reruns the
full installed Runtime and Provider lifecycle acceptance on the new boot, and
links that acceptance runId into a separate reboot proof. Merely restarting
services cannot satisfy this gate.

The same Linux machine passed reboot proof run
`55a46175-c058-4d0a-85a8-fbec0c318ce1`. Its installed boot ID
`a7914a28-fbca-4121-bae2-3b75064ff668` differed from the observed post-reboot
boot ID `72df9174-1b5d-49a6-8c73-06272f27a795`, and the linked full Runtime
acceptance run was `850b1b0f-94f0-4a24-99b9-4da27c5a0adb`. Mutable settings,
secrets, Vital Files, Postgres, and Redis preservation were rechecked after the
new boot.

## Current status

The macOS Platform API no longer exposes `/runtime/overview` or its stream.
Those Host-composed Platform, settings, install, release, and VitalDB DTOs were
removed from Swift, OpenAPI, and PWA validation. The common PWA reads
`/platform`, `/runtime/stack`, settings, and VitalDB resources independently
and combines them only for presentation.
The old `/runtime/events/stream` was also removed because it polled a separate
Host event repository. `GET /runtime/events` remains and reads the Runtime
Controller operation-event owner directly; the PWA paginates and polls that
canonical resource.

The macOS native control panel also applies Redis Relay settings only through
the Runtime Controller owner API. Legacy Host configure DTOs/effects, the CLI
settings-file option, `RuntimeRedisRelayConfigurationWriter`, and the unused
temporary settings-file environment contract are removed. Static proof checks
both the Runtime Controller gateway call and the absence of that Host writer.
Host watchdog/recovery policy does not accept Guest service, container,
VitalDB, or Redis Relay product state as a recovery input; it remains limited
to Host-owned VM, proxy, and Platform service boundaries.
The canonical settings boundary no longer mixes Host and Runtime Product state.
`GET/PUT /runtime/settings` remains Runtime Controller-owned Product Settings,
while `GET/PUT /platform/settings` is a separate Platform Agent contract for
Host resources, network exposure, local paths, boot/recovery, backup, and log
retention. The Platform document excludes Runtime credentials and read-only
owner fields are excluded from the apply document. macOS maps this contract to
its explicit Host settings owner and refuses apply when that owner reports any
read issue. The shared Windows/Linux Agent currently returns a typed `501`
instead of manufacturing settings; its resource/network edit capabilities stay
false until those Platform adapters own the state. The macOS Swift package currently passes all 2,051 tests, including
the architecture proof that prevents the Host Redis Relay writer from
returning and lifecycle proofs that include the Platform Agent in fresh
install and uninstall state.

The macOS implementation is the reference implementation. Its API listener is a
dedicated launchd Platform Agent, not a UI process. Windows and Linux now share a
small Go Platform Agent core that cross-compiles offline, implements the Windows
Service protocol, reads SCM/systemd state through native structured APIs, and
passes live Platform plus core Runtime conformance through its closed
`/runtime/*` forwarding boundary. The Runtime Controller owns the canonical
`/runtime/*` namespace directly; the Agent does not translate a legacy
namespace. Linux now also has a systemd-supervised Native Runtime Provider that
drives the common Compose bundle, owns the explicit lifecycle state machine,
and publishes the Runtime endpoint only after Controller readiness succeeds.
Windows now has a Windows-Service-hosted Hyper-V Provider using the same state
machine. It invokes fixed Hyper-V cmdlets without interpreting PowerShell
output as state, waits for Controller readiness at an explicitly configured VM
address, and requests graceful guest shutdown without forced power-off.
Platform Agent Provider commands use native systemd D-Bus or SCM APIs and keep
the command effect result separate from the Provider-owned lifecycle document.
The Hyper-V provisioning boundary now verifies feature availability, VHDX
identity, internal switch/NAT identity and existing VM ownership without
deleting mismatched resources. The product Hyper-V VHDX build, production
Windows artifact assembly, and installed
acceptance evidence are still required before cross-platform Runtime v2 can be
called complete.

The Windows image compile contract is now explicit: a passed `linux/amd64`
rootfs proof, a system disk with an EFI System Partition, a persistent Runtime
data disk, and a NoCloud seed ISO. The staging proof records SHA-256 and byte
identity for all three raw inputs after the deploy payload is staged; the image
compiler snapshots and compares those exact bytes before conversion. It also
requires the Runtime data raw disk to be an ext4 filesystem labeled
`vital-runtime`. The system image carries the deploy payload; the Runtime data
disk survives system-image replacement. The seed configures a fixed internal
Hyper-V address and native bind mounts, so Windows does not need to emulate the
macOS VirtioFS share. Image conversion proof is not Windows boot proof; release
packaging must still require a real Hyper-V boot/conformance manifest from a
supported Windows runner.

Windows artifact assembly enforces that distinction: the deterministic ZIP
The Windows builder has two explicit modes. `--acceptance-candidate` creates a
non-distributable ZIP with `state=acceptanceCandidate`, a null installed
acceptance identity, and an explicit pending proof. This is the only artifact
used to bootstrap the first installed proof. After that proof is copied back,
`--acceptance-manifest` seals `state=releaseCandidate`. Sealing rejects a
missing/failed manifest and rejects a passed manifest whose image-manifest
SHA-256 does not match the bundled Hyper-V image.
The acceptance manifest must include Platform and Runtime core contracts plus
product settings, Runtime events, and the common PWA. Mutable Runtime config,
product settings, and Compose environment live on the persistent Runtime data
VHDX, not the replaceable system VHDX.
The Windows Service installer now runs that acceptance before publishing
installation state. It verifies that Platform config, API token owner, Runtime
Provider owner path, release versions, and acceptance proof refer to the same
installation, then atomically writes the explicit ProgramData `install.json`
owner without a UTF-8 BOM. Service or acceptance success alone is not inferred
as installed state. Windows acceptance also executes a Platform API Provider
stop/start round trip, waits for explicit `stopped` and `running` owner states,
and proves that the Runtime Controller becomes available again afterward.
The install owner also records the Windows host boot-session identity derived
from `Win32_OperatingSystem.LastBootUpTime`. The bundled reboot acceptance
refuses the original boot session and reruns the complete Hyper-V acceptance,
linking its runId only when that proof reports the current boot session.
The ZIP remains a release candidate until it is wrapped and signed by the
production Windows installer pipeline and its clean-host lifecycle gates pass.

The release-candidate ZIP now contains an elevated offline installation entry
point. It verifies the complete checksum inventory and rejects path escapes or
reparse points, stages an immutable Program Files release, creates hardened
ProgramData config/token owners, provisions the three Hyper-V artifacts, and
runs Service plus installed acceptance before `install.json` can appear.
Acceptance is bound to the exact Agent binary, Hyper-V Provider binary, PWA
tree, image-manifest, and packaging/config tree hashes from the installed
release manifest; image and version agreement alone is not sufficient release
evidence. The update verifier refuses `acceptanceCandidate`, so that bootstrap
artifact cannot enter the product update channel. MSI wrapping,
publisher signing, and execution on a clean supported Windows host remain open
production gates.

Build and install the unsealed candidate on the first Windows acceptance runner:

```bash
make platform-agent/package/windows-acceptance-candidate \
  WINDOWS_PLATFORM_VERSION=2.0.0 \
  WINDOWS_RUNTIME_BUNDLE_VERSION=2.3.4 \
  WINDOWS_HYPERV_IMAGE_DIR=/absolute/path/to/hyperv-image
```

From an elevated PowerShell session:

```powershell
& .\VitalServer-Windows\packaging\install-windows.ps1 `
  -BundleDirectory .\VitalServer-Windows
```

Copy `%ProgramData%\VitalServer\proof\windows-hyperv-acceptance.json` back to
the build host and run `make platform-agent/package/windows` with
`WINDOWS_HYPERV_ACCEPTANCE_MANIFEST` to produce the sealed candidate. A second
clean-host install gate validates that sealed ZIP itself.

Before update apply, an administrator must obtain the ZIP digest through the
release channel and provision that exact value from the currently installed
immutable release:

```powershell
$install = Get-Content "$env:ProgramData\VitalServer\install.json" -Raw | ConvertFrom-Json
& (Join-Path $install.releasePath "packaging\trust-update-windows.ps1") `
  -BundlePath C:\Updates\VitalServer-Windows.zip `
  -ExpectedSHA256 <publisher-provided-lowercase-sha256>
```

The update/rollback/data proof is then produced with
`acceptance-update-rollback-hyperv.ps1`. On a host installed from that same
sealed ZIP, standard uninstall/reinstall preservation is proved separately:

```powershell
$install = Get-Content "$env:ProgramData\VitalServer\install.json" -Raw | ConvertFrom-Json
& (Join-Path $install.releasePath "packaging\acceptance-uninstall-reinstall-hyperv.ps1") `
  -BundleDirectory C:\Acceptance\VitalServer-Windows `
  -OutputManifestPath C:\Acceptance\windows-uninstall-reinstall.json
```

The runner requires a `releaseCandidate`, calls only the standard uninstall
workflow, waits on its durable ProgramData document after the Agent disappears,
and reinstalls the same sealed bytes. It proves that config/token bytes, the
Runtime settings marker, and the data VHDX identity survive, that provisioning
reports `preserved-existing`, and that reinstall publishes a new host-local
installed acceptance ID. The sealed bundle acceptance ID and a host-local
install acceptance ID have different meanings and are not equated.

These commands describe acceptance artifacts; they do not turn an unexecuted
Windows job into a pass. Windows completion requires actual clean-host install,
reboot, update/rollback, standard uninstall/reinstall, support-export, and clean
uninstall results from supported Hyper-V hardware.

Clean uninstall is the terminal gate and must run last. Its manifest must live
outside managed ProgramData:

```powershell
$install = Get-Content "$env:ProgramData\VitalServer\install.json" -Raw | ConvertFrom-Json
& (Join-Path $install.releasePath "packaging\acceptance-clean-uninstall-hyperv.ps1") `
  -OutputManifestPath C:\Acceptance\windows-clean-uninstall.json
```

The uninstall implementation publishes its external completed proof only after
Program Files, ProgramData, both VHDX files, seed, Services, VM, NAT, and switch
postconditions pass. The acceptance runner then checks that proof and the
resources independently. If cleanup fails after deleting the internal workflow
document, the uninstaller instead publishes an external failed proof with its
reason without recreating managed ProgramData, and the acceptance runner stops
immediately. A proof written before
destructive postconditions is not accepted.

After copying the terminal proof back to the build host, the complete evidence
set is accepted only through the identity-chain verifier:

```bash
make platform-agent/proof/windows-lifecycle \
  WINDOWS_SEALED_BUNDLE=/evidence/VitalServer-Windows-2.0.0-amd64.zip \
  WINDOWS_CLEAN_HOST_ACCEPTANCE=/evidence/clean-host-acceptance.json \
  WINDOWS_REBOOT_PROOF=/evidence/reboot.json \
  WINDOWS_REBOOT_RUNTIME_ACCEPTANCE=/evidence/reboot-runtime.json \
  WINDOWS_UPDATE_BUNDLE=/evidence/VitalServer-Windows-2.0.1-amd64.zip \
  WINDOWS_UPDATE_ROLLBACK_PROOF=/evidence/update-rollback.json \
  WINDOWS_UNINSTALL_REINSTALL_PROOF=/evidence/uninstall-reinstall.json \
  WINDOWS_CLEAN_UNINSTALL_PROOF=/evidence/clean-uninstall.json \
  WINDOWS_LIFECYCLE_ACCEPTANCE_OUT=/evidence/windows-runtime-v2-lifecycle.json
```

The verifier checks both ZIP checksum inventories and binds platform/runtime
versions, immutable release-manifest SHA-256, update archive SHA-256, boot
sessions, sealing acceptance, host-local install acceptance transitions,
support artifact evidence, and every required passed stage. It rejects reused
run IDs and evidence assembled from different releases or host lifecycle
chains. Only its `windows-runtime-v2-lifecycle-acceptance` output is the final
Windows v2 lifecycle gate; a folder of unrelated passed JSON files is not.

Windows Platform delivery now has a scheduler adapter distinct from systemd.
It creates a one-shot SYSTEM Scheduled Task so verification, update, and
rollback continue while Agent and Provider Services restart; task launch
failure is written back to the durable Platform workflow owner. The Windows
bundle verifier performs bounded, canonical ZIP extraction and complete
checksum-inventory verification before any apply effect.

The update transaction stages a new immutable release and versioned system
VHDX/seed, leaves the existing Runtime data VHDX attached, and then switches VM
attachments, Platform config, provision/install owners, and Service binaries.
Failure restores every saved owner and attachment and reruns acceptance on the
old release. Release rollback takes its target only from the install owner's
`previousReleasePath`; callers never provide a rollback path. The bundled
update/rollback acceptance writes a temporary marker through the Runtime
Controller settings owner, proves it after system-image update and rollback,
and restores the original settings. It does not mount or inspect the Runtime
data VHDX from Host code.
Fresh Windows installs remain `verify-only`. An elevated local trust tool can
enable apply only when an administrator supplies the exact archive SHA-256
obtained out of band and the local ZIP matches it; the tool writes an
ACL-restricted digest catalog and then restarts the Agent. It never derives a
digest from the bundle and declares that same value trusted.

Hyper-V provisioning treats the Runtime data VHDX as mutable state, not as an
immutable release artifact. It verifies the source only when creating the disk;
an existing destination is preserved even though normal Runtime use changes
its bytes. Provision evidence records `created` versus `preserved-existing`,
the source digest, and a point-in-time observed digest separately. This keeps
reinstall/idempotence from rejecting healthy user data as a checksum mismatch.

Windows uninstall is a durable Platform workflow, not a synchronous command
result. Before deleting anything, the workflow matches the explicit install,
Provider, and provision owners against the actual VM identity, its system/data
disks and seed, and the managed NAT and internal switch. Standard uninstall
removes the VM, Services, replaceable system artifacts, and immutable releases
while preserving the Runtime data VHDX and ProgramData settings. Clean
uninstall removes ProgramData as well and writes its final proof outside that
tree. The common API returns a `202 PlatformWorkflowOperation`; a caller can
therefore retain the operation ID even while the Agent Service is being
removed. Static packaging tests prove these boundaries, but clean-host and
data-preserving uninstall/reinstall still require execution on the supported
Windows Hyper-V acceptance runner.

Linux uses the same durable uninstall contract without introducing a common
platform abstraction for the different effects. Its workflow validates the
install owner, current release symlink and release document, Native Provider
and Platform delivery configs, and all three systemd unit owners before the
first stop or delete. Standard mode runs Compose down without `--volumes`,
removes systemd units and replaceable `/opt/vitalserver` releases, and keeps
the explicit config, Runtime data, logs, and Docker named volume. Clean mode
adds `--volumes` and removes `/etc/vitalserver`, `/var/lib/vitalserver`, and
`/var/log/vitalserver`; its final proof is outside those roots.

The Linux offline bundle contains a standard uninstall/reinstall acceptance
runner. It records a Runtime data sentinel, a digest over mutable config and
secret owners, and the Postgres Docker volume identity; waits for the local
durable uninstall operation after the Agent disappears; reinstalls from the
same offline bundle; and requires all three preservation proofs plus a new
installed acceptance owner. Unit tests verify the workflow structure, but the
manifest becomes release evidence only when executed on the supported Linux
acceptance host.

The initial Windows v2 support baseline is Windows 11 24H2 or later on a
Pro-or-higher edition (Pro, Enterprise, or Education) with hardware
virtualization and SLAT available. Windows Home is explicitly unsupported
because the Hyper-V role is unavailable there. Windows Server remains a future
acceptance target rather than an inferred supported platform. These constraints
follow Microsoft's [Hyper-V installation requirements](https://learn.microsoft.com/windows-server/virtualization/hyper-v/get-started/Install-Hyper-V),
[Windows 11 requirements](https://learn.microsoft.com/windows/whats-new/windows-11-requirements),
and [Windows 11 release information](https://learn.microsoft.com/windows/release-health/windows11-release-information).
