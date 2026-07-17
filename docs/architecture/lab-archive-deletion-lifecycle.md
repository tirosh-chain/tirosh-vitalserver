# Lab, artifact export, and deletion lifecycle

> 상태: **Lab lifecycle·simulated Archive acceptance 완료 / real recorder cold-path handoff 구현 중**
>
> 범위: Guest Runtime 안의 Lab aggregate, Archive Export workflow, explicit hide/detach/delete semantics. 이 문서는 `stop`·`.vital` finalization·upload/indexing·delete를 서로 성공으로 추정하지 않도록 고정한다. 실제 Recorder Gateway raw capture는 [Recorder Gateway Cold-Path Capture Boundary](recorder-gateway-cold-path-capture-boundary.md)가 소유한다.

## 1. 결정: stop은 export 성공이 아니다

Lab session의 `stop`은 virtual recorder execution을 종료하고 Lab aggregate의 terminal state를 저장하는 명령이다. 그것만으로 source file 존재, artifact finalization, upstream upload, indexing 완료를 주장하지 않는다.

`.vital` 파일을 만들고 library에 반영하려면 별도의 `ArtifactExportCommand`가 필요하다. 이 command는 다음을 하나의 Archive Export operation 안에서 실행한다.

```mermaid
sequenceDiagram
    participant C as Client / UI workflow
    participant L as Lab owner
    participant G as Recorder Gateway cold-path owner
    participant A as Archive Export owner
    participant F as Vital artifact formatter
    participant P as Archive provider

    C->>L: stop(session, expectedRevision)
    L-->>C: Operation succeeded; session=stopped
    C->>G: finalize(cold-path capture, expectedRevision)
    G-->>C: finalized packet-sequence receipt
    C->>A: export(virtual-recorder, expectedRevision, finalized source reference)
    A->>L: explicit stopped-recorder eligibility read
    A->>G: read finalized packet sequence and verify digest
    A->>F: form parser-verified .vital bytes
    F-->>A: finalized source evidence
    A->>A: write immutable artifact + ArtifactManifest
    A->>P: upload artifact
    P-->>A: upload result
    A->>P: verify indexing
    P-->>A: indexing result
    A-->>C: ExportReceipt + terminal export Operation
```

An operator-facing “Stop and export” action may orchestrate those two public commands in order, but it must display the Lab operation and the Archive Export receipt separately. If export fails, the session stays `stopped`; it is not rewritten to `running`, `failed`, or a guessed upload success.

## 2. State owners

| Fact | Owner | Durable state | It must not mean |
| --- | --- | --- | --- |
| Lab scenario execution and members | Guest Runtime Lab module | `LabSession`, `LabBed`, `VirtualRecorder`, lifecycle `Operation` | artifact finalized or uploaded |
| UI visibility | Lab module | resource `visibility` | delete or detach |
| Recorder-to-bed association | Lab module | recorder `bedReference` / bed assignment state | current Socket.IO connection |
| Recorder raw packet capture and finalization | Recorder Gateway | `RecorderColdPathCapture`, packet sequence, finalization receipt | `.vital` artifact exists or was uploaded |
| Finalized `.vital` bytes and immutable artifact identity | Archive Export module | storage object + `ArtifactManifest` | upstream indexed it |
| Upload and indexing outcome | Archive Export module | immutable `ExportReceipt` | Lab session lifecycle state |
| Deletion of Lab-owned resource graph | Lab module | `DeletionReceipt` + retained audit operation | archive retention deletion |

The Lab module and Archive Export module can share the Guest Runtime process and SQLite infrastructure in this phase, but they use separate repositories/tables and cross the boundary through explicit application ports. Neither module reads the other's table or file layout.

## 3. Resource model and commands

### Lab aggregate

`LabSession` is an aggregate root with `prepared`, `running`, `stopped`, or `failed` state. Creating a session creates explicit `LabBed` and `VirtualRecorder` resources. A virtual recorder has `ready`, `running`, `stopped`, or `failed` execution state; a bed has `assigned` or `detached` assignment state. Both have independent `visible` / `hidden` UI visibility.

The command surface is intentionally small:

| Command | Preconditions | Result |
| --- | --- | --- |
| create session | valid scenario/count | prepared session, beds, and recorders atomically persisted |
| start session | session is prepared or stopped | session and all owned recorders transition to running |
| stop session | session is running | session and all owned recorders transition to stopped; no archive claim |
| hide / unhide resource | valid current revision | only visibility changes |
| detach recorder | session stopped, recorder assigned | recorder has no bed reference and the referenced bed becomes detached |
| delete resource | explicit target and cascade policy | a `DeletionReceipt` lists deleted and intentionally retained resources |

Commands use expected resource revisions and request-id idempotency. A known precondition failure returns `CommandRejection`; a durable-write ambiguity returns `CommandAdmissionFailure`. Neither produces an empty collection or an invented deletion result.

