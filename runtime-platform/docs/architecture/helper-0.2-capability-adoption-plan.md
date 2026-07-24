# Helper 0.2 capability adoption plan

## 1. 목적

이 문서는 현재 Helper 0.2에서 제품 환경으로 검증한 Recorder
observability, `.vital` 파일 추적, replay failure, 설치 및 패키지 proof를
Runtime Platform vNext에 반영하는 구현 순서와 완료 조건을 정의한다.

Helper source, database, API response를 vNext runtime dependency로 가져오지
않는다. Helper는 behavior oracle과 negative evidence의 출처다. vNext는 해당
행동을 owner별 contract, repository와 acceptance로 다시 구현한다.

첫 구현 목표는 다음 vertical slice다.

```text
Vital Recorder
  -> Recorder Gateway admission
  -> Guest Runtime Recorder Observation Catalog
  -> PostgreSQL evidence/current projection
  -> bounded public read
  -> Runtime Console Recorder Detail
```

그 다음 `.vital` artifact lineage와 replay failure를 같은 owner 규칙으로
연결한다. macOS delivery proof는 product capability 구현과 별도 release
gate로 유지한다.

### 1-1. 2026-07-24 실행 baseline과 남은 목표

현재 완료된 foundation은 다음과 같다.

- Alembic `0001`~`0006_backup_owner` source contract와 PostgreSQL migration integration
  harness
- SQLite Catalog 제거와 PostgreSQL 단일 repository composition
- Gateway 인증을 거치는 internal observation admission
- accepted/duplicate/quarantined request receipt, immutable observation과 Recorder current
  projection의 원자적 commit
- revisioned expectation event/current expectation/Recorder summary의 원자적
  commit과 idempotent receipt
- authenticated source identity, media type와 실제 request byte count의
  admission evidence
- explicit max-report-age freshness policy와 Catalog-clock `current/stale`
  projection
- Recorder별 keyset-paginated timeline과 Recorder-reported typed incident read
- public observation/current summary read

남은 구현은 아래 gate 순서로 진행한다. 앞 gate의 owner contract와
acceptance가 통과하기 전에 뒤 UI나 package proof로 상태를 보완하지 않는다.

| Gate | 상태 | 목표 | 완료 evidence |
| --- | --- | --- | --- |
| C1 | 완료 | Recorder Catalog 완결 | accepted/duplicate/quarantined 및 expectation transaction, explicit freshness projection, bounded timeline/incident read |
| C2 | 완료 | Archive lineage repository | artifact/attribution atomic commit, independent upload/index receipts, bounded artifact read |
| C3 | 설치 증명 대기 | Recorder direct upload와 Guest bootstrap | Gateway durable spool, authenticated Guest streaming admission, restart dispatch recovery, C77/C78 owner evidence와 C24 `installed-guest-runtime` attachment 완료; 실제 ARM64 clean-Guest first boot/reboot proof 대기 |
| C4 | 승인 corpus 실행 대기 | attribution과 replay | assignment-owner PostgreSQL integration, Lab source streaming admission, pure replay transition, bounded parser/spool, transition outbox, command/read API, durable Runner effect worker, deterministic v1~v3 wire corpus, future-time typed admission rejection, public no-graph/unknown/string track failure와 PostgreSQL-backed Guest Runtime→Runner→Gateway→VitalServer success/terminal upstream failure path를 지원 Node 20.19.3에서 완료; C79 human approval/digest verifier와 v1~v3 required release acceptance target 완료, 실제 승인 bytes 실행 대기 |
| C5 | portable 완료 | Recorder Console | bounded Catalog Recorder page, lazy Detail, selection/unmount cancellation IPC, 사용자 중심 observation/incident/Vital file cards, 접힌 technical owner response, stylesheet packaging regression test, C75 replay 생성/조회와 owner operation·receipt·typed failure 표시; 2026-07-24 지원 Node 20.19.3 전체 control/web/desktop suite 30/30 통과, installed Console proof 대기 |
| C6 | 증명 대기 | backup/restore/delivery | C76 contract/state machine, durable ledger, SQLite/PostgreSQL adapters, runtime worker/API, C37와 Host facade 완료; control HTTP admission/read를 통한 실제 SQLite+seeded PostgreSQL 16 combined empty-target restore, public Recorder/lineage owner API parity와 second-restore 거부 통과, installed Host facade 및 macOS clean-host C24 대기 |

release-ready는 C1~C6가 모두 통과한 상태다. 단순 package 생성 성공이나
부분 unit test 성공은 release-ready로 부르지 않는다.

## 2. 현재 구현과 목표의 차이

초기 설계 시점의 vNext에는 다음 기반만 있었다.

- Recorder-owned `RecorderObservationEnvelope`
- Guest-owned immutable `CatalogObservation`과 ingest operation
- Guest SQLite의 `catalog_observations`
- 단건 및 전체 observation read
- Recorder Gateway ingress/delivery receipt
- Recorder Gateway cold-path capture finalization
- Lab stop과 분리된 Archive Export operation
- hide, detach와 delete가 분리된 Lab resource lifecycle
- C23/C24 delivery plan과 proof, immutable Guest artifact composition

위 SQLite foundation은 현재 PostgreSQL owner로 교체되었다. 다음 제품 동작은
여전히 C1~C6에서 완결해야 한다.

- Recorder가 직접 업로드한 `.vital` 파일의 lineage
- upload와 upstream indexing receipt의 분리
- PostgreSQL schema migration, backup, restore proof
- Helper 0.2 수준의 Recorder Detail과 파일 이력
- Developer ID macOS package의 clean-host lifecycle proof

SQLite Catalog와 startup DDL은 이미 삭제되었다. vNext는 아직 release되지
않았고 legacy install migration도 첫 release 범위가 아니므로 dual-write나
SQLite-to-PostgreSQL compatibility branch를 다시 만들지 않는다.

## 3. 상태 owner와 저장소

| 사실 | owner | 저장소 | public consumer |
| --- | --- | --- | --- |
| Recorder self-observation | Vital Recorder | Recorder가 발생시키고 Catalog가 원문 보존 | Catalog, Runtime Console |
| socket/packet admission | Recorder Gateway | Gateway durability store | Catalog, support tooling |
| observation evidence/current/history | Guest Runtime Recorder Observation Catalog module | Guest PostgreSQL `recorder_catalog` | Host facade를 통한 Runtime API |
| observability expectation | Guest Runtime Recorder Observation Catalog module | Guest PostgreSQL `recorder_catalog` | Runtime Console, deployment/support command |
| `.vital` source/finalization/upload/indexing | Guest Runtime Archive Export module | Guest PostgreSQL `archive_export`와 declared artifact store | Runtime Console |
| upstream indexing result | selected Upstream Provider | provider receipt를 Archive Export가 보존 | Archive Export read API |
| Runtime/Lab operation ledger | Guest Runtime | Guest SQLite | Runtime API |
| Gateway spool/replay | Recorder Gateway | Gateway-owned durability store | Gateway API/receipt only |

