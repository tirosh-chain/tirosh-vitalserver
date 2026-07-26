# ADR 0005: Vital File Versioned Compatibility and Canonical Model

## 상태

Accepted, implementation in progress

## 배경

VitalServer 제품군은 `.vital` 파일을 생성, 복구, 업로드, 색인, 미리보기,
재생한다. 현재 이 기능들은 Python `vitaldb`, bundled VitalServer JavaScript,
Lab replay adapter, TestKit, Recorder Recovery에 분산되어 있다.

기존 구현에는 다음 문제가 있다.

- bundled VitalServer parser가 packet 시작 위치를 고정 offset으로 읽어 최신
  가변 길이 header를 처리하지 못한다.
- 일부 소비자가 track `type` 대신 `srate`로 waveform/numeric을 추론한다.
- TestKit과 Recorder Recovery가 최신 header를 과거 header처럼 다시 써서
  parser 문제를 artifact downgrade로 숨긴다.
- Lab replay가 string track과 unknown track의 처리 정책을 canonical contract가
  아닌 adapter 내부 분기로 결정한다.
- 업로드와 재생이 파일 전체 또는 multipart body 전체를 메모리에 적재한다.
- 파일명, 구조 검증, writer 로직이 package마다 중복되어 서로 다른 규칙을
  적용할 수 있다.

이미 생성된 Vital File은 제품보다 오래 보존될 수 있으므로 입력 호환성은
필요하다. 그러나 하위 버전 호환을 이유로 domain 전체에 버전 분기나 추론
fallback을 퍼뜨리면 파일의 실제 상태를 알 수 없게 된다.

## 목표

- Vital File v1, v2, v3를 명시적으로 읽고 재생할 수 있다.
- 입력 wire format은 version별 reader가 하나의 canonical domain model로
  정규화한다.
- waveform, numeric, string은 wire `type`으로만 구분한다.
- 새 artifact는 canonical 최신 포맷인 v3로만 생성한다.
- 손상, 미지원 version/type, decode 실패를 empty/default success로 바꾸지 않는다.
- 대용량 파일의 upload와 replay는 bounded-memory streaming 경계를 사용한다.

## 결정

### 지원 매트릭스

| 기능 | v1 | v2 | v3 | 알 수 없는 미래 version |
| --- | --- | --- | --- | --- |
| header probe | 지원 | 지원 | 지원 | typed reject |
| inspect/index | 지원 | 지원 | 지원 | typed reject |
| replay | 지원 | 지원 | 지원 | typed reject |
| 새 파일 생성 | 생성하지 않음 | 생성하지 않음 | 생성 | 해당 없음 |
| 명시적 offline migration | v3로 변환 가능 | v3로 변환 가능 | 불필요 | reject |

하위 버전 지원은 input compatibility다. v1/v2 writer나 runtime downgrade는
제공하지 않는다. Migration은 사용자가 명시적으로 실행하는 별도 operation이며,
원본을 보존하고 결과 검증에 성공한 뒤에만 v3 artifact를 제공한다.

### 계층 책임

```text
gzip byte source
  -> format probe
  -> version-specific reader (v1 | v2 | v3)
  -> canonical VitalFile document
  -> inspect | replay | upload preflight | migration

canonical writer v3
  <- TestKit | Recorder Recovery | explicit migration
```

- Core/Domain은 version, header, track kind, canonical document와 검증 오류
  계약을 정의한다. 완전한 명시적 입력만 계산하며 파일이나 네트워크를 읽지
  않는다.
- Adapter는 gzip, filesystem, stream, Python `vitaldb`, bundled VitalServer 같은
  외부 상태를 읽고 version별 wire 값을 Core 계약으로 변환한다.
- Workflow는 probe, reader 선택, validation, replay/upload/migration 순서를
  조정하고 명시적 결과를 저장한다.
- UI는 source version, validation state, unsupported item, failure를 표시할 뿐
  version이나 track kind를 추론하지 않는다.

### Header와 version

- decompressed stream은 `VITA`, little-endian format version, header length 순으로
  검증한다.
- packet 시작 위치는 항상 `10 + headerLength`다. 고정 `20` 또는 `37`을 packet
  시작 위치로 사용하지 않는다.
- 공통 10-byte header 뒤의 알려진 필드는 선언된 header length가 충분할 때만
  읽는다.
- 알려지지 않은 header extension은 보존하거나 안전하게 skip한다. extension을
  domain state로 해석하지 않는다.
- v1/v2/v3 외 version은 `unsupportedFormatVersion`으로 거부한다.

### Track 계약

