# Vital Files upload가 대용량 선택에서 메모리 압력 또는 OOM을 유발함

> ID: TS-169
> Category: Runtime Control PWA / Guest containers / Vital Files
> Owner: macOS runtime / guest control
> Status: fixed, operational verification pending

## Symptom

여러 개 또는 큰 `.vital` 파일을 업로드할 때 Helper, Guest Control 또는
VitalServer app의 메모리가 파일 크기에 비례해 늘거나 process/container가
종료된다. 선택한 파일 수와 전체 크기가 커질수록 증상이 빨리 나타날 수 있다.

## Cause

서로 다른 두 경계를 구분해야 한다.

1. Host 또는 Guest가 파일/multipart 전체를 `Data`/`bytes`로 만들면 같은 내용이
   원본 파일, 합성 multipart, HTTP client buffer로 동시에 존재한다.
2. 여러 파일을 VitalServer에 한 요청 또는 동시 요청으로 보내면 upstream parser의
   in-flight 작업이 겹친다.

과거 upload 구현은 선택 파일을 순회해 `파일 1개 = POST /upload 1회`로 보냈다.
2026-06-18의 manual upload crash 수정도 multipart를 임시 파일로 만든 뒤
`URLSession upload(fromFile:)`로 전송하도록 바꿨다. 별도의 VitalServer app OOM
대응은 recorder의 realtime `send_data` burst에 적용된 spool/replay flow control이며,
`.vital` 한 파일을 임의 byte 범위로 나누는 upload protocol은 아니었다.

## Fix direction

- Native picker는 전체 파일을 `Data(contentsOf:)`로 읽지 않고 file descriptor와
  명시적 size를 전달한다.
- Runtime Control 및 Guest Control ingress는 upload 전용 request body를
  제한된 chunk로 임시 파일에 기록하고, 완료/실패 시 operation owner가 제거한다.
- Guest preflight는 gzip과 Vital header를 bounded read로 끝까지 검증한다.
- Guest→VitalServer는 각 파일을 선택 순서대로 독립 `/upload` 요청으로 보내고,
  앞 요청 응답 후 다음 요청을 시작한다.
- 각 요청은 multipart prefix, file chunk, suffix를 stream하며 정확한
  `Content-Length`와 실제 source size를 비교한다.
- Recorder Recovery는 raw archive 전체가 아니라 명시된 cursor byte window만
  64 KiB 단위로 읽고 JSONL payload를 순차 decode한다. Decode한 track record는
  operation-owned SQLite spool에 적재하고 source byte window와 vrcode마다 완전한 `.vital` 파일 하나로
  materialize한다. 긴 녹화도 임의 시간 경계로 waveform이나 artifact를 나누지 않는다.

단일 완전한 `.vital` 파일의 parse만으로 VitalServer app이 OOM이 되는 경우에는
upload transport가 파일을 임의 byte로 잘라서는 안 됩니다. 관측된 장시간 `.vital`도 약 20 MiB 수준이므로
Recovery artifact 역시 시간 기준으로 나누지 않습니다. 단일 파일도 OOM을 일으킨다면 VitalServer가
소유하는 streaming parser 또는 resumable-upload 계약이 별도로 필요합니다.

VitalRecorder의 기존 source-side 경계는 `CUT_HOURLY=1`이다. 이 설정은 recorder가
매시간 새 완전한 `.vital` 파일을 생성하게 하며, 이미 생성된 파일의 byte-range
upload를 의미하지 않는다. Cold-path recovery artifact도 source byte window와 vrcode별 단일 파일이며,
native Recorder 파일과는 origin/producer/receipt로 구분합니다.

## Verification

1. 3 MiB 이상 Host→Runtime Control upload가 성공하고 request staging directory가
   응답 후 비어 있다.
2. Host→Guest gateway가 source file을 file-backed multipart로 보내고 임시 body를
   성공/실패 후 제거한다.
3. 두 파일 import에서 VitalServer `/upload` request가 정확히 두 개이며 각 body에
   `vitalfile` part 하나만 있다.
4. Guest outbound body가 `bytes`가 아닌 bounded iterable이고 선언/실제 크기
   mismatch가 명시적 실패다.
5. 이틀 이상의 raw archive export에서 source read가 bounded이고 vrcode별 artifact가 하나이며 임시
   spool directory가 성공/실패 후 제거된다.
6. 운영 soak에서는 Helper RSS, Guest Control RSS, VitalServer app
   `oomKilled`/`restartCount`를 서로 다른 owner evidence로 기록한다.

## Prevention

Batch selection, HTTP request, Vital File artifact를 같은 “multipart 분할”로 부르지
않는다. 계약에는 각 경계의 단위를 명시한다: Host batch는 여러 part, Guest
staging은 파일별 artifact, VitalServer upload는 한 요청에 완전한 파일 하나다.
Streaming은 transient memory copy를 줄이는 수단이고, 단일 파일 parser의 peak
memory를 자동으로 제한하는 기능은 아니다.

## References

- [VitalRecorder User Manual](https://vitaldb.net/docs/?documentId=VitalRecorder%2FUser_Manual.md):
  `CUT_HOURLY=1`은 파일을 매시간 분리한다.
- [Vital File Format](https://vitaldb.net/docs/?documentId=VitalRecorder%2FVital_File_Format.md&format=pdf):
  packet 경계와 완전한 Vital File 구조를 정의한다.
- [VitalDB Web API](https://vitaldb.net/docs/?documentId=API%2FWeb_API.md&format=pdf):
  `/upload`는 `vitalfile` 파일 하나를 입력으로 받는다.

## Related cases

- `TS-085`: proxy request body limit으로 413이 발생함
- `TS-090`: realtime recorder burst에서 VitalServer app OOM evidence를 보존함
- `TS-144`: upload와 VitalServer index owner 경계를 우회함