PostgreSQL은 Guest product deployment의 한 instance를 사용할 수 있지만 schema,
role, migration과 repository는 owner별로 분리한다. 한 owner가 다른 owner
schema를 직접 query하지 않는다. 필요한 연결은 application port와 typed
contract로 수행한다.

```text
recorder_catalog schema
  writer role: recorder_catalog_writer
  reader role: recorder_catalog_reader

archive_export schema
  writer role: archive_export_writer
  reader role: archive_export_reader
```

Guest Runtime executable 안의 Catalog와 Archive Export module은 각각 자기
repository port를 가진다. PostgreSQL을 도입하기 위해 별도 microservice를
추가하지 않는다. schema migration은 같은 owner source에서 제공하는 명시적
`migrate` command를 product bootstrap이 실행한다.

## 4. Recorder observability 상태 모델

하나의 `deviceCondition`이나 `online` 값으로 여러 사실을 합치지 않는다.
Recorder summary는 다음 축을 독립적으로 제공한다.

| 축 | 값 | 의미 |
| --- | --- | --- |
| `supportState` | `supported`, `unsupported`, `unknown` | Recorder가 self-observation protocol을 제공하는지 |
| `expectationState` | `expected`, `not-expected`, `unset` | 운영자가 report를 기대한다고 명시했는지 |
| `reportState` | `never-reported`, `current`, `stale` | accepted report의 존재와 freshness |
| `readState` | `available`, `unavailable`, `failed` | Catalog owner read 결과 |

규칙은 다음과 같다.

- accepted self-observation은 `supportState=supported`의 유일한 runtime
  evidence다.
- `unsupported`는 명시적 expectation command 또는 certified deployment
  profile에서만 온다.
- 아무 report가 없다는 사실만으로 `unsupported`를 만들지 않는다.
- `expected`이면서 `never-reported`인 경우에만 missing report를 사용자에게
  주의 상태로 제시할 수 있다.
- stale은 Catalog가 보존한 latest accepted timestamp와 명시 freshness
  policy로 계산한다.
- Gateway connection, packet count, upstream delivery는 이 네 축을
  변경하지 않는다.
- UI용 종합 `Stable`, `Needs attention`, `Critical incident`는 이
  workstream의 domain contract가 아니다. 이후 별도 policy가 complete owner
  inputs를 받을 때만 추가한다.

## 5. PostgreSQL schema와 migration

### 5-1. `recorder_catalog`

`recorder_catalog.admission_requests`

- `request_id` primary key
- authenticated source identity
- received byte count와 media type
- `received_at`
- terminal request outcome와 typed issue

`recorder_catalog.observations`

- internal immutable observation ID
- `request_id`
- `recorder_id`, `boot_id`, `sequence`
- optional source event ID
- `occurred_at`, `received_at`, `persisted_at`
- clock-quality summary fields
- resource/document type와 schema version
- `outcome`: `accepted`, `duplicate`, `quarantined`
- typed issue
- accepted or quarantined source document JSONB
- source document SHA-256

Unique/index requirements:

```text
UNIQUE (source_event_id) WHERE source_event_id IS NOT NULL
UNIQUE (recorder_id, boot_id, sequence)
INDEX  (recorder_id, occurred_at DESC)
INDEX  (recorder_id, received_at DESC)
INDEX  (recorder_id, persisted_at DESC)
INDEX  (outcome, persisted_at DESC)
GIN    (document jsonb_path_ops) only for reviewed JSON path queries
```

`recorder_catalog.recorder_current`

- one row per Recorder
- latest accepted profile/observation references
- support, expectation, report state inputs
- latest boot ID and sequence
- latest occurred/received/persisted timestamps
- current projection document JSONB and projection revision
- projection updated time

`recorder_catalog.expectation_events`

- immutable command event
- command/request ID
- Recorder ID
- expected/not-expected/support declaration
- source and reason
- issued/received/persisted timestamps

`recorder_catalog.recorder_expectations`

- one current projection per Recorder
- latest expectation event reference
- expected revision

Current projection과 expectation event는 같은 transaction에서 갱신한다.
observation admission도 immutable observation과 current projection을 같은
transaction에서 commit한다. external effect 뒤 terminal result persistence가
모호하면 성공을 반환하지 않는다.

### 5-2. `archive_export`

`archive_export.artifacts`

- artifact ID
- source kind
- immutable artifact manifest reference
- original file name과 media type
- byte size와 SHA-256
- source finalization state
- created/finalized timestamps

`archive_export.recorder_attributions`

- artifact ID
- Recorder가 보고한 bed name
- upload/finalization 시각
- assignment evidence reference
- candidate Recorder IDs
- outcome: `matched`, `unresolved`, `ambiguous`
- matched Recorder ID only when outcome is `matched`
- resolved policy version와 timestamp

`archive_export.upload_attempts`

- attempt and request ID
- artifact ID
- selected Upstream Provider reference
- attempt state와 typed failure
- started/finished timestamps

`archive_export.indexing_receipts`

- artifact ID와 upload attempt reference
- provider-owned receipt identity
- `indexed`, `not-indexed`, `unknown`, `unsupported`, `failed`
- observed timestamp와 typed issue

`reportedBedName`은 Recorder identity가 아니다. assignment owner의
time-bounded evidence가 한 Recorder만 가리킬 때만 `matched`가 된다.

### 5-3. migration owner

- migration source는 `runtime-platform/services/guest-runtime` owner tree
  안에 둔다.
- migration tool은 Alembic을 사용하고 revision chain 하나를 canonical
  source로 관리한다.
- bootstrap은 PostgreSQL readiness와 migration terminal receipt를 각각
  확인한다.
- Runtime readiness는 expected Alembic revision과 schema owner read가 모두
  available일 때만 통과한다.
- migration failure에는 revision, stage, database identity, typed reason과
  log/evidence path를 남긴다.
- SQL `CREATE TABLE IF NOT EXISTS`를 application startup migration으로
  사용하지 않는다.

현재 revisions:

```text
0001_catalog_foundation
0002_catalog_expectations
0003_archive_lineage
0004_archive_source_admissions
0005_recorder_assignment_owner
0006_backup_owner
```

## 6. API와 command

### 6-1. Guest-only admission

Recorder Gateway가 호출하는 admission API는 Host public facade allowlist에
넣지 않는다.

```text
POST /internal/v1/recorder-catalog/observations
```

Input:

- authenticated Gateway identity
- request ID
- one versioned Recorder observation envelope

Result:

- `accepted` with immutable observation reference
- `duplicate` with existing reference
- `quarantined` with typed validation issue
- `admission-unknown` when durable commit existence cannot be determined

Gateway는 `occurredAt`을 수정하지 않고 `receivedAt`을 추가한다. Catalog는
`persistedAt`을 추가한다.

### 6-2. public Runtime reads

```text
GET /v1/runtime/recorders/{recorderId}/observability
GET /v1/runtime/recorders/{recorderId}/observability/timeline
GET /v1/runtime/recorders/{recorderId}/observability/incidents
GET /v1/runtime/recorders/{recorderId}/artifacts
GET /v1/runtime/artifacts/{artifactId}
```