| wire type | canonical kind | 필수 규칙 | replay 정책 |
| --- | --- | --- | --- |
| 1 | waveform | finite `srate > 0`, record sample array | sample index와 srate 사용 |
| 2 | numeric | record timestamp와 scalar 값, `srate=0` 허용 | record timestamp 사용 |
| 5 | string | record timestamp와 UTF-8 string | 명시적 emit, configured skip 또는 typed reject |
| 그 외 | 없음 | `unsupportedTrackType` | 명시적 reject/skip policy 필요 |

`srate`는 waveform의 속성이지 track kind discriminator가 아니다. Numeric의
`srate=0`은 정상 값이며 missing이나 실패가 아니다. String skip은 reader의
암묵적 동작이 아니라 replay operation의 명시적 설정이어야 한다.

### Canonical model

Canonical document는 최소한 다음 의미를 유지한다.

- source format version과 header metadata
- device identity와 track identity
- explicit track kind, encoding format, unit, display range, color, sample rate,
  gain, offset, monitor type
- timestamp가 있는 waveform/numeric/string record
- 알 수 없는 optional metadata와 알 수 없는 packet을 안전하게 건너뛴 진단
- validation issue와 source byte/packet 위치

Canonical model에는 version별 field 위치, gzip handle, filesystem path,
Python `vitaldb` object를 넣지 않는다. Version별 reader가 없는 값을 기본값으로
만들지 않으며, contract상 optional인 값만 `None`으로 표현한다.

### Writer와 VitalServer parser

- TestKit과 Recorder Recovery는 하나의 v3 writer adapter를 사용한다.
- 최신 header를 legacy 10-byte header로 rewrite하는 로직은 bundled VitalServer
  parser가 header length 기반 parsing을 사용한 뒤 삭제한다.
- bundled asset을 직접 임시 수정하기보다 유지 가능한 runtime wrapper 또는
  명시적인 patched asset 생성 경계를 둔다.
- writer 결과는 다시 v1/v2/v3 reader로 읽어 header, track kind, record count,
  timestamp 범위를 검증한다.

### 실패 계약

최소 오류 코드는 다음과 같다.

- `truncatedHeader`
- `invalidMagic`
- `unsupportedFormatVersion`
- `invalidHeaderLength`
- `invalidHeaderTime`
- `invalidPackedFlag`
- `unsupportedTrackType`
- `invalidTrackMetadata`
- `truncatedPacket`
- `invalidRecord`

오류에는 가능한 경우 source version, byte offset, track id/name, packet type를
포함한다. Decode 실패는 빈 track 목록, 0 records, stopped 상태로 바뀌지 않는다.

### Bounded-memory 전환 설계

Upload는 다음 owner 경계를 따른다.

1. macOS Host는 선택한 파일의 path, basename, size를 source descriptor로 소유하고
   security-scoped file handle에서 제한된 크기의 chunk를 읽는다.
2. Runtime Control과 Guest Control의 upload 전용 transport는 일반 JSON request의
   `Data`/`bytes` body 계약을 재사용하지 않는다. Multipart part를 임시 파일로
   stream하고, 완료되지 않은 part는 workflow 실패로 삭제한다.
3. Guest upload workflow는 완성된 임시 파일을 Core header probe로 preflight한 뒤
   gzip stream을 끝까지 제한된 buffer로 읽어 CRC를 검증한다. 검증 전에는
   VitalServer upload나 operation success로 전이하지 않는다.
4. Guest에서 VitalServer로 전달할 때 multipart prefix, source chunk, suffix를
   순서대로 보내며 source 크기만큼의 합성 body를 만들지 않는다.
5. 각 hop은 `Content-Length`, source size, received size를 비교하며 mismatch를
   `truncatedUpload` 또는 `uploadSizeMismatch`로 보고한다.

여러 파일을 선택한 Host→Guest 요청과 VitalServer upload 단위는 같은 의미가
아니다. Host→Guest는 반복 `files` part를 포함할 수 있지만 Guest는 이를 합쳐서
VitalServer에 보내지 않는다. 검증을 통과한 각 파일을 원래 선택 순서대로
`파일 1개 = POST /upload 1회`로 직렬 전송한다. 다음 파일은 앞 파일의 HTTP
응답을 받은 뒤에만 보낸다. 이 규칙은 한 요청에서 여러 대형 파일을 동시에
처리해 VitalServer app의 메모리 압력을 키우지 않기 위한 transport invariant다.

이 규칙은 단일 `.vital` 파일의 내부 packet을 여러 HTTP request로 나누는
chunked-upload protocol이 아니다. VitalServer `/upload`는 완전한 Vital File 한
개를 요구한다. 단일 파일 parse 자체가 app memory boundary를 넘는 경우에는
임의 byte 분할로 해결하지 않고, source owner가 만드는 시간 구간별 완전한
artifact 정책 또는 VitalServer가 명시적으로 제공하는 resumable upload 계약이
별도로 필요하다. 현재 제품에는 그런 wire 계약이 없으므로 안전한 크기를
추정하거나 부분 파일을 성공으로 전송하지 않는다.

