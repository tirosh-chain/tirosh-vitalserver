# Lab, artifact export, and deletion lifecycle

> 상태: **Lab lifecycle·cold-path→`.vital` formation 구현됨 / C37·C46·C51 indexed-library selection 구현됨 / external HTTP indexed-library acceptance 구현됨 / bundled VitalServer image acceptance 진행 중**
>
> 범위: Guest Runtime 안의 Lab aggregate, Archive Export workflow, explicit hide/detach/delete semantics. 이 문서는 `stop`·`.vital` finalization·upload/indexing·delete를 서로 성공으로 추정하지 않도록 고정한다. 실제 Recorder Gateway raw capture는 [Recorder Gateway Cold-Path Capture Boundary](recorder-gateway-cold-path-capture-boundary.md)가 소유한다.

## 1. 결정: terminal stop은 export 성공이 아니며, export intent는 durable하다

Lab session 또는 virtual recorder의 `stop`은 execution을 종료하고 Lab aggregate의 terminal state를 저장하는 명령이다. 그것만으로 source file 존재, artifact finalization, upstream upload, indexing 완료를 주장하지 않는다.

Runner scenario가 `archiveOnTerminalStop=true`를 명시했다면, Guest Runtime은 Runner start receipt에서 이를 `terminalArchivePolicy=export-on-stop`으로 보존한다. Stop 때 C45 finalization receipt가 durable해지면 Lab은 exact source revision·finalization receipt·stable request ID와 **그 stop을 소유한 Lab Operation reference**를 갖는 `terminalArchiveIntent=pending`을 함께 기록한다. 이후 coordinator가 Archive Export를 요청하며, `submitted`는 **Archive operation이 admitted됨**만 뜻한다. `succeeded` upload/indexing 여부는 Archive-owned `Operation`과 `ExportReceipt`에서만 읽는다.

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
    L->>G: Runner finalizes exact cold-path capture
    G-->>L: finalized packet-sequence receipt
    L->>L: persist stopped recorder + terminalArchiveIntent=pending
    L-->>C: Lab Operation succeeded; session=stopped
    L->>A: terminal archive dispatch (stable request ID, exact source revision)
    A->>L: explicit stopped-recorder eligibility read
    A->>G: read finalized packet sequence and verify digest
    A->>F: form parser-verified .vital bytes
    F-->>A: finalized source evidence
    A->>A: write immutable artifact + ArtifactManifest
    A->>P: upload artifact
    P-->>A: upload result
    A->>P: verify indexing
    P-->>A: indexing result
    A-->>L: Archive Operation reference (or typed dispatch issue)
    A-->>C: ExportReceipt + terminal export Operation