Recorder list에는 작은 summary만 포함한다. detail, timeline, incidents와
artifacts는 선택 후 별도로 읽는다.

Timeline query는 `from`, `to`, `limit`, `cursor`, `timeBasis`를 요구한다.
`timeBasis`는 `recorder-occurred-at`, `gateway-received-at` 중 caller가
명시한다. clock quality가 없거나 불량하다고 다른 timestamp로 fallback하지
않는다. response는 제외된 record 수와 이유를 별도 집계로 제공한다.

Incident는 Recorder가 보고했거나 Catalog의 명시적 transition policy가 만든
event만 반환한다. log text, packet gap 또는 UI refresh 실패에서 incident를
추론하지 않는다.

모든 collection read는 bounded page와 opaque cursor를 사용한다. repository
failure는 `empty` page가 아니라 typed failed read다.

### 6-3. expectation command

```text
POST /v1/runtime/recorders/{recorderId}/observability-expectation
```

- caller-supplied request ID
- expected Recorder revision
- `expected` 또는 `not-expected`
- optional explicit `supported` 또는 `unsupported` declaration
- source와 reason

동일 request ID와 동일 command는 기존 receipt를 반환한다. 같은 request ID의
다른 command는 conflict다. command admission failure와 terminal operation
failure를 구분한다.

### 6-4. Recorder `.vital` upload admission

Recorder의 direct/naive upload는 Recorder Gateway public data-plane route가
받는다. Gateway는 body를 메모리에 모두 올리지 않고 bounded streaming 또는
multipart spool로 durable admission한 뒤 Archive Export port에 source
receipt를 전달한다.

Gateway와 Guest Archive 사이의 내부 전송은 작은 source admission command를
bounded base64url JSON header로 보내고 `.vital` bytes는
`application/x-vital` body로 streaming한다. Guest object store는 실제
byte count와 SHA-256을 Gateway receipt와 비교하고 file과 object receipt를
sync한 뒤 directory rename으로만 공개한다. PostgreSQL의 accepted source
request, artifact와 attribution은 그 다음 한 transaction으로 commit한다.
object commit 뒤 PostgreSQL 결과가 unknown이면 성공을 반환하지 않으며,
동일 source receipt의 deterministic artifact ID로 retry한다.

Source kind는 closed set이다.

```text
recorder-upload
gateway-cold-path
lab-export
manual-upload
```

`recorder-upload`는 reported bed name과 transport/source receipt를 보존한다.
`gateway-cold-path`는 finalized cold-path receipt 없이는 admit하지 않는다.
`lab-export`는 stopped Lab recorder revision과 source finalization receipt를
요구한다. 이 source들은 같은 artifact table에 있을 수 있지만 서로의 source
evidence를 대체하지 않는다.

## 7. `.vital` validation과 replay failure

Archive formation과 Lab replay adapter는 같은 versioned Vital file parser
contract를 사용한다. 지원하는 과거 file-format version 목록과 fixture를
명시한다.

Track validation:

| type | 의미 | 규칙 |
| --- | --- | --- |
| `1` | waveform | `srate > 0`; record sample array를 rate에 맞춰 처리 |
| `2` | numeric | `srate=0` 허용; record timestamp를 사용 |
| `5` | string | 명시적 skip 또는 typed unsupported |
| other | unknown | 명시적 skip/reject policy |

Numeric track에 임의 `srate=1`을 넣어 waveform으로 바꾸지 않는다.

Replay operation failure:

```text
status: failed
failureStage:
  file-validation
  track-decode
  replay-preparation
  message-send
  upstream-delivery
failureCode
failureMessage
failedAt
```

사용자가 요청한 stop은 `stopped`이며 system failure인 `failed`와 다르다.
terminal transition 뒤에도 원래 failure를 보존한다. graph-compatible signal이
없으면 replay/session을 성공으로 완료하지 않는다.

### 7-1. vNext replay owner와 구현 순서

vNext의 기존 Lab Runner는 생성형 scenario 실행기이며 `.vital` replay가
아니다. 따라서 scenario run에 optional error 필드만 추가하지 않는다.
Guest Runtime이 durable replay operation을 소유하고, Lab Runner는 선택된
effect command만 수행한다.

Replay 입력은 다음 source를 서로 다른 owner fact로 유지한다.

| source | owner | replay 입력 방식 |
| --- | --- | --- |
| 사용자가 Lab에 올린 파일 | Lab replay source store | `lab-replay-source` immutable reference |
| Recorder 직접 upload | Archive `recorder-upload` artifact | explicit artifact-to-replay selection |
| Gateway cold path | Archive `gateway-cold-path` artifact | explicit artifact-to-replay selection |

bed name, 파일명 또는 동일한 SHA-256만으로 source kind를 바꾸거나 Recorder
identity를 추론하지 않는다. 긴 `.vital` 파일은 5분 단위 artifact로 분할하지
않는다. parser와 sender가 bounded streaming/batch 처리를 소유하고 원본
artifact identity는 하나로 유지한다.

Guest-owned state machine은 아래 순서만 허용한다.

```text
pending-file-validation
  -> pending-track-decode
  -> pending-replay-preparation
  -> sending
  -> awaiting-upstream-delivery
  -> succeeded
```

각 비 terminal state는 같은 이름의 effect command 하나만 반환한다.
adapter failure event는 현재 state에 대응하는
`file-validation`, `track-decode`, `replay-preparation`, `message-send`,
`upstream-delivery` stage를 명시해야 한다. stage가 현재 state와 다르면
transition을 거부한다. 어느 비 terminal state에서든 사용자 stop은
`stopped`가 되며 failure를 만들지 않는다. `failed`, `stopped`, `succeeded`
이후에는 다른 terminal 의미로 전이하지 않는다.

source implementation의 첫 단계로 pure
`LabReplayOperation`/`LabReplayEvent`/`LabReplayTransitionDecision`을
추가했다. Lab source admission은 하나의 원본 artifact identity를 유지하면서
Host facade→Guest object store까지 binary body를 streaming한다. Host는 body를
JSON/메모리 buffer로 바꾸거나 5분 segment로 분할하지 않으며, object store는
staging file의 byte count와 SHA-256을 검증한 뒤 atomic rename한다. 장시간
전송 중에는 Host endpoint 상태 workflow lock을 잡지 않으므로 unrelated
Control API가 upload 종료까지 기다리지 않는다.

v1~v3 호환성 정책도 pure domain decision으로 고정했다. gzip header와
bounded TRACKINFO metadata를 읽는 adapter가 이 decision을 호출한다. Track kind는
`waveform=1`, `numeric=2`, `string=5` enum을 먼저 해석하고, numeric의
`srate=0`을 그대로 보존한다. known graph signal은 published VitalServer
TRACKINFO `montype` wire ID enum으로만 판정한다. filename, track name 또는
임의 dictionary label로 monitor type을 추론하지 않는다.

