# Runtime Platform interfaces

This directory contains operator-facing consumers of the published Host Agent
Control API. An interface may keep window, selection, filter, and draft-input
state, but it must not own or infer Host, Guest, Recorder, Lab, archive, or
upstream state.

| Directory | Role | External boundary |
| --- | --- | --- |
| `platformctl/` | cross-platform headless operator CLI | Host-published C52 local administration descriptor |
| `runtime-console-control-contract/` | named request vocabulary shared by renderer and shell | existing C1/C2/C7/C8/C9 public control contract |
| `runtime-console-web/` | React renderer with no direct transport privilege | injected narrow control transport only |
| `runtime-console-desktop/` | Electron main/preload shell | explicit Host C52 local endpoint, narrow IPC |

The desktop shell deliberately fails to start without one explicit local
control route. Development supplies a C52 `--local-control-descriptor` path.
A packaged application uses the fixed, installer-owned C53 bootstrap path for
its operating system; C53 then names the C52 descriptor. Neither path reads
C33, discovers a port, or opens a remote control address. The required
macOS/Windows/Linux local-administration adapters are described in [Operator
Control Surface](../../docs/architecture/operator-control-surface.md).

For an offline product update, the desktop shell may show exactly one native
directory chooser. The renderer does not read the chosen directory; it sends
the resulting explicit Host-local path through C69 to Host Agent. The Host
then owns copy, validation, immutable bundle identity, and C27 update
admission. `platformctl update import/read/apply` exposes the same named C69
paths for headless operators. Neither interface parses or creates C25.

The Console and `platformctl lab create/resource` expose only the two
published Guest Lab command shapes. A session create explicitly carries a new
session ID, revision zero, base name, scenario ID, and recorder count. The
Guest owns its `LAB-` naming, child-resource identities, and lifecycle state.
Before a resource action, the interfaces use the latest Guest-published
resource ID and revision; they never derive either from a display name or a
local cache. Deleting a session always declares `owned-resources`; deleting a
single bed or virtual recorder always declares `none`.

The same named vocabulary configures both supported upstream arrangements:
`external-upstream-apply` carries only a provider reference, an endpoint
configuration reference, and an optional credential reference; then
`runtime-topology-apply` selects that owned external integration. A bundled
topology is selected with its explicit bundled endpoint reference. Neither UI
nor CLI accepts a remote URL, connection header, or secret value for these
commands, because those values remain in the reviewed Guest deployment and
secret-material boundaries.

Archive credential provisioning is the one deliberately separate local-secret
command. The Guest first publishes a non-secret C51 credential reference and
availability only. Runtime Console sends transient form values through the
OS-authorized local transport and clears them after the response;
`platformctl archive credential-material provision` accepts a password only
from one stdin line. Both interfaces send the material directly to the Guest
secret-material owner, never return it, and never place it in a command-line
argument, environment variable, settings document, operation, receipt, or
state store.

NTP and observability use the same rule. `time apply` and
`telemetry apply` select the explicit `host` or `guest` owner and carry an
authority/pipeline ID, current revision, node reference, and bounded spec.
Time carries a deployment-owned source identity rather than an NTP address.
Telemetry fixes the OTLP signal set to logs, metrics, and traces, and accepts
only a collector reference plus a bounded non-sensitive attribute allowlist.
Neither interface accepts a collector URL, NTP host/port, connection header,
credential, or raw JSON document.

```sh
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces ci --include=dev
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run check
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run test
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run build
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces audit
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run package:macos
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run package:macos-application
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run package:windows
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run package:linux
PATH="$HOME/.nvm/versions/node/v22.12.0/bin:$PATH" npm --prefix runtime-platform/interfaces run package:linux-deb
```

`npm ci --include=dev` requires Node 22.12 or later within the Node 22 major;
the explicit development inclusion prevents an ambient npm production setting
from silently omitting TypeScript, Electron, or the package builder. The
committed lockfile is the source of dependency identity; `node_modules/` and
`dist/` are local development outputs. OS package artifacts are written below
`runtime-platform/.tmp/runtime-console-desktop/`, outside the source workspace,
so framework symlinks and temporary installer files cannot become source input.

The workspace-local `.npmrc` sets `legacy-peer-deps=true` for this interface
dependency graph only. `app-builder-lib` declares both `dmg-builder` and
`electron-builder-squirrel-windows` as peers. `electron-builder` installs the
required `dmg-builder` directly, while this product selects DMG, NSIS, AppImage,
and DEB targets and never selects Squirrel. Disabling npm's automatic peer
installation therefore excludes the unused Squirrel, `electron-winstaller`,
and `temp` toolchain without changing a selected package target. The desktop
dependency-graph test fails if those packages reappear, if the required DMG
builder disappears, or if the reviewed Electron Builder overrides and
minimatch/brace-expansion floors change.

The package commands build a signing-independent Electron application installer
for the selected OS: an arm64 DMG on macOS, an amd64 NSIS installer on Windows,
and an amd64 AppImage on Linux. `package:macos-application` is an internal
macOS product-build input: it emits `VitalServer Runtime Platform.app` for C47
to select and for the unified Runtime Platform PKG to install. It is not a
second operator-delivered installer. The selected architecture is explicit in
the packaging adapter and is never inferred from the build host.
`package:linux-deb` is a separate amd64 Debian package command and must run
on a Linux packaging worker; it is deliberately not treated as a successful
macOS cross-build. The installer still needs the Runtime Platform Host product
to have installed its OS-owned C53/C52 files; missing or invalid files are a
visible application startup failure, not a network fallback. A package build
is not C24 clean-host delivery proof and does not claim that an OS host-service
installer has been produced for Windows or Linux.

`npm run license-check` verifies the lockfile's explicit third-party package
license metadata against the committed permissive policy. It is intentionally
not a substitute for the platform-binary SBOM and notice review required when
Electron is packaged for an OS. `npm audit` is a separate network-backed
vulnerability gate and must pass before package creation.