VitalRecorder가 소유하는 기존 artifact 경계는 `CUT_HOURLY=1`이다. 이 설정은
한 `.vital` 파일의 wire bytes를 사후 분할하는 것이 아니라 recorder가 매시간
새롭고 완전한 `.vital` 파일을 생성하게 한다. Recorder Recovery exporter는 현재
명시적으로 선택된 raw archive byte window를 vrcode별 artifact 하나로 내보내며,
독립적인 시간 분할 정책은 소유하지 않는다. 단일 recovery artifact OOM이
재현되면 upload adapter가 아니라 exporter workflow에 명시적인 시간 window와
artifact receipt를 추가해야 한다.

Replay는 packed v3가 track별 record block을 저장할 수 있다는 점을 고려한다.
시간순 replay frame을 만들기 위해 전체 sample array를 메모리에 유지하지 않고,
preflight scanner가 version별 packet을 한 번 순회하며 canonical record를
operation-owned disk spool에 track/time index로 기록한다. Replay는 매 tick마다
해당 1초 window만 읽는다. Session finish/failure가 spool lifecycle을 소유하며,
spool write/read/decode 실패는 빈 frame이나 gap으로 바꾸지 않는다.

이 전환이 끝날 때까지 `bytes` 기반 기존 API와 disk-spool 기반 API를 자동으로
선택하는 fallback은 두지 않는다. Endpoint와 contract를 명시적으로 교체하고,
대용량 회귀 테스트로 peak resident memory가 파일 크기에 비례하지 않음을
검증한다.

## 구현 순서

1. ADR, header probe, version/track kind/error 계약과 v1/v2/v3 fixture를 추가한다.
2. Lab reader/replay를 canonical contract로 옮기고 numeric/string/gap 정책을
   고정한다.
3. TestKit과 Recorder Recovery writer를 공통 v3 writer로 합치고 downgrade
   rewrite를 제거할 준비를 한다.
4. bundled VitalServer index/preview parser를 header length 기반 parser로
   교체하고 v1/v2/v3 corpus로 검증한다.
5. downgrade rewrite를 삭제하고 모든 생성 artifact가 v3임을 검증한다.
6. upload preflight와 replay를 bounded-memory streaming으로 전환한다.
7. 실제 과거 파일과 생성 fixture를 포함한 compatibility corpus를 CI에서
   inspect, replay, rewrite round-trip 검증한다.

각 단계는 독립적으로 검증 가능한 focused change로 수행한다. Writer downgrade
삭제는 VitalServer parser 교체와 corpus 검증이 끝나기 전에는 수행하지 않는다.

## 완료 조건

- v1/v2/v3 fixture가 동일 canonical 의미로 inspect/replay된다.
- 1 Hz waveform과 `srate=0` numeric이 explicit type에 따라 올바르게 처리된다.
- string track 정책이 operation input과 결과에 드러난다.
- unknown future version과 unknown track type이 typed failure로 남는다.
- TestKit과 Recorder Recovery가 동일 writer로 v3 artifact를 생성한다.
- bundled VitalServer가 header length 10, 26, 27 및 확장 header를 색인한다.
- legacy header rewrite 함수와 고정 packet offset이 제거된다.
- 대용량 upload/replay가 파일 크기에 비례한 메모리 복사를 하지 않는다.
- troubleshooting 문서에 symptom, cause, fix direction, prevention이 기록된다.

## 대안

| 대안 | 기각 이유 |
| --- | --- |
| 최신 v3만 읽기 | 기존 설치와 보관 artifact를 재생할 수 없다 |
| 모든 계층에서 v1/v2/v3 분기 | 버전 지식과 fallback이 domain, UI, workflow에 퍼진다 |
| 기존 파일을 open 시 자동 변환 | 원본 변경과 decode 실패를 숨기고 operation 상태를 추론하게 된다 |
| 계속 legacy header로 downgrade 생성 | 최신 writer와 parser 간 불일치를 artifact 변조로 숨긴다 |
| track kind를 `srate`로 추론 | 1 Hz waveform과 `srate=0` numeric을 구분하지 못한다 |

## 결과

얻는 것:

- 과거 파일은 계속 읽으면서 내부 로직은 하나의 명시적 모델만 사용한다.
- format compatibility와 product behavior를 독립적으로 테스트할 수 있다.
- 손상과 미지원 상태가 재생 성공 또는 빈 데이터로 오인되지 않는다.
- writer와 bundled parser의 책임이 분리된다.

감수하는 것:

- v1/v2/v3 fixture와 version별 reader를 유지해야 한다.
- bundled VitalServer parser 교체 전까지 downgrade 제거를 미뤄야 한다.
- migration과 streaming은 별도 workflow와 상태 계약이 필요하다.