record scanner는 waveform을 최대 64 KiB chunk로 전달하고 numeric/string
record timestamp를 decode한다. operation-owned SQLite spool은 staging,
database/receipt fsync와 atomic directory rename 후에만 공개하며 source 파일을
시간 단위로 나누지 않는다. frame reader는 명시적인 `omit-track` 또는
`fail-frame` gap policy만 사용한다. 제품 C37은 spool root, string-track
policy와 gap policy를 모두 필수 입력으로 전달하며 현재 제품 선택은
`skip`/`fail-frame`이다.

Replay operation과 effect outbox는 Guest Runtime SQLite에서 한 transaction으로
전이한다. process가 spool publication 뒤 operation commit 전에 중단되면 다음
실행은 replay ID, receipt, database digest와 scan metadata를 검증한 뒤 같은
spool만 재사용한다. file validation과 track decode failure는 stage/code/message/
failedAt을 terminal operation에 남긴다. C75 public command/read와 Host facade
allowlist는 durable operation 및 typed terminal failure를 그대로 전달한다.
command admission은 file validation 완료를 의미하지 않는다.

새 replay admission은 caller `requestedAt`을 explicit Guest admission clock과
비교한다. 미래 timestamp는 operation이나 outbox를 만들지 않고 HTTP `400`,
`state=rejected`, `code=lab-replay-requested-at-in-future`와 Guest-owned
`rejectedAt`으로 반환한다. clock이 맞을 때까지 worker가 같은 chronology
오류를 반복하는 wait/fallback은 사용하지 않는다. 이미 수락된 동일 command의
idempotent retry는 clock regression 뒤에도 저장된 operation을 그대로
반환하며 새 admission policy를 다시 적용하지 않는다.

prepare/send/upstream-confirm effect는 Guest의 operation-owned cursor와 Lab
Runner의 별도 durable session receipt를 사용한다. 각 batch ID와 각 frame의
Gateway ingress identity는 replay ID, offset과 frame evidence로 결정되며,
acknowledgement 유실 뒤 재시도해도 Gateway가 같은 ingress receipt를 반환한다.
Gateway의 `send_data_idempotent`는 기존 packet ingress aggregate를 재사용하고,
accepted ingress와 VitalServer delivery를 하나의 성공으로 합치지 않는다.
Runner는 모든 frame의 Gateway delivery receipt가 `succeeded`인 경우에만
upstream confirmation receipt를 만든다. pending/scheduled delivery는 retryable
effect failure, exhausted/unsupported delivery는 typed terminal rejection이다.
Runner session path는 C37의 필수 `replayStateDirectory`이고 재부팅 뒤
preparation/batch/upstream receipt를 그대로 읽는다.

Guest Runtime의 replay worker는 public application lifecycle이 소유한다.
application open 이후 durable outbox의 다음 effect만 읽고, close 시 worker를
먼저 취소·join한 뒤 repository를 닫는다. preparation receipt의
`outputStartedAt`과 operation-owned `nextFrameOffsetSecond`가 전송 시각을
결정한다. v1 product policy는 1초 frame 하나를 batch 하나로 보내는
real-time pacing이며 source `.vital`이나 immutable spool을 시간 구간별 파일로
분할하지 않는다. transport outcome을 알 수 없는 실패와 아직 확정되지 않은
Gateway delivery는 operation을 성공 또는 실패로 추론하지 않고 같은 durable
effect를 1초 뒤 다시 확인한다.

process-level acceptance는 실제 PostgreSQL-backed Guest Runtime, Lab Runner,
Recorder Gateway와 Socket.IO VitalServer acknowledgement fixture를 실행한다.
deterministic ingress retry, terminal upstream failure 전파, Guest-owned durable
effect worker, 그리고 explicit accepted acknowledgement 이후에만 만들어지는
upstream receipt와 terminal success를 증명한다. Runner batch send fact는
`lastSendState=sent`, VitalServer acknowledgement는 별도
`upstreamDeliveryReceipt`로 보존한다.

### 7-2. Runner terminal rejection이 Guest에서 대기 상태로 남는 실패

- 증상: Gateway에는 `retry.state=exhausted` delivery receipt가 있지만 Guest
  replay는 `messagesSent > 0`, `lastSendState=sent`,
  `state=awaiting-upstream-delivery`에서 계속 재시도한다.
- 원인: Runner의 typed `400 rejected` issue에는 `retryable`과 `dependency`가
  있었지만 Guest의 strict response decoder가 두 필드를 계약에 선언하지
  않았다. `DisallowUnknownFields` decode failure가 typed terminal rejection을
  일반 transport error로 바꾸어 상태 머신에 failure event가 전달되지 않았다.
- 수정: Guest Runner adapter가 `code`, `message`, `retryable`,
  `dependency`를 모두 decode하고, `retryable=false`와 유효한 dependency가
  명시된 rejection만 `LabReplayEffectRejectedError`로 application에 전달한다.
  누락되거나 retryable인 issue는 terminal로 추론하지 않는다.
- 예방: producer의 실제 error document 전체를 consumer contract fixture로
  검증한다. success body만 맞추거나 issue의 일부 필드를 무시하지 않는다.
  composed acceptance는 VitalServer를 중단해 Gateway exhausted receipt,
  Runner typed rejection, Guest `failureStage=upstream-delivery`와
  `failureCode=vitalserver-delivery-terminal-failure`까지 확인한다.

남은 구현 단위는 다음과 같다.

1. 비식별·재배포 provenance가 승인된 real-file compatibility corpus
2. Runtime Console C75 replay/Recorder list/Detail UI의 installed-product smoke

## 8. Runtime Console

Recorder list는 다음 작은 summary만 표시한다.

- Recorder identity
- assigned bed
- Gateway connection fact
- relative Last Seen
- Recorder report state
- latest artifact status

Recorder Detail은 lazy read로 구성한다.

```text
Overview
Device report
History
Vital files
Actions
```

- ISO first/last seen과 verification time은 Detail에 둔다.
- Gateway connection, Recorder report와 upstream delivery를 별도 행으로
  표시한다.
- visibility는 큰 status card가 아니다.
- `Hide`는 `Hide from Recorder list`처럼 결과를 설명한다.
- timeline/incidents/artifacts는 Detail을 열기 전에는 fetch하지 않는다.
- navigation과 selection 변경은 이전 detail request를 취소한다.
- UI는 `unsupported`, `not-expected`, `never-reported`, `stale`, read failure를
  임의 label 하나로 합치지 않는다.

C5 구현은 Catalog owner의 `/v1/runtime/recorders` bounded page를 먼저 읽고
각 Recorder를 support/expectation/report/read 축으로 표시한다. Recorder 선택
전에는 timeline, incident, artifact를 읽지 않는다. 선택 변경, 명시적 Cancel,
renderer unmount는 AbortSignal을 preload IPC request ID와 Desktop main의
pending Host-local HTTP request까지 전달한다. 늦은 응답은 generation guard로도
현재 Detail을 덮지 못한다.