### Delete policy

`hide` only changes UI visibility. `detach` only changes the explicit assignment relationship. They are never aliases for delete.

`delete` requires a declared cascade policy. A running session is rejected. Deleting a session requires `cascade=owned-resources` and deletes its remaining beds and recorders atomically after the session is stopped. Deleting a recorder requires that it has first been detached if its bed must remain; deleting an assigned bed is rejected until the recorder is detached. Durable Lab operations remain as audit records, while Archive manifests/receipts are explicitly retained by archive retention policy and listed in the deletion receipt. This prevents both stale Lab read models and invisible archive data loss.

## 4. Artifact Export workflow

The real Artifact Formation adapter produces a `.vital` media object only after Lab has explicitly reported the selected recorder as stopped **and** Recorder Gateway has supplied a finalized cold-path packet-sequence receipt. The public manifest carries its digest, size, storage reference, and finalization evidence—not raw waveform data.

The current `lab-simulation-archive` profile is acceptance-fixture behavior: it creates a deterministic `vital-lab-source-v1` envelope, not parser-verified `.vital` bytes. It therefore proves Lab/Archive lifecycle separation only. It must not be used as evidence that a Lab-generated recorder uploaded a clinically readable Vital file.

`ArtifactExportCommand` returns an operation. The Archive owner persists an `ExportReceipt` for every terminal attempt:

- `succeeded` requires finalization, upload, and indexing to have separate successful evidence.
- upload failure records `upload=failed`, `indexing=not-requested`, and a failed operation. The Lab session remains stopped.
- indexing failure records `upload=succeeded`, `indexing=failed`, and a failed operation. It does not retroactively claim upload failed or index success.
- source eligibility, capability, storage, provider, and decode failure remain typed failures/unsupported outcomes; none become an empty vital-file list.

The generic Lab archive-provider adapter is a versioned binary upload/index port. It is not a claim that the legacy VitalServer multipart endpoint has been certified; actual bundled image/proxy proof remains a cross-platform delivery gate, and the external provider has its own explicit integration boundary.

## 5. Contracts and API

| Contract | Owner | Purpose |
| --- | --- | --- |
| C14 `LabSession`, `LabBed`, `VirtualRecorder` | Guest Runtime Lab module | explicit resource/visibility/assignment/lifecycle state |
| C15 Lab commands and `DeletionReceipt` | Guest Runtime Lab module | revisioned start/stop/hide/detach/delete and deletion evidence |
| C5 `IngressReceipt` and C13 `DeliveryReceipt` | Recorder Gateway | ingress durability and VitalServer delivery replay; neither is cold-path finalization |
| C45 `RecorderColdPathCaptureFinalizationCommand`, `RecorderColdPathCaptureFinalizationReceipt` | Recorder Gateway | named raw packet capture source and finalization evidence, not `.vital` formation |
| C6 `ArtifactExportCommand`, `ArtifactManifest`, `ExportReceipt` | Archive Export module | valid artifact formation, upload, index result separation |
| C2 `Operation` | command owner | durable command lifecycle, never inferred from UI state |

Guest Runtime exposes these as `/v1/runtime/lab/*` and `/v1/runtime/archive/*`; Host Agent only allowlists and forwards the bytes. The Host does not combine Lab state with Archive receipt state.

## 6. Acceptance evidence

This boundary is complete only when black-box acceptance proves all of the following:

1. A session stop returns `stopped` before any capture finalization or export request, and no artifact success is implied.
2. A Recorder Gateway finalization receipt names a digest-verified packet sequence without claiming a `.vital` artifact.
3. A later export writes a schema-valid immutable manifest and a separate schema-valid succeeded receipt only after parser-verified artifact formation plus explicit upload and index acknowledgements.
4. Upload or index failure persists a failed receipt and leaves the stopped Lab session unchanged.
5. `hide`, `detach`, and `delete` have distinct observable effects.
6. Delete rejection on active/dependent resources creates no partial deletion.
7. Explicit session cascade removes every Lab session/bed/recorder read-model resource, while any retained archive manifests are named in `DeletionReceipt` rather than becoming an orphan.

검증 명령은 다음과 같다.

```sh
make -C runtime-platform check
```

이 명령은 real Guest Runtime application composition을 명시적
`guest-runtime-control-http-acceptance-fixture` TCP/HTTP entry point로 실행하는
public-contract acceptance를 수행한다. fixture는 Guest application/SQLite/HTTP
boundary만 증명하며 production Linux Guest의 AF_VSOCK transport를 대체하지 않는다.
`stop → explicit export`, upload/index known failure, provider outcome unknown,
hide/detach/delete guard, retained Archive resource를 모두 SQLite 내부 접근 없이
검증한다.
