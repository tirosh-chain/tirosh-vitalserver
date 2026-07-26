# Runtime Platform dependency inventory

> Scope: current cross-platform source and test tooling. This is an
> implementation inventory and a reproducible source-input SPDX record, not a
> per-artifact third-party notice bundle. A shipping image/package must produce
> a per-artifact SBOM and complete notices as part of the release gate.

## Production runtime dependencies

| Component | Direct dependency | Version / source | License posture | Why it exists |
| --- | --- | --- | --- | --- |
| Host Agent | Go standard library | Go `1.23` toolchain | Go project license | HTTP, process bridge, SQLite adapter orchestration |
| Guest Runtime | Go standard library | Go `1.23` toolchain | Go project license | HTTP, state workflow, SQLite adapter orchestration |
| Guest Product Bootstrap Artifact Composer | Go standard library | Go `1.25.7` toolchain | Go project license | selected C35 release-build workflow: verifies complete declared input, preserves raw root bytes, and composes the C40 bootstrap storage artifact without shell, cache, or `PATH` discovery |
| Guest Product Bootstrap Volume Composer | `github.com/diskfs/go-diskfs` | `v1.9.3`, pinned in `tooling/guest-product-bootstrap-volume-composer/go.mod` / `go.sum` | MIT | in-process ISO9660 `CIDATA` composition for an explicit NoCloud delivery volume; it never mounts or writes Guest ext4 |
| Guest Linux Boot Artifact Extractor | `github.com/diskfs/go-diskfs` | `v1.9.3`, pinned in `tooling/guest-linux-boot-artifact-extractor/go.mod` / `go.sum` | MIT | read-only whole-disk ext4 access for declared boot-resource extraction; avoids Host `debugfs`, VM cache, container, or `PATH` dependency |
| Guest Root Storage Partition Assembler | Python standard library | Python `3.9+` | Python project license | C43 verifier/effect adapter from a C42 identity-verified whole-disk ext4 source to one declared MBR `/dev/vda1` raw base and immutable receipt; it neither chooses storage layout nor claims boot |
| Host Agent and Guest Runtime | `modernc.org/sqlite` | `v1.38.2`, pinned in each `go.mod`/`go.sum` | BSD-3-Clause according to the module `LICENSE` | pure-Go SQLite driver; keeps each state owner independent of a native SQLite library install |
| macOS provider | Apple `Virtualization` framework | macOS SDK/Xcode platform framework | Apple platform terms; not vendored source | actual `VZVirtualMachine` effect adapter |
| Windows provider bridge | Hyper-V PowerShell module and Windows SCM | Windows clean Host | Windows platform terms; not vendored source | explicit VM and Host service command adapter; live proof pending C24 runner evidence |
| Linux provider bridge | `virsh` / libvirt and `systemctl` | Linux clean Host | OS distribution/platform terms; not vendored source | explicit VM and Host service command adapter; live proof pending C24 runner evidence |
| Windows/Linux provider bridge | Go standard library | Go `1.23` toolchain | Go project license | independently compiled C21/C10/C22 bridge executable; no native command dependency is hidden in Host Agent |
| Recorder Gateway | Node.js | `>=20.19.0 <21` | Node.js project license | isolated Socket.IO protocol adapter/runtime |
| Recorder Gateway | `socket.io` | `4.8.3`, pinned in `services/recorder-gateway/package-lock.json` | MIT | Recorder-facing v4 server and explicit bundled-upstream delivery client |

`modernc.org/sqlite` and `github.com/diskfs/go-diskfs` bring transitive Go
modules. Their exact versions are locked in their owning module's `go.sum`.
The Host/Guest SQLite graphs are intentionally independent; release-build
volume composition is isolated from both runtime processes. No transitive
module is copied into `runtime-platform/`.

The Gateway's production Node dependency graph is locked in
`services/recorder-gateway/package-lock.json`. It is not copied into this
repository as source. `product/delivery/sbom-policy.v1.json` is the reviewed
source input for the generated SPDX source inventory; it is deliberately not a
release artifact SBOM. Prometheus, Jaeger, Redis, PWA, and per-artifact
packaging inputs remain explicit product/release work, not hidden dependencies.

## Development-only dependencies

| Tooling area | Pinned dependency | Use |
| --- | --- | --- |
| contract validation | `jsonschema==4.25.1` | JSON Schema Draft 2020-12 validation |
| OpenAPI validation | `openapi-spec-validator==0.7.2` | public control API validation |
| macOS provider test | Xcode Swift Package Manager / Swift Testing | compile and provider policy tests |
| Windows/Linux provider test | Go cross compilation | builds Linux and Windows bridge binaries without claiming native VM execution |
| Recorder protocol compatibility test | `ws` `8.21.1` | MIT WebSocket transport used by a small, in-repo Engine.IO v3 / Socket.IO protocol-v4 wire fixture; avoids an obsolete Socket.IO v2 client dependency |
| Recorder Gateway build/test | TypeScript `5.9.3`, `@types/node` `20.19.43` | strict compile and Node test runner typing |

These Python packages are installed only in `runtime-platform/.venv/`, which is
ignored and never a runtime/package input.

## Verification and release rule

The authoritative dependency declarations are the service-local `go.mod`,
`go.sum`, and `contracts/requirements-dev.txt` files. Review dependency changes
with:

```sh
(cd runtime-platform/services/host-agent && go list -m all)
(cd runtime-platform/services/guest-runtime && go list -m all)
(cd runtime-platform/tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN=go1.25.7+auto go list -m all)
(cd runtime-platform/tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN=go1.25.7+auto go list -m all)
(cd runtime-platform/services/recorder-gateway && npm ci && npm audit --omit=dev)
make -C runtime-platform check
```

`make -C runtime-platform source-inventory-check` verifies that the checked-in
source inventory was generated from the reviewed policy. Before a distributable
image or installer is accepted, release work must additionally produce a
machine-readable **per-artifact** SBOM, aggregate all runtime transitive
notices, apply the permissive-license allowlist in the vNext design, and attach
C24 evidence hashes/URIs. `make -C runtime-platform release-ready` fails while
any clean-host proof is pending. A successful compile, source inventory, or
portable provider test is not license/install evidence.

The root `check` target is portable. It retains pure macOS contract, archive,
assembly, evidence, and Host package policy tests, but it does not compile the
native Provider against Apple's SDK. Exactly five Host package composer tests
that execute real `pkgbuild` and `pkgutil` are explicitly skipped unless
`sys.platform == "darwin"`; no missing-tool probe changes their meaning. A macOS
development or CI host must also run
`make -C runtime-platform macos-native-check`; the matching macOS workflow job
compiles the Provider and runs the complete package suite, including those five
native integrations.