C75는 Recorder ID별 summary/timeline/incidents/artifacts read와 Lab replay
command/read를 named request로 제공한다. Recorder Detail은 선택 이후에만 네
bounded read를 실행한다. selection 변경, Cancel과 component unmount는
renderer generation만 바꾸는 것이 아니라 `AbortSignal`을 preload IPC
correlation과 desktop main을 거쳐 Host local HTTP transport까지 전달한다.
따라서 취소된 request는 응답을 버리는 데 그치지 않고 실제 pending socket
request가 종료된다.

## 9. Backup과 restore

자동 backup의 최소 범위:

- Guest Runtime SQLite operation/control ledger
- PostgreSQL `recorder_catalog`
- PostgreSQL `archive_export`
- PostgreSQL `recorder_assignment`
- PostgreSQL `guest_operational_state`
- artifact manifest와 owner-declared metadata

Docker image, 재생성 가능한 cache와 telemetry backend data는 포함하지 않는다.
원본 `.vital`/raw archive byte의 보존은 별도 artifact retention policy가
결정하며 metadata backup이 이를 대신하지 않는다.

Backup manifest:

- operation/request ID
- database identity
- SQLite schema version
- PostgreSQL Alembic revision
- included owner schemas
- artifact path, byte size와 SHA-256
- started/finished time와 terminal result

Restore는 빈 target에 수행하고 migration revision, current projection,
expectation, observation history, artifact attribution, upload/index receipt를
public owner API로 검증한다. 일부 owner만 복원된 결과는 complete success가
아니다.

### 9-1. 최소 C6 소유 경계

C6는 범용 backup 제품이나 외부 storage lifecycle을 새로 만들지 않는다.
첫 구현은 Guest operational state의 일관된 local backup/restore proof만
소유한다.

| 책임 | owner | 명시 계약 |
| --- | --- | --- |
| schedule, retention, destination selection | Host deployment | backup request와 immutable destination reference |
| SQLite online snapshot | Guest backup workflow | source database identity, schema version, byte size, SHA-256 |
| PostgreSQL logical snapshot | Guest backup workflow | database identity, Alembic revision, included owner schemas, dump SHA-256 |
| artifact metadata inventory | Archive owner | artifact ID/path/size/SHA-256와 `objectBytesIncluded=false` |
| immutable backup publication | Guest backup workflow | staging fsync 후 atomic publish된 manifest/receipt |
| restore target provisioning | Guest restore workflow | empty SQLite path와 empty PostgreSQL database proof |
| restored-state verification | 각 public owner API | projection/history/attribution/receipt evidence |

Host는 PostgreSQL table, SQLite file name, migration log나 artifact directory를
직접 탐색하지 않는다. Guest workflow가 source identity와 owner schema를
계약으로 제공한다. metadata backup은 raw `.vital` object 보존 성공을 뜻하지
않으며 v1 manifest는 반드시 `objectBytesIncluded=false`를 기록한다.

최소 상태 머신은 다음과 같다.

```text
requested
  -> snapshotting-sqlite
  -> snapshotting-postgresql
  -> inventorying-artifacts
  -> publishing
  -> succeeded | failed

restore-requested
  -> validating-backup
  -> proving-empty-target
  -> restoring-sqlite
  -> restoring-postgresql
  -> verifying-owner-reads
  -> succeeded | failed
```

각 전이는 request ID, operation revision, stage별 immutable receipt와 typed
failure를 남긴다. `pg_dump`/`pg_restore`, SQLite backup, checksum 또는 owner
read 중 하나라도 실패하거나 결과가 모호하면 operation은 성공하지 않는다.
restore는 기존 target에 merge/overwrite하지 않으며 empty-target proof가
없으면 시작하지 않는다.

### 9-2. C6 구현 순서

1. backup manifest, backup/restore command, operation, stage receipt와
   empty-target proof schema를 추가한다.
2. pure state machine과 invalid/out-of-order transition test를 추가한다.
3. SQLite online snapshot, PostgreSQL custom-format dump/restore, immutable
   publication adapter를 각각 port 뒤에 둔다.
4. application workflow가 stage receipt와 operation을 한 owner ledger에
   durable하게 기록하도록 한다.
5. empty PostgreSQL database와 빈 SQLite target을 만든 acceptance fixture에서
   backup→restore를 실행한다.
6. 복원 후 migration revision, current/expectation/history, artifact
   attribution, upload/index receipt를 public API로 대조한다.
7. 마지막에 Host schedule/destination reference와 C37 process configuration을
   연결한다.

2026-07-24 구현 메모:

- C37은 backup root, snapshot 대상과 분리된 workflow ledger,
  `guest-backup-destination` reference, `pg_dump`와 `pg_restore` 실행 파일을
  모두 명시한다. 일부만 존재하는 구성은 시작 전에 거부한다.
- 일반 Runtime 배포는 현재 상태의 backup만 구성한다. Restore admission은
  별도로 provision한 absent SQLite path와 live database가 아닌 empty
  PostgreSQL URL이 모두 제공된 maintenance/acceptance 구성에서만 열린다.
- durable worker는 HTTP 요청과 독립적으로 pending effect를 재개한다.
  mutation 이후 ledger commit 전에 재시작해도 immutable stage evidence와
  owner read proof로 같은 effect를 검증하며, mutation을 성공으로 추측하지
  않는다.
- artifact inventory는 metadata만 streaming하며
  `objectBytesIncluded=false`이다. Recorder upload `.vital` object 보존과
  C76 metadata backup 성공은 서로 다른 상태다.
- PostgreSQL CLI에는 database URL 전체를 `PGDATABASE`로 전달하지 않는다.
  adapter가 URL을 명시적 libpq 환경으로 분해하고 inherited libpq state를
  제거한다. `pg_restore`는 검증된 database name을 `--dbname`으로 함께
  받아야 한다. URL query 중 지원하지 않는 연결 정책은 시작 전에
  거부하며 credential이 argv에 노출되지 않게 한다.

production composition은 backup과 restore를 같은 availability로 취급하지
않는다. 일반 C37 product deployment는 `operationalStateBackup`만 제공하며
restore command는 `guest-operational-state-restore-owner-unavailable`로
명시적으로 거부된다. maintenance deployment가 다음 세 값을 모두 제공할
때만 restore stage executor와 admission을 함께 활성화한다.

- `guest-restore-target` reference
- live Guest Runtime SQLite와 다른, 아직 존재하지 않는 SQLite target path
- live Catalog material과 다른, 사전에 empty로 provision한 PostgreSQL
  database URL material path

부분 설정, live SQLite path 재사용, live PostgreSQL material 재사용은 C37
validation failure다. process supervisor는 이 설정이 존재할 때만 restore
인자를 Guest Runtime에 전달한다. Guest Runtime은 다시 application
composition에서 complete-set과 source/target 분리를 검증한다. 따라서 UI,
Host probe 또는 restore request가 owner availability를 추정해 활성화할 수
없다.

Host C33는 backup timing과 destination을 다음 explicit deployment state로
소유한다.

- UTC epoch 기준 interval schedule ID와 interval seconds
- Guest C37과 일치해야 하는 `guest-backup-destination` reference
- admission outcome이 unknown/unavailable일 때 같은 slot을 재시도하는 interval
- v1의 삭제 없는 `retain-all` retention policy