```

The control surface displays the Lab operation, `terminalArchiveIntent`, and Archive Export receipt separately. If export fails or dispatch is unavailable, the session stays `stopped`; its intent remains `rejected` or `unavailable` with typed issue evidence and is eligible for a retry of the same stop command. It is never rewritten to `running`, `failed`, or a guessed upload success.

Guest Runtime process start also scans only persisted, dispatchable terminal
intents and repeats the exact Archive request ID. It does not re-create a
capture, choose a source revision, or derive a stop operation from a log. The
intent's originating Lab operation is re-read before the dispatch observation
is written, so a restart can reconcile a durable `pending`/`unavailable`/
`rejected` intent without treating either the Lab stop or the later upload as
success. A reconciliation read/write failure remains visible as the unchanged
intent plus process diagnostic; it is not converted into an empty queue.

## 2. State owners

| Fact | Owner | Durable state | It must not mean |
| --- | --- | --- | --- |
| Lab scenario execution and members | Guest Runtime Lab module | `LabSession`, `LabBed`, `VirtualRecorder`, lifecycle `Operation` | artifact finalized or uploaded |
| Terminal archive dispatch intent | Guest Runtime Lab module | `VirtualRecorder.terminalArchiveIntent` | Archive upload/index success |
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
| stop session / recorder | resource is running | Runner finalization receipt is persisted first; `archiveOnTerminalStop` creates a durable pending intent, never an upload claim |
| hide / unhide resource | valid current revision | only visibility changes |
| detach recorder | session stopped, recorder assigned | recorder has no bed reference and the referenced bed becomes detached |
| delete resource | explicit target and cascade policy | a `DeletionReceipt` lists deleted and intentionally retained resources |

Commands use expected resource revisions and request-id idempotency. A known precondition failure returns `CommandRejection`; a durable-write ambiguity returns `CommandAdmissionFailure`. Neither produces an empty collection or an invented deletion result.

### Operator-requested export

`terminalArchivePolicy=no-export`인 stopped virtual recorder는 operator가 별도
`ArtifactExportCommand`를 요청할 수 있다. 이 명령은 현재 Lab recorder read가
공개한 positive resource revision 및
`recorderGatewayFinalizationReceiptId`, 그리고 Archive Export owner가
`GET /v1/runtime/archive/export-provider`에서 공개한 provider reference만 받는다.
Console과 `platformctl`은 이 exact facts를 전달하는 named surface를 제공한다.
어느 인터페이스도 recorder/session 이름, Gateway URL, cold-path file path,
provider endpoint 또는 credential에서 source/provider를 만들어 내지 않는다.

`terminalArchivePolicy=export-on-stop`인 recorder에는 이미 Terminal Archive
Intent가 있으므로 동일한 manual command를 허용하지 않는다. 운영자는 Lab
operation, intent, 그리고 Archive operation/receipt를 각각 읽어야 하며, stop
성공을 export 성공으로 표시해서는 안 된다.

### Delete policy

`hide` only changes UI visibility. `detach` only changes the explicit assignment relationship. They are never aliases for delete.

`delete` requires a declared cascade policy. A running session is rejected. Deleting a session requires `cascade=owned-resources` and deletes its remaining beds and recorders atomically after the session is stopped. Deleting a recorder requires that it has first been detached if its bed must remain; deleting an assigned bed is rejected until the recorder is detached. Durable Lab operations remain as audit records, while Archive manifests/receipts are explicitly retained by archive retention policy and listed in the deletion receipt. This prevents both stale Lab read models and invisible archive data loss.

## 4. Artifact Export workflow

The real Artifact Formation adapter produces a `.vital` media object only after Lab has explicitly reported the selected recorder as stopped **and** Recorder Gateway has supplied a finalized cold-path packet-sequence receipt. The public manifest carries its digest, size, storage reference, and finalization evidence—not raw waveform data.

Archive Export rejects a stopped recorder that lacks an explicitly named C45 finalization receipt. It fetches the receipt and the immutable packet-sequence bytes from the Gateway's Guest-loopback control contract, verifies their digest relationship, checks that the receipt belongs to the recorder's explicit `recorderGatewayRecorderId`, and then forms gzip-compressed legacy VITA v3 bytes. A malformed capture, mismatched digest, unknown receipt, or recorder mismatch remains a typed command rejection; it cannot produce a placeholder file.

`archive-export-outcome-profile` is a deterministic development/test adapter. It is not a VitalServer upload client, so a deployment that explicitly selects it proves **source finalization and binary artifact formation**, not that a remote VitalServer parsed or indexed the output. It cannot silently stand in for an indexed-library provider.

`VitalServerIndexedLibraryHTTPArchiveExportProvider` now implements the concrete
VitalServer indexed-library wire boundary. It streams one immutable
`artifactId.vital` as multipart field `vitalfile` to `/upload`; HTTP success is
accepted only when the body is exactly `success`. It then independently logs
in with adapter-only secret material and reads gzip-compressed `/api/filelist`
to prove that the exact filename appears in the owner index. It neither treats
an accepted upload as indexing nor turns a transport interruption into a failed
receipt. HTTP rejection is a known failed step, while connection/body-read
failure returns an unknown outcome to Archive Export and leaves its durable
operation running. The adapter disables ambient `HTTP_PROXY` routing: C46's
complete upstream origin is the only selected network target.

The adapter is intentionally not selected from a topology guess or a default
endpoint. For an external target, C37 selects
`kind=vitalserver-indexed-library` and names only a private credential-material
path. C46 supplies the matching archive provider, endpoint, timeout, and C51
credential reference; it carries no credential bytes. The Supervisor rejects a
C37/C46 provider mismatch before Guest Runtime starts. C51 is deliberately
different: Guest Runtime starts with an explicit `missing` C51 projection so an
OS-local operator can provision it through C52. A later archive effect rejects
missing, symlinked, group/world-readable, invalid, or reference-mismatched C51
material before it constructs the HTTP adapter, and writes an explicit failed
receipt rather than claiming upload/index success.

`ArtifactExportCommand` returns an operation. The Archive owner persists an `ExportReceipt` for every terminal attempt:

- `succeeded` requires finalization, upload, and indexing to have separate successful evidence.
- upload failure records `upload=failed`, `indexing=not-requested`, and a failed operation. The Lab session remains stopped.
- indexing failure records `upload=succeeded`, `indexing=failed`, and a failed operation. It does not retroactively claim upload failed or index success.
- source eligibility, capability, storage, provider, and decode failure remain typed failures/unsupported outcomes; none become an empty vital-file list.

The generic Lab archive-provider port remains versioned and provider-neutral.
Black-box acceptance now proves terminal Lab stop through C45 source
finalization, `.vital` formation, explicit C46 endpoint selection, private C51
material, multipart upload, and independent index evidence against a
non-loopback external-library fixture. It is not a bundled-image or hospital
VitalServer parser acceptance claim; those two deployment paths retain their
own image and production-upstream release gates.

## 5. Contracts and API

| Contract | Owner | Purpose |
| --- | --- | --- |
| C14 `LabSession`, `LabBed`, `VirtualRecorder` | Guest Runtime Lab module | explicit resource/visibility/assignment/lifecycle state |
| C15 Lab commands and `DeletionReceipt` | Guest Runtime Lab module | revisioned start/stop/hide/detach/delete and deletion evidence |
| C5 `IngressReceipt` and C13 `DeliveryReceipt` | Recorder Gateway | ingress durability and VitalServer delivery replay; neither is cold-path finalization |
| C45 `RecorderColdPathCaptureFinalizationCommand`, `RecorderColdPathCaptureFinalizationReceipt` | Recorder Gateway | named raw packet capture source and finalization evidence, not `.vital` formation |
| C6 `ArtifactExportCommand`, `ArchiveExportProviderConfiguration`, `ArtifactManifest`, `ExportReceipt` | Archive Export module | provider reference read와 valid artifact formation, upload, index result separation |
| C2 `Operation` | command owner | durable command lifecycle, never inferred from UI state |

Guest Runtime exposes these as `/v1/runtime/lab/*` and `/v1/runtime/archive/*`; Host Agent only allowlists and forwards the bytes. `GET /v1/runtime/archive/export-provider` is a configuration fact, and `POST /v1/runtime/archive/exports` is an admission request; neither endpoint makes an upload/index success claim. The Host does not combine Lab state with Archive receipt state.

## 6. Acceptance evidence

This boundary is complete only when black-box acceptance proves all of the following:

1. A terminal session stop persists exact Runner/C45 finalization evidence and, when selected by the Runner scenario, a durable pending archive intent; neither implies artifact success.
2. A Recorder Gateway finalization receipt names a digest-verified packet sequence without claiming a `.vital` artifact.
3. Automatic terminal dispatch and a later explicit export both write a schema-valid immutable manifest and a separate schema-valid succeeded receipt only after parser-verified artifact formation plus explicit upload and index acknowledgements. The external indexed-library case proves C37/C46/C51 selection and separate upload/index receipt identities without profile fallback.
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
`stop → durable terminal intent → automatic Archive dispatch`, explicit export, upload/index known failure, provider outcome unknown,
hide/detach/delete guard, retained Archive resource를 모두 SQLite 내부 접근 없이
검증한다.
