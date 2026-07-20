# Runtime Console desktop shell

The Electron shell hosts the shared renderer on macOS, Windows, and Linux.
It uses `contextIsolation`, a sandboxed preload, disabled Node integration,
and one IPC channel. The main process validates that the renderer asks for a
named public request and maps it through one explicit Host-owned C52 local
administration descriptor.

For development, build the interfaces workspace first, then supply the C52
descriptor deliberately:

```sh
npm --prefix runtime-platform/interfaces run start --workspace=@tirosh-chain/runtime-console-desktop -- \
  --local-control-descriptor /absolute/path/to/host-agent.local.json
```

The descriptor is a Host Agent-owned regular JSON file. It selects either an
OS-authorized Unix domain socket (macOS/Linux) or Windows named pipe; it never
contains an HTTP port, remote address, authorization policy, secret, or Host
deployment configuration. The shell rejects an absent descriptor, symbolic
link, unknown field, remote endpoint, or arbitrary renderer-supplied path. It
does not follow redirects.

A packaged OS launcher instead passes a single explicit C53
`--operator-interface-bootstrap /absolute/path/to/runtime-console-bootstrap.json`
argument. C53 contains only `localAdministrationDescriptorPath`, the expected
C52 path. It is owned by Host installation configuration, is read as a regular
non-symlink JSON file, and is mutually exclusive with the direct C52
development option. Missing/invalid C53 or missing/invalid C52 is a visible
desktop startup failure; the shell never reads C33, discovers a port, or uses
an environment endpoint.

Package commands run only after the renderer and desktop bundle are rebuilt:

```sh
npm --prefix runtime-platform/interfaces run package:macos
npm --prefix runtime-platform/interfaces run package:macos-application
npm --prefix runtime-platform/interfaces run package:windows
npm --prefix runtime-platform/interfaces run package:linux
npm --prefix runtime-platform/interfaces run package:linux-deb
```

Their output is written below
`runtime-platform/.tmp/runtime-console-desktop/`, outside the source workspace.
`package:macos-application` emits the `.app` tree selected by the unified
macOS Runtime Platform PKG; it is a product-build input, not an additional
operator installer. The other package commands emit standalone operator
installers. Neither form has Host service authority: it cannot create C53/C52
or start a Host service. A failed/missing C53 or C52 therefore remains an
explicit application start failure.

`package:linux` produces an AppImage. `package:linux-deb` produces a Debian
package only on a Linux packaging worker; package creation must not pretend
that a macOS cross-build has proved a Debian installer.