각 UTC slot의 request ID와 operation ID는 schedule ID와 slot timestamp에서
결정론적으로 만든다. Host 재시작이나 retry는 같은 ID를 다시 보내며 실제
중복/current operation 판단은 Guest ledger owner가 수행한다. Host는
manifest, SQLite path, PostgreSQL table 또는 backup directory를 읽어 성공이나
중복을 추론하지 않는다. `retain-all`은 누락된 purge 구현을 성공으로 숨기는
fallback이 아니라, v1이 자동 삭제를 수행하지 않는다는 명시 정책이다.

### 9-3. PostgreSQL owner dump 선택 실패

증상:

- `pg_dump`가 성공하고 custom-format archive도 열리지만,
  `pg_restore --list`에는 `public.alembic_version`만 있고
  `recorder_catalog`, `archive_export`, `recorder_assignment`,
  `guest_operational_state`가 없다.

원인:

- 한 invocation에 `--schema=<owner>`와
  `--table=public.alembic_version`을 같이 넘기면 선택 범위가 합집합이 되지
  않는다. 실제 PostgreSQL 16에서는 table filter가 owner schema 선택을
  제거한 archive가 만들어졌다.

수정 방향:

- source owner가 `public` schema에 `alembic_version`과 그 primary-key index
  외 관계가 없음을 먼저 증명한다.
- 네 owner schema와 `public` schema를 명시적으로 dump한다.
- restore target은 public relation도 없는 상태여야 하며,
  empty-target proof 이후 한 transaction에서 `--clean --if-exists`로
  기본 `public` schema를 archive의 `public` schema로 교체한다.
- restore 후 source와 같은 `database_id`, Alembic revision, 네 owner schema와
  owner read surface를 다시 증명한다.

예방 원칙:

- `pg_dump` exit code나 archive 존재만 backup 성공으로 사용하지 않는다.
- 실제 지원 PostgreSQL 버전으로 `pg_restore --list`와 empty-database restore를
  acceptance gate에 포함한다.
- 선택 option의 결합 의미를 추정하지 않고 실제 archive TOC로 증명한다.

### 9-4. restore 후 public owner read parity

empty-target restore acceptance는 table count나 adapter 내부 SQL 성공만으로
완료하지 않는다. 동일한 고정 clock을 사용하는 source/target public Control
HTTP owner surface에서 다음 응답 bytes가 같아야 한다.

- bounded Recorder summary page
- Recorder observability current, timeline과 reported incidents
- matched Recorder artifact page
- artifact detail의 attribution, upload attempts와 indexing receipts

2026-07-24 PostgreSQL 16 acceptance에서 이 검증은 public page limit `100`을
application이 repository lookahead `101`로 전달하지만 PostgreSQL adapter가
`100`까지만 허용하던 경계 불일치를 발견했다. 증상은 restore 성공 뒤
`recorder-artifact-page-read-failed`와
`bounded Recorder artifact query is invalid`였다. public page size와
repository lookahead fetch size를 별도 application port 상수로 정의하고
adapter가 후자를 검증하도록 수정했다.

예방 원칙:

- public page limit과 repository fetch limit을 같은 의미로 취급하지 않는다.
- keyset cursor를 만들기 위한 한 건의 lookahead를 owner port 계약에
  명시한다.
- backup/restore acceptance는 source와 restored target 양쪽의 public owner
  API를 호출해 projection과 lineage receipt parity를 증명한다.

## 10. 구현 순서

### Phase A — contract와 persistence

1. 이 문서의 state axes와 source kind를 JSON Schema/OpenAPI에 추가한다.
2. positive/negative/old-Recorder fixture를 추가한다.
3. PostgreSQL deployment declaration과 owner credentials를 추가한다.
4. `0001`–`0003` Alembic migration과 clean-database proof를 추가한다.
5. PostgreSQL repository를 구현한다.
6. SQLite Catalog repository와 startup DDL을 삭제한다.

완료 조건:

- contract compatibility와 negative decode gate 통과
- PostgreSQL integration test에서 migration/admission/idempotency 통과
- Runtime readiness가 expected migration revision을 명시
- vNext runtime source에 Catalog dual-write가 없음

### Phase B — admission, projection과 history

1. Guest-only admission authentication과 route를 추가한다.
2. Gateway observation publisher를 해당 route에 연결한다.
3. current/expectation transaction과 public detail read를 구현한다.
4. bounded timeline/incident repository와 API를 구현한다.
5. backup/restore proof에 네 PostgreSQL owner schema
   (`recorder_catalog`, `archive_export`, `recorder_assignment`,
   `guest_operational_state`)와
   `public.alembic_version`을 포함한다.

완료 조건:

- accepted, duplicate, quarantined, admission-unknown acceptance 통과
- supported/unsupported/unknown과 expected/not-expected/unset 조합 통과
- read failure가 empty collection으로 바뀌지 않음
- backup 후 빈 database restore acceptance 통과

### Phase C — artifact lineage와 replay

1. direct Recorder upload streaming admission을 Gateway에 추가한다.
2. Archive Export artifact/attribution/upload/index repository를 구현한다.
3. bed assignment evidence adapter와 matched/unresolved/ambiguous policy를
   구현한다.
4. older Vital file fixtures와 typed replay failure를 추가한다.
5. cold path, Recorder upload와 Lab export가 구분되는 acceptance를 추가한다.

완료 조건:

- 한 Recorder로 명확히 귀속된 파일과 unresolved/ambiguous 파일 조회 가능
- upload success와 indexing result가 독립적으로 보존됨
- 10시간 이상 단일 `.vital` 파일을 시간 단위로 임의 segment하지 않음
- graph-incompatible file과 send failure가 successful session이 되지 않음

2026-07-24 구현 상태:

- Alembic `0004_archive_source_admissions`가 request ID와 full command digest,
  accepted/duplicate/quarantined receipt를 보존한다. 실제 PostgreSQL 16
  migration과 accepted artifact/attribution/request atomic commit proof가
  통과했다.
- `archive_export` PostgreSQL repository는 artifact와 attribution을 한
  transaction으로 commit한다.
- upload attempt와 indexing receipt는 별도 owner fact로 commit하며 실제
  PostgreSQL integration test가 `upload=succeeded`,
  `indexing=not-indexed` 조합을 보존한다.
- artifact detail과 matched Recorder artifact page는 bounded public read와
  Host facade allowlist까지 연결되었다.
- Recorder Gateway의 multipart spool은 `.vital` file part를 메모리에
  materialize하지 않고 transaction directory에 streaming write한다. file과
  source receipt를 sync한 뒤 directory rename으로만 durable admission을
  공개하며 원본 파일을 시간 단위로 segment하지 않는다.
- Guest Archive object store와 source-admission application policy는
  streaming byte/hash 검증, deterministic object identity, idempotent
  accepted receipt와 durable quarantine을 구현했다.
- authenticated internal
  `POST /internal/v1/archive/recorder-uploads` adapter는 source command와
  binary body를 분리하고 rejected, quarantined, admission-unknown을 서로
  다른 typed outcome으로 반환한다.
