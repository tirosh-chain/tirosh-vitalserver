# macOS Virtualization Provider

This provider adapts macOS virtualization APIs to the Host provider contract.

It owns platform-specific API calls and translates their results into explicit provider outcomes. It does not define product lifecycle policy or Guest readiness rules.

## macOS virtual machine command CLI

`macos-virtual-machine-command-cli` reads one C21 `PlatformProviderLifecycleInvocation` JSON document from standard input and writes one C10 `ProviderLifecycleResult` JSON document to standard output. The invocation carries the Host-durable `requestId` and expected Guest endpoint revision. Host, not this adapter, owns the operation/idempotency ledger; the command CLI validates the correlation before any effect. The Go Host Agent calls this executable through a typed Platform Provider process adapter; neither side imports the other’s source.

The Swift library contains an `AppleVirtualMachineController` adapter over `VZVirtualMachine`. `macos-virtual-machine-command-cli --virtual-machine-configuration <absolute-path>` loads C32 `MacOSVirtualMachineConfiguration`, the Host-owned deployment contract: machine identity, CPU/memory, Linux kernel/initrd/command line, every disk image, and explicit NAT MAC address. It rejects traversal, missing configuration, invalid JSON, invalid VM configuration, and inaccessible disk images as typed `unavailable` or `failed` outcomes; it never discovers assets from an installation directory or VM name.

C32 also requires `GuestBootConsoleCapture`. The Host provider opens its declared
append-only capture file and attaches it as the Guest's `hvc0` serial output;
the supervisor retains the output handle for the VM lifetime. The capture file
is diagnostic evidence for Linux kernel and early boot output only. It is not
a Guest Runtime readiness check, it does not create Host or Guest lifecycle
state, and an empty capture must not be formatted as successful boot.

C32 `GuestRuntimeDiskProvisioning` names a different boundary: the immutable
C34 `GuestRootStorageReleaseArtifact`, a Host-owned
`GuestRuntimeDiskWorkspace`, and its provisioning receipt. Before the provider
constructs `VZVirtualMachine`, `GuestRuntimeDiskProvisioner` verifies the
release manifest and source bytes, atomically creates the workspace when both
workspace and receipt are absent, or retains it only when its receipt matches
the configured release identity. It never attaches the immutable release root
as the writable Guest root and never treats an existing file without a matching
receipt as usable state.

Without this explicit flag, the command CLI returns `observedState=unavailable` with `macos-vm-not-configured`. This is deliberate: an unconfigured command CLI must not report a running VM. Host Agent passes the same document only when the selected provider is `macos-virtualization` and C32 is explicit.

For a real controller, start and stop results report the observed VZ state. A successful stop request that only reaches `stopping` remains `stopping`; it does not claim `stopped` or Guest Runtime readiness.

## Persistent ownership requirement

`macos-virtual-machine-command-cli` is an invocation test adapter, not the persistent
macOS release provider. It creates `VZVirtualMachine` in a one-shot process,
so its object cannot remain the owner after stdout returns. A real product
deployment requires `MacOSVirtualMachineSupervisor`: a long-lived process that
retains the controller and receives newline-delimited C21/C10 documents over
its explicit standard-input/standard-output process transport.
`macos-virtual-machine-supervisor --virtual-machine-configuration <C32>` now
provides that owner process. Until Host composition and package layout start
and retain this executable instead of the one-shot CLI, this package must not
be used as evidence that an installed Guest VM remains running. See [macOS
Virtual Machine Supervisor Boundary](../../../docs/architecture/macos-virtual-machine-supervisor-boundary.md).

## Virtualization entitlement signature boundary

Apple Virtualization checks the entitlement of the **process that constructs
`VZVirtualMachine`**. In the installed product that process is
`macos-virtual-machine-supervisor`, not the Host Agent and not the PKG
installer. The release artifact therefore has two named, independently
verified signatures:

| Signed artifact | Release-build responsibility | Required fact |
| --- | --- | --- |
| `macos-virtual-machine-supervisor` | `MacOSVirtualMachineSupervisorCodeSigning` | `com.apple.security.virtualization=true` in the staged executable signature |
| macOS PKG | package signing configuration | installer identity and integrity |

`MacOSVirtualMachineSupervisor.entitlements` is the source entitlement
document for the first responsibility. The package composer copies the
already-built supervisor into its temporary payload, signs that staged copy,
then runs both `codesign --verify --strict` and an explicit entitlement read
before `pkgbuild` can publish the PKG. It never signs the supplied build
artifact in place. A signed PKG is rejected unless its contained supervisor
has a signed supervisor contract; an unsigned development PKG can still carry
a signed supervisor for local Virtualization smoke work.

This validates the release-build signature boundary only. It is not evidence
that the host installed the package, launchd retained the supervisor, a Guest
booted, or the Guest Runtime became ready.
