# Host Updater

`host-updater` is the next-updater component selected through the immutable C25 bootstrap envelope. The currently installed Host Agent validates only C25 and stages this artifact; it does not import or parse C26 `ProductUpdateSpecification`.

`host-updater --mode plan --invocation <C30 path>` reads a Host-staged C30 document and the referenced C26 file below its own staged directory. It verifies the C26 digest before pure `PlanStagedProductUpdateExecution` validates the explicit layer order and dependencies, then writes a `StagedProductUpdateExecutionPlan`.

`host-updater --mode complete --invocation <C30 path> --report <C28 path>
--completion-endpoint <Host-local origin>` is the separate settlement workflow.
It reads a regular, bounded C28 evidence document created by a selected layer
effect executor, validates every report correlation and artifact digest against
C30/C26, constructs C27 `StagedProductUpdateCompletionCommand` with C30's
`expectedHandoffJournalRevision`, and sends it to the explicit Host-local
endpoint. It does not infer evidence from command output, logs, or missing
artifacts; without a C28 report it cannot settle an update.

The executable still deliberately performs no artifact replacement itself.
Container, Guest Runtime, and Host platform effects remain explicit selected
adapter responsibilities; their future executor must create C28 before this
settlement workflow can run.

## Package language

The directory names are part of the update bounded-context language, rather
than generic implementation labels:

- `stagedupdateinvocationfile` reads the Host-owned C30 invocation and its
  referenced C26 specification from the staged filesystem boundary.
- `updateexecutionreportfile` reads the selected layer executor's explicit C28
  evidence document.
- `hostlocalupdatecompletionpublisher` transports only the C27 completion
  command to the explicitly configured Host-local endpoint.
- `hostupdaterdomain` owns C26/C27/C28/C30 types, validation, and pure
  transition policy for the next-updater bounded context.
- `hostupdaterstagedupdatecompletionapplication` orchestrates those three
  contracts. Its `PublishStagedProductUpdateCompletion` workflow has no
  filesystem, HTTP, or update-layer effect implementation of its own.

This vocabulary makes it possible to identify the state owner, contract, and
external boundary from an import path alone.

The stable handoff contract contains no `minimumUpdaterVersion`. Every release carries a signed next-updater artifact and opaque specification digest. A bootstrap verifier that cannot establish that evidence returns an explicit failed or unavailable receipt; it never attempts to parse or apply the specification as a fallback.
