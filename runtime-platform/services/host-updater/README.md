# Host Updater

`host-updater` is the next-updater component selected through the immutable C25 bootstrap envelope. The currently installed Host Agent validates only C25 and stages this artifact; it does not import or parse C26 `ProductUpdateSpecification`.

`host-updater --mode plan --invocation <C30 path>` reads a Host-staged C30 document and the referenced C26 file below its own staged directory. It verifies the C26 digest before pure `PlanStagedProductUpdateExecution` validates the explicit layer order and dependencies, then writes a `StagedProductUpdateExecutionPlan`.

`host-updater --mode execute --invocation <absolute C30 path> --report
<absolute C28 path> --layer-effect-receipt-directory <absolute Host-owned
directory> --layer-effect-timeout <duration>` is the production staged
execution path.
It verifies every C26 artifact and effect-executor byte immediately before a
fixed argument invocation. A release executor must write C55; a zero exit code,
log message, missing file, or malformed receipt is never promoted to success.

The release-owned C55 protocol has no caller-controlled executable arguments:

```text
--protocol-version v1
--effect-executor-id <C26 effect executor ID>
--effect-configuration-path <verified staged configuration artifact path>
--receipt-path <Host-owned path>
--update-id <C30 updateId>
--layer <C26 layer>
--operation <apply|rollback>
--artifact-path <verified staged artifact path>
--artifact-sha256 <C26 artifact digest>
```

On Windows, C28 output must use a drive-rooted Host-local path. UNC paths are
rejected because C56 does not permit network storage to own update evidence.

The workflow applies layers in C26/C25 order, stops on the first non-success
C55, invokes already-succeeded rollback artifacts in reverse order, and
persists the resulting C28 without replacing different pre-existing evidence.
It never sends C27. A successfully written C28 alone is not a settled Host
update, but it is the explicit recovery boundary: retrying `execute` is
rejected rather than replaying layer effects.

`host-updater --mode complete --invocation <absolute C30 path> --report
<absolute C28 path> --completion-descriptor <absolute C52 path>` is the
C27 settlement path for an already persisted C28. It validates
the existing C28 against C30/C26, then sends C27 only over the Host
Agent-published C52 Unix-domain socket or Windows named pipe. Completion never
re-applies a layer effect and cannot accept, derive, or substitute a TCP
completion endpoint.

The same C52 request contract is exercised against a real Unix-domain socket
on macOS/Linux and a real Windows named pipe on the matching native CI runner.
Cross-compiling a named-pipe client is not treated as native transport proof.

This module provides the verified effect-execution protocol, not a generic
artifact-replacement implementation. Each release still supplies explicit
Guest Runtime, container, and Host-platform executors; those executors own
their side effect and C55 outcome. The updater owns ordering, correlation,
rollback orchestration, and C28/C27 only.

## Package language

The directory names are part of the update bounded-context language, rather
than generic implementation labels:

- `stagedupdateinvocationfile` reads the Host-owned C30 invocation and its
  referenced C26 specification from the staged filesystem boundary.
- `stagedlayereffectprocess` re-verifies one C26 executor and artifact, invokes
  the fixed C55 protocol, and reads a strict typed receipt from Host-owned
  storage.
- `updateexecutionreportfile` owns strict, idempotent C28 publication/read.
- `hostlocalupdatecompletionpublisher` reads C52 and transports only C27 over
  the declared OS-local transport.
- `hostupdaterdomain` owns C26/C27/C28/C30 types, validation, and pure
  transition policy for the next-updater bounded context.
- `hostupdaterlayerexecutionapplication` orchestrates the C26 sequence through
  its effect-executor port and turns correlated C55 receipts into C28,
  including reverse rollback.
- `hostupdaterstagedupdatecompletionapplication` composes C27 after C28 is
  already explicit; it has no filesystem, transport, or layer-effect logic.

This vocabulary makes it possible to identify the state owner, contract, and
external boundary from an import path alone.

The stable handoff contract contains no `minimumUpdaterVersion`. Every release carries a signed next-updater artifact and opaque specification digest. A bootstrap verifier that cannot establish that evidence returns an explicit failed or unavailable receipt; it never attempts to parse or apply the specification as a fallback.
