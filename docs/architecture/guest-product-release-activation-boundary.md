# Guest Product Release Activation Boundary

## Purpose

This boundary turns one release-owned Guest Product archive into an explicit
Guest release activation request. It exists so a Host update can update the
Guest Product without writing the Guest filesystem, changing the `current`
link, or interpreting Guest service health from the Host.

The boundary has four distinct owners:

| Contract or role | Owner | Responsibility |
| --- | --- | --- |
| C26 layer declaration | staged Host updater | Names immutable archive, C61 configuration, and fixed execution order. |
| C61 `GuestProductReleaseEffectExecutorConfiguration` | release process | Declares the one Host-local C32 endpoint and the exact apply/rollback release transition. |
| C59 release command and operation | Guest Product Release Manager | Stages the archive, activates `current`, restarts the Guest Product, health-checks it, rolls back when needed, and persists the operation. |
| C55 layer-effect receipt | C61 effect executor | Correlates C59's terminal operation into the Host updater's layer outcome. |

## Data and control path

```text
C26 archive + C61 configuration
          │ Host Updater verifies SHA-256, size, regular file, no symlink
          ▼
C61 effect executor (Host process)
          │ fixed C55 protocol only
          │ HTTP multipart over Host loopback
          ▼
C32 Host-local HTTP ↔ AF_VSOCK bridge
          ▼
C59 Guest Product Release Manager (Guest systemd service)
          │ stage → activate current → restart → health gate → rollback if needed
          ▼
C59 terminal operation ──► C61 C55 receipt ──► C28 execution report
```

The C32 bridge is direct to C59, rather than routed through Guest Runtime. A
successful Guest Product release can restart Guest Runtime, so a Guest Runtime
control proxy would terminate the update control path at exactly the wrong
time.

## Invariants

- C61 accepts only `http://127.0.0.1:<declared-port>` and the fixed C59 update
  path. It does not discover a Guest IP, public endpoint, or alternate port.
- The Host updater verifies the C26 archive, executable, and configuration
  artifact before execution. C61 verifies the archive digest again at its own
  filesystem boundary.
- C61 cannot provide a Host command line. The Host updater supplies the fixed
  C55 protocol and C61 supplies only desired release data.
- C59, not the Host, owns Guest staging directories, the active-release link,
  service restart, health decision, rollback, and durable release operation.
- A transport failure, invalid C59 response, or non-terminal C59 operation is
  written as a typed C55 unavailable outcome. It never becomes a guessed
  release success.
- An existing C55 path is idempotent only when the complete receipt bytes have
  the same domain meaning. Different existing evidence is not replaced.

## Current executable evidence

`guest-product-release-manager` has focused domain/application/HTTP tests and
the macOS provider test proves the separate C32 bridge lifecycle. The C61
effect executor has focused tests for C61 parsing, C55 receipt publication,
archive streaming, C59 outcome mapping, and Darwin/Linux/Windows compilation.
The Host Updater test suite verifies that it supplies only the fixed C55
protocol and re-verifies every C26 artifact immediately before execution.

## Release composition and remaining proof

The release process now has two adjacent, non-runtime tools:
`guest-product-release-archive-composer` turns one explicitly selected release
tree into the C59-safe tar+gzip artifact, and
`product-update-composer` selects that artifact plus the next updater and
layer effect executable, generates the Guest Runtime transition inside the
complete Product Update Specification, and passes a prepared payload to the
generic bootstrap-envelope signer. Neither tool reads `current`, activates a
Guest release, or becomes a Guest state owner.

Clean-host update and rollback proof remains a release-delivery responsibility
for each target OS. Container and Host Platform effects are separate owners;
they must not reuse the Guest Product Release Manager merely because their work
occurs near the Guest Product.