## 구현 현황

- Core canonical manifest와 v1/v2/v3 header probe가 구현되었다.
- 공통 `vitalserver-vitalfile` package가 version-dispatched reader와 canonical
  v3 writer를 소유한다.
- v1/v2 inspect는 record-aware time range를 사용하고, v3 inspect는
  header-only 경계를 사용한다.
- Lab과 TestKit은 canonical manifest의 explicit track kind만 소비한다.
- TestKit과 Recorder Recovery는 같은 v3 writer를 사용하며 legacy header
  rewrite는 제거되었다.
- bundled server index 및 webview asset은 runtime patch에서 version을
  검증하고 `10 + headerLength`를 packet offset으로 사용한다.
- bundled server index parser는 gzip chunk를 가로지르는 최대 선언 header를
  제한적으로 누적하며 v1/v2/v3와 65,535-byte 확장 header fixture를 통과한다.
- 실제 Docker image의 bundled index reader가 공통 writer의 canonical v3 artifact를
  색인하는 smoke validation을 통과했다.
- 실제 Docker image의 HTTP `/static/js/webview.js` 응답이 version 검증과 두
  parsing pass의 `10 + headerLength` offset을 포함함을 확인했다. 실제 파일의
  browser draw smoke는 release validation에 남아 있다.
- 공통 reader는 실제 wire packet으로 만든 대표 v1/v2/v3 corpus를 동일 canonical
  manifest와 sample 의미로 decode한다. 로컬 운영 corpus의 v3 파일 59개도 모두
  inspect했고, 서로 다른 세 recording group의 대표 파일을 bounded SQLite spool로
  replay했다. 이 과정에서 과거 DEVINFO의 선택적 company 문자열, 같은 device id의
  후속 정의 overwrite, 미정의 track record skip을 version reader의 명시적 wire
  규칙으로 추가했다. 운영 파일 자체를 저장소에 포함한 CI corpus 구성은 남아 있다.
- Guest upload preflight는 Core probe로 v1/v2/v3와 gzip 무결성을 검증하며 미래
  version과 절단 header를 VitalServer 호출 전에 거부한다. Core wheel도 Guest
  air-gap wheelhouse에 명시적으로 포함된다.
- Guest에서 VitalServer로 보내는 multipart는 source 크기만큼의 합성 body 없이
  chunk iterable로 전송한다.
- Guest Control upload ingress는 일반 JSON body reader를 사용하지 않고 request-owned
  임시 디렉터리에 part를 최대 64 KiB 단위로 staging한다. `Content-Length`, closing
  boundary, 최대 32개 part를 명시적으로 검증하고 성공·실패 후 임시 파일을
  정리한다. staging storage 실패는 `vitalFileUploadStagingFailed`, 절단 전송은
  `truncatedUpload`로 구분한다.
- 공통 Vital File packet scanner는 v1/v2/v3 packet stream을 최대 64 KiB waveform
  chunk로 전달한다. Product Lab 기본 replay adapter는 이를 operation-owned SQLite
  spool에 기록하고 one-second window만 읽는다. 한 frame은 최대 100,000 waveform
  samples로 제한하며 session pause/completion/replacement/start failure가 spool을
  명시적으로 제거한다.
- macOS native picker는 선택 파일을 security-scoped file descriptor로 전달하고,
  Guest gateway는 최대 64 KiB chunk로 request-owned multipart 파일을 만든 뒤
  `URLSession upload(fromFile:)`로 보낸다. Runtime Control ingress도 최대 64 KiB
  network read를 request-owned 파일에 기록하고, multipart part를 개별 파일로
  decode한 뒤 operation 종료 시 모두 제거한다.
- Guest는 검증된 파일을 VitalServer에 한 파일당 한 요청으로 직렬 전송한다.
  Guest→VitalServer multipart source는 최대 1 MiB chunk iterator이며 전체 파일
  또는 여러 파일을 하나의 request body로 합치지 않는다.
- Recorder Recovery exporter는 raw archive 전체를 `read_bytes()`로 복사하지 않고
  명시된 cursor byte window만 최대 64 KiB 단위로 읽는다. JSONL payload도 iterator로
  decode해 원본 archive bytes, 전체 UTF-8 text, 전체 decoded payload tuple이 동시에
  메모리에 남지 않게 한다. 하나의 선택 window를 시간별 artifact로 나누는 정책은
  아직 별도 workflow 과제로 남아 있다.

## 관련 결정

- ADR 0002의 Host/Guest 경계는 upload와 parser state owner에도 적용한다.
- ADR 0003의 component vocabulary는 writer/parser 변경 release 범위를 표현한다.
- ADR 0004의 update compatibility gate는 parser와 writer 배포 순서를 보호한다.
