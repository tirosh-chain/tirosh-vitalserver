# Guest Product release effect executor

This executable realizes the Guest Runtime layer's release-owned C55 effect.
It is invoked only by `host-updater` with its fixed protocol:

```text
--protocol-version v1
--effect-executor-id <C26 executor id>
--effect-configuration-path <verified C61 path>
--receipt-path <Host-owned C55 path>
--update-id <C30 update id>
--layer guest-runtime
--operation apply|rollback
--artifact-path <verified release archive>
--artifact-sha256 <C26 artifact digest>
```

The executable does not discover endpoints, release directories, or previous
release state. C61 explicitly supplies the C32 Host-loopback bridge and the
C59 expected/target release transition. C59 remains the owner of release
staging, activation, rollback, and durable operation state; this executable
only maps that explicit operation to one C55 receipt.

The Host updater verifies the executable, C61 file, and archive before
invocation. The executor verifies the archive again at its own boundary and
writes C55 without replacing different existing evidence. Missing or invalid
inputs and transport failures are reported as typed terminal receipts whenever
the fixed C55 invocation and receipt path are valid; an unwritable receipt is
an invocation failure, never an update success.