- Recorder Gateway는 source receipt마다 append-only dispatch revision을
  보존하고 Guest Archive endpoint에 authenticated streaming body로 전달한다.
  process start와 configured interval recovery는 `pending`, `dispatching`,
  `unknown`만 재시도하며 terminal state를 다시 전송하지 않는다.
- public `/upload`는 Guest가 `accepted` 또는 `duplicate` artifact receipt를
  반환한 경우에만 Recorder 호환 plaintext `success`를 반환한다.
  quarantine, rejection과 durable outcome unknown은 서로 다른 HTTP/typed
  failure로 남는다.
- C37 product deployment와 Guest Process Supervisor는 PostgreSQL URL/token,
  Archive admission token/object root/byte limit, Gateway endpoint와 recovery
  policy를 child process에 전달한다. C35 bootstrap composer는 이 필수 입력과
  Guest/Gateway token 및 byte-limit 일치를 compile-time에 검증한다.
- C39/C40은 PostgreSQL과 Alembic/Psycopg package, persistent private/object
  directory, generated database password와 두 bearer token, canonical
  migration executable 및 expected revision을 명시한다.
- Guest bootstrap은 PostgreSQL role/database와 private material을 만든 뒤
  embedded Alembic migration을 실행하고 exact revision의 terminal receipt를
  durable path에 기록한 후에만 C38 product service를 시작한다.
- `/run`은 reboot 때 사라지므로 database URL과 bearer token은
  `/var/lib/vitalserver/private`에 보존한다. Supervisor와 child process는 이
  owner path만 소비한다.
- bootstrap composer, Guest Runtime, Supervisor와 C39/C40 contract regression은
  통과했다.
- Guest Runtime readiness는 SQLite control ledger뿐 아니라 Recorder Catalog와
  Archive Export PostgreSQL owner가 exact Alembic revision 및 자기 schema를
  읽을 수 있는지 매 요청마다 확인한다. PostgreSQL failure는 `ready`나 empty
  Catalog로 바뀌지 않는다.
- C77 `GuestOperationalStateIdentity`는
  `GET /v1/runtime/operational-state/identity`에서 SQLite `databaseId`와
  schema version, PostgreSQL `databaseId`, exact `0006_backup_owner` revision,
  네 owner schema, migration receipt와 세 private material의 비밀을 노출하지
  않는 aggregate identity를 하나의 all-or-failed read로 제공한다. Host
  facade와 `platformctl runtime operational-state-identity`는 이 Guest-owned
  문서만 전달한다. Host, clean-host runner와 UI가 Guest 파일명, DB table,
  log 또는 누락을 해석해 identity를 만들지 않는다.
- clean install에서는 C77 available 결과와 migration receipt를 함께
  보존하고, reboot 뒤 C77의 SQLite/PostgreSQL/bootstrap identity
  subdocument가 같은지 확인한다. 조회 시각인 `observedAt`은 비교 대상이
  아니며 매 owner read의 실제 시각을 계속 명시해야 한다. 한 owner read라도
  실패하면 partial identity 없이 typed dependency failure이며 reboot proof는
  실패다.
- 아직 남은 C3 release gate는 실제 clean Guest에서 first boot, migration
  receipt, product readiness와 reboot 후 동일 material/revision/readiness를
  관찰하는 installed-product acceptance다.
- migrated PostgreSQL 16과 동일 SQLite/private-material 입력을 사용한 portable
  Host facade restart acceptance는 C77의 `sqlite`, `postgresql`, `bootstrap`
  동일성을 실제 `platformctl` 경로에서 통과했다. C78 runner의 immutable
  journal/evidence, Host boot-session 변경, identity-change failure와
  `available`이지만 `ready`가 아닌 readiness 거부 테스트도 통과했다. 이
  결과는 실제 ARM64 Guest boot나 C24 설치 증거를 대신하지 않는다.
- `reportedBedName`과 `declaredRecorderCode`는 attribution evidence일 뿐이다.
  authenticated Recorder identity 또는 assignment-owner evidence가 없으면
  attribution은 `unresolved`여야 한다.

### Phase C-1 — assignment owner 결정

Attribution 구현 전에 Guest 안에 명시적인 Recorder assignment owner를
추가한다. Archive repository가 Catalog current row나 Gateway 접속 상태를
직접 조회해서 identity를 만들지 않는다.

최소 owner contract는 다음과 같다.

- immutable assignment evidence ID와 source
- Recorder ID와 reported bed name
- `effectiveFrom`과 optional `effectiveUntil`
- evidence observation time와 persisted time
- source evidence reference
- bounded query: `(bedName, artifact.finalizedAt) -> complete candidate set`

resolver 결과 규칙:

- candidate 1개: `matched`
- candidate 0개: `unresolved`
- candidate 2개 이상: `ambiguous`
- assignment owner read/decode failure: Archive admission `unknown`

`declaredRecorderId`, `declaredRecorderCode` 또는 최신 Catalog observation은
candidate set을 보완하는 fallback이 아니다. 이후 Recorder가 assignment
profile을 POST할 수 있더라도, 해당 profile을 assignment owner가 인증·admit한
immutable evidence로 만든 뒤 같은 query port를 통해서만 사용한다.

2026-07-24 source implementation은 이 경계를 다음과 같이 고정한다.

- `POST /v1/runtime/recorder-assignments`는 administrator source의 immutable
  assignment evidence만 admit하며 request ID 재사용을
  `duplicate`와 `conflict`로 구분한다.
- Alembic `0005_recorder_assignment_owner`가 evidence와 immutable resolution을
  별도 `recorder_assignment` schema에 보존한다.
- assignment owner가 `(bedName, artifact.finalizedAt)`의 전체 evidence와
  candidate set을 canonical resolution ID로 저장한다.
- Archive attribution은 그 resolution reference만 소비한다. candidate 0개는
  명시적 `unresolved`, 1개는 `matched`, 복수는 `ambiguous`다.
- owner read/decode/validation failure는 Archive admission error다. bed name,
  Catalog observation 또는 Recorder 선언으로 candidate를 보완하는 배포
  policy는 존재하지 않는다.

실제 PostgreSQL 16에 `0001`~`0006_backup_owner`를 적용한 migration 및
assignment/Catalog/Archive repository integration acceptance는 통과했다.
남은 release proof는 clean Guest first-boot/reboot에서 같은 exact revision과
owner read를 다시 확인하는 것이다.

### Phase D — Console과 macOS delivery proof

1. Recorder summary/detail/artifact generated client type을 추가한다.
2. lazy Detail과 request cancellation을 구현한다.
3. Helper 0.2의 readable Recorder layout을 vNext owner contract로 재구성한다.
4. Developer ID Supervisor/PKG를 clean Mac에 설치한다.
5. clean install, same-release reinstall, data-preserving repair, reboot,
   update, failed-update rollback, uninstall/reinstall와 runtime boot를 C24에
   기록한다.

완료 조건:

