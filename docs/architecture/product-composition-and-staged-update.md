# Product Composition and Staged Update

## Purpose

This document describes the update boundary in domain language. It answers
three questions that a maintainer must be able to answer from the names alone:

1. Who creates a release bundle?
2. Who may decide that the bundle is trustworthy and ready to hand off?
3. Who may interpret and execute the evolving update plan?

The answer is intentionally split. A release tool composes a bundle, the Host
Agent admits and stages an immutable bootstrap boundary, and the separately
selected next updater interprets the evolving layer specification. No layer
uses a missing file, log line, or old command result as a substitute for owned
state.

## Ubiquitous language and owners

| Term | Owner | Meaning |
| --- | --- | --- |
| `ReleaseBundleComposition` | Release process | Explicit input naming the target, layers, payload artifacts, signing key, and issue time. It contains no caller-supplied digests. |
| Signed release bundle | `release-composer` | A new immutable directory containing `payload/`, C25, and an inventory manifest. |
| C25 `UpdateBootstrapEnvelope` | Release process; verified by Host | Small signed compatibility boundary. It names the selected next updater and opaque update specification. |
| C26 `ProductUpdateSpecification` | Staged next updater | Evolving detailed layer plan. The currently installed Host Agent must not parse it. |
| C29 `HostUpdateJournal` | Host Agent | Durable admission, handoff, recovery, and final settlement state. |
| C30 `StagedUpdateInvocation` | Host bootstrapper; read by next updater | Host가 C29 `handoff-pending` journal revision을 durable commit한 뒤 발행하는 next-updater input. `requestId`와 `expectedHandoffJournalRevision`은 C27 completion이 제시해야 할 정확한 Host journal version이며, Host가 원자적으로 `applying` 전이와 C28 정산을 수행한다. Its `payload/` paths are relative to the staged directory. |
| C31 `StagedUpdateHandoff` | Host bootstrapper; consumed by deployment supervisor | Queue item that names the C30 path relative to Host staging. It is not a copy of C30. |

## Composition and handoff flow

```text
ReleaseBundleComposition
        │ release-composer calculates digests and signs C25
        ▼
Signed release bundle (payload/, C25, inventory)
        │ Host Agent validates C25 and its two known artifacts
        ▼
HostUpdateJournal (C29) ──atomic copy──► staged update directory
                                             ├── payload/
                                             └── bootstrap-envelope.json (C25)
        │ durable `handoff-pending` commit fixes journal revision
        ▼
invocation.json (C30) ──atomic create──► staged update directory
        │ durable queue publication
        ▼
handoff-queue/<updateId>.json (C31)
        │ deployment supervisor resolves C31 under Host staging
        ▼
host-updater reads C30, verifies and parses C26, produces UpdateExecutionPlan
```

The queue must not contain a copied C30. C30's `specificationRelativePath`
is intentionally relative to the staged directory. Moving that document into
the queue would silently change the path base and make an otherwise valid C26
unreadable. C31 makes that indirection explicit and durable.

## Invariants

- `release-composer` derives artifact SHA-256 and size from payload bytes and
  refuses to replace an existing bundle output.
- `StagedBundleBootstrapper` accepts only an explicit Host-owned bundle store,
  staging directory, and Ed25519 trust store. Partial configuration is a
  startup error.
- The Host verifies only C25 and the C25-named next-updater/C26 artifacts. It
  does not decode C26.
- A staged directory is published by rename only after its complete payload and
  C25 have been synced. C30 is not created at this point because its
  `expectedHandoffJournalRevision` does not exist until C29 is durably
  `handoff-pending`.
- The Host atomically creates C30 only after that durable C29 transition. It
  records the original `requestId` and the exact
  `expectedHandoffJournalRevision`; a
  retry must byte-match the existing C30 rather than changing the completion
  correlation.
- C31 is atomically created or must byte-match the already durable handoff;
  recovery may request the handoff again but cannot create a second meaning.
- The next updater resolves C30's C26 path below the staged directory, rejects
  traversal, symlinks, missing files, size overflow, and digest mismatch, then
  passes complete explicit input to pure `PlanStagedUpdate` policy. For every
  layer it re-verifies the C26 artifact and C26-declared effect executable,
  invokes the release-owned fixed C55 protocol without a shell or
  caller-selected arguments, and accepts only a correlated C55 receipt. The
  application workflow aggregates those receipts into one atomic C28 report.

## Current scope and next responsibility

The implementation proves signed composition, Host staging, durable C31
publication, restart re-handoff, next-updater planning, digest-verified C55
layer-effect invocation, atomic C28 publication, and C52-local C27 completion
submission by a separate `host-updater` process. For the Guest Runtime layer,
the release-owned C61 executor is concrete: it sends a re-verified Guest
Product archive through the direct C32 Host-local bridge to C59 and maps its
terminal operation to C55. The concrete release process now uses
`guest-product-release-update-composer` to select immutable C61/C26 inputs:
the next updater, apply archive, C55 executable, and optionally the reverse
rollback archive. It writes a prepared payload and generic signer input, then
`release-composer` owns C25 signing. The composer currently rejects non-macOS
arm64 targets because C61 depends on the concrete macOS C32 AF_VSOCK bridge;
the shared C25–C31 contract does not imply a nonexistent platform effect. The
packaged
`host-update-handoff-supervisor` also consumes C31 and launches only the
C25-selected updater, publishing C57 rather than inferring update success from
process exit. It does not claim that a concrete release package was activated,
that a release-composition owner selected the target Guest archive and C61
configuration for an actual signed bundle, that any Container/Host replacement
occurred, or that a matching OS package manager performed rollback. Those remain separate
product-composition responsibilities:

- **Release-owned layer effect executors** apply or compensate container and
  Host-platform changes selected by the pure
  `UpdateExecutionPlan`. Each must implement the fixed C55 protocol and write
  only its own correlated receipt.
- **Guest Product release composition** selects immutable target bytes and
  generates the C61 apply/rollback transition for each signed C25/C26 bundle.
  C59 owns Guest activation and rollback; C61 does not become a second Guest
  release-state owner.
- **Next updater execution workflow** validates C55 against C30/C26 and
  creates one C28 layer/rollback report. `execute` creates C28 only;
  `complete` reads that immutable report and submits C27 through C52 without
  rerunning a layer effect. Host Agent atomically verifies that handoff
  revision, enters `applying`, and settles C29 only from that command.
- **Release delivery proof** attaches C24 clean-host install, update, rollback,
  and uninstall evidence for each target platform.

The executable proof is `make -C runtime-platform release-composer-test` plus
`make -C runtime-platform installation-update-acceptance`.
