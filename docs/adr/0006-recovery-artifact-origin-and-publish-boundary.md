# ADR 0006: Recovery artifact origin and publish boundary

## Status

Accepted

## Context

Vital Recorder가 직접 생성해 VitalServer에 업로드하는 `.vital` 파일과 recorder
ingress raw archive에서 재구성한 `.vital` 파일은 같은 artifact가 아니다. Raw
archive recovery 파일은 `send_data` payload의 파생물이며 native recorder file의
완전성, metadata, 시간 경계를 대신한다고 가정할 수 없다.

기존 cold path는 raw archive cursor를 export한 직후 같은 `/upload` endpoint로
전송하고 job을 `uploaded`로 기록했다. 파일 내부 `RecorderRecovery/METADATA` 외에는
origin receipt가 없었고, export 완료와 library publish 완료도 한 상태였다. File
name이나 metadata track을 읽어 source를 추정하는 것은 product state contract가
아니다.

## Decision

### Artifact origin

Recovery artifact owner는 생성 시 다음 origin 중 하나를 명시한다.

- `coldPathRecovery`: 실제 recorder `send_data` raw archive에서 파생
- `productLabGenerated`: Product Lab이 lifecycle과 publish intent를 소유

기존 VitalServer `/upload`로 들어오는 파일은 caller identity 계약이 없으므로
`nativeRecorder`로 추정하지 않는다. Recovery와 Product Lab artifact만 owner가
명시한 receipt로 식별한다.

### Export and publish

Export와 publish는 서로 다른 operation이다.

```text
archiveReady
  -> exportPending
  -> exporting
  -> exported
  -> publishRequested
  -> publishing
  -> published
```

실제 recorder의 inactivity와 recorder-ingress shutdown은 export까지만 요청한다.
Product Lab terminal Finish는 explicit publish intent를 제공할 수 있다. Pause,
disconnect, filename, file absence는 publish intent가 아니다.

### Receipt

Export success는 artifact id, origin, producer, recorder/room identity, source archive
identity와 byte window, coverage, format version, SHA-256, size, track count, writer
version을 포함한 receipt를 만든다. Publish는 receipt와 library index를 검증하고
별도의 publish receipt를 만든다.

### Invariants

- `exported`는 `published`가 아니다.
- Cold path는 기존 library file을 덮어쓰지 않는다.
- File/index read failure는 filename available로 바뀌지 않는다.
- Origin은 filename, track name, metadata absence로 추정하지 않는다.
- Retry는 같은 source window와 writer version에 대해 같은 artifact identity를
  사용한다.
- Upload success 후 index/registry commit 실패는 reconciliation failure이며 빈
  success나 재업로드로 바뀌지 않는다.

## Migration

Recorder ingress state schema v2는 v3로 명시적으로 migration한다. `uploaded`는
export와 publish가 모두 완료된 legacy receipt로 보존한다. Pending/running job은
export pending으로 재개한다. 실패 stage를 문서에서 증명할 수 없는 legacy failure는
`unknownLegacyStage`로 보존하고 자동으로 다음 단계로 진행하지 않는다.

## Consequences

Cold path artifact는 자동으로 일반 My Files에 섞이지 않는다. Recovery artifact
registry와 UI가 추가로 필요하지만 native file과 derived recovery file의 의미,
충돌, retry, failure가 명시적으로 분리된다.

## Implementation Status

- recorder-ingress state schema v3와 v2 migration이 구현되었다.
- inactivity, shutdown, Product Lab Finish는 `/raw-archive/export-vital`만 호출한다.
- recovery artifact receipt와 publish operation은 SQLite registry schema v2에 기록되고 read API로 조회할 수 있다.
- `POST /artifacts/{artifactId}/publish`가 explicit publish intent를 받고, 순수 상태 머신이
  `publishRequested`, `publishing`, `reconciling`, `published`, `failed` 전이를 결정한다.
- publish workflow는 private artifact의 size/SHA-256을 receipt와 대조하고, 기존 filename collision을
  차단한 뒤 한 파일을 streaming upload하며 VitalServer file index의 path/size proof가 있어야
  `published`를 commit한다. `publishing`/`reconciling` 재개는 재업로드하지 않고 index만 reconcile한다.
- raw archive decode는 bounded byte-window stream이며, track record는 operation-owned SQLite spool에
  저장한 뒤 source byte window와 vrcode마다 하나의 완전한 `.vital` artifact로 materialize한다.
  긴 녹화라는 이유로 waveform이나 artifact를 임의 시간 경계에서 분할하지 않는다.