- UI가 owner read만 표시하고 domain state를 만들지 않음
- package generation proof와 installed product proof가 분리됨
- matching clean-host C24가 모든 required stage를 `passed`로 기록
- Guest rootfs/run/deploy receipt와 packaged payload가 exact digest로 일치
- 실제 Guest bootstrap, stack readiness와 VM shutdown proof 통과

## 10-1. 남은 실행 목표와 gate 순서

최종 목표는 “source test가 통과한다”가 아니라 다음 한 문장으로 정의한다.

> clean macOS Host에 선택된 package를 설치하면 Guest가 PostgreSQL Catalog와
> Archive store를 명시적으로 bootstrap하고, Recorder observation과 `.vital`
> upload/replay 상태를 owner contract로 제공하며, reboot와 backup/restore
> 뒤에도 같은 사실을 잃지 않고 C24 evidence로 증명한다.

남은 작업은 아래 순서를 바꾸지 않는다.

1. **C6 combined restore acceptance — portable workflow 완료**
   - 실제 owner evidence가 들어 있는 source에서 Guest SQLite online snapshot,
     PostgreSQL custom-format dump와 artifact metadata inventory를 하나의
     immutable manifest로 발행한다.
   - absent SQLite path와 system/public relation이 없는 PostgreSQL target에만
     복원하고, 두 번째 복원은 `target-not-empty`로 거부한다.
   - exact `0006_backup_owner`, database identity, projections, history,
     assignment, attribution과 upload/index receipt를 public owner read로
     대조한다. 이 workflow acceptance는 실제 PostgreSQL 16에서 통과했다.
     installed Guest의 public facade read는 C3/C24에서 별도로 증명한다.
2. **C4 replay compatibility acceptance**
   - C79는 비식별, 재배포 권한, 비임상 사용 제한을 사람이 승인한 real
     `.vital` corpus와 exact file name/byte size/SHA-256/format version을
     선언한다. verifier는 승인 결정을 만들지 않고 외부 corpus의 등록
     bytes만 대조한다.
   - `lab-replay-approved-corpus-acceptance`는 migrated PostgreSQL과 C79
     manifest/directory를 명시적으로 요구하고 각 v1~v3 entry가 선언된
     format과 최소 graph-compatible signal 수로 Guest-owned `succeeded`
     operation에 도달해야 통과한다.
   - graph-compatible signal 0개, unsupported string/unknown track,
     preparation/message-send/upstream failure를 typed terminal operation으로
     검증한다. generated graph=0, unknown track, reject-policy string track과
     실제 VitalServer 중단 후 upstream terminal failure까지 migrated
     PostgreSQL 기반 public/process acceptance가 통과했다.
   - caller 시간이 Guest clock보다 미래인 경우 operation을 생성하지 않고
     Guest-owned rejection time과 typed `400` issue를 반환한다. 이 policy는
     domain/application/HTTP와 idempotent retry test로 고정되었다.
3. **C3 installed bootstrap proof**
   - clean Guest first boot에서 PostgreSQL service, exact Alembic revision,
     migration receipt와 product readiness를 확인한다.
   - reboot 전후 database identity, private material digest, revision과 public
     readiness를 비교한다.
   - package install 실패와 Guest bootstrap 실패를 서로 다른 stage/reason/log
     path로 보고한다.
   - C78 installed-runtime evidence runner는 C52 local-control descriptor를
     사용하는 `platformctl`과 Host boot-session `sysctl`만 소비한다.
     `first-boot-checkpoint`는 available readiness/C77을 보존하고,
     `direct-upload-lineage`는 승인 provenance의 `.vital` 전체 파일을
     multipart로 streaming하고 Recorder Assignment receipt, Recorder artifact
     page, Archive artifact detail의 source receipt/SHA-256/byte size/matched
     Recorder attribution이 모두 일치할 때만 verified다. Gateway의
     `success` 응답만으로는 통과하지 않으며 파일을 시간 구간으로 분할하지
     않는다. `post-reboot-identity`는 두 선행 stage가 verified인 경우에만
     실제 Host boot-session 변경과 C77의 SQLite, PostgreSQL, migration
     receipt/private-material-set identity 동일성을 요구한다. unavailable
     owner, lineage 불일치, identity 변경은 partial owner value 없는 typed
     failed evidence다.
   - macOS C24 runner는 세 C78 문서를 package `clean-install` 또는 Host
     `reboot` 성공에 섞지 않는다. 같은 plan/runner/evidence chain, changed
     boot session과 C77 owner identity를 다시 검증하여 별도 required
     `installed-guest-runtime` stage evidence에 exact document와 source
     digest를 보존한다.
4. **C5 installed Recorder Console proof**
   - 구현된 bounded summary와 lazy Detail read를 installed runtime에서
     검증한다.
   - observability, incidents, artifact lineage와 replay failure가 owner가
     제공한 서로 다른 상태로 표시되는지 확인한다.
   - navigation 시 in-flight Detail request가 Host HTTP transport까지
     취소되는지 supported Node 20 전체 suite와 desktop acceptance로 증명한다.
5. **C6 macOS C24**
   - clean install, same-release repair, reboot, update, failed-update rollback,
     uninstall/reinstall을 실제 package와 VM으로 실행한다.
   - 실제 C78 세 문서를 `record-installed-guest-runtime`으로 결속하고 C74가
     해당 stage evidence bytes를 review한 candidate만 release-ready로 인정한다.
   - 모든 stage가 matching release/package digest와 explicit proof context를
     가진 경우에만 release-ready로 판정한다.

각 gate는 contract, focused test, integration/acceptance와 운영 문서를 같은
change에 포함한다. 뒤 gate의 UI나 packaging logic은 앞 gate의 누락 상태를
추론하거나 성공으로 보완하지 않는다.

## 11. 계획된 commit 단위

1. `docs(runtime-platform): adopt Helper 0.2 product evidence`
2. `feat(contracts): define Recorder Catalog resources`
3. `feat(guest-runtime): migrate Recorder Catalog to PostgreSQL`
4. `feat(recorder-gateway): publish durable observations`
5. `feat(guest-runtime): project Recorder observability state`
6. `feat(guest-runtime): persist expectation commands`
7. `feat(guest-runtime): expose bounded Recorder history`
8. `feat(archive): track Recorder-uploaded Vital artifacts`
9. `feat(archive): resolve Recorder artifact attribution`
10. `feat(lab): preserve typed Vital replay failures`
11. `feat(console): show Recorder observation and artifact detail`
12. `test(delivery): prove macOS installed Runtime lifecycle`

각 commit은 contract, focused test와 관련 문서를 같은 change에 포함한다.
schema와 API를 먼저 바꾸고 consumer를 나중에 추측으로 맞추지 않는다.

## 12. 이번 범위의 비목표

- Helper database 또는 state file의 in-place import
- Helper와 vNext production dual-write
- automatic device-condition score
- packet gap이나 log text에서 만든 incident
- telemetry backend 확장
- 자동 장기 retention/purge
- 대규모 운영 dashboard
- bed name만으로 Recorder identity 확정
- `.vital` 파일의 임의 시간 segment

이 비목표가 필요해지면 별도 capability, owner, contract와 acceptance를 먼저
정의한다.
