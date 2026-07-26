# Vital Files upload accepts one path and replay does not use the selected file

> ID: TS-130
> Category: Runtime Control PWA / Product Lab
> Owner: Runtime Control Vital Files import and Product Lab replay boundaries
> Status: resolved

## Symptoms

- 기존 Lab 화면에서 Host 파일 하나를 골라도 Upload/Replay button이 동작하지 않는다.
- Upload request가 Host에서 고른 bytes가 아니라 Guest mount path 문자열 하나를 요구한다.
- 여러 `.vital` 파일을 한 번에 library에 넣을 수 없다.
- `.txt`처럼 `.vital`이 아닌 파일도 upload flow에 들어갈 수 있다.
- Replay를 실행해도 선택한 `.vital`의 packet이 아니라 고정된 synthetic signal만 전송된다.
- macOS Helper에서 upload 성공 건수가 표시되지만 replay 파일 선택기는 계속 `-`로 남는다.

## Impact

Upload와 Replay의 source가 섞여 사용자가 선택한 파일과 실제 전송 데이터가 달라질 수
있었다. 잘못된 확장자나 batch 일부만 반영되면 library 상태도 사용자가 요청한 operation과
달라질 수 있었다.

## Cause

기존 public Upload 계약은 browser/Host file import가 아니라 이미 Guest에 mount된 한 경로를
Product Lab이 VitalServer `/upload`로 다시 보내는 command였다. Replay engine도 그 경로의
`.vital` content를 읽지 않고 고정 HR/SpO2 payload를 생성했다. UI section 하나가 이 서로
다른 동작을 함께 표현해 operation owner와 source가 드러나지 않았다.

macOS Helper는 한때 native file import가 끝난 뒤 session, bed, recorder read model만 다시
읽고 Vital Files library read model은 갱신하지 않았다. 이후 직접 shared storage로 복사하는
경로까지 생겨, 파일이 있어도 VitalServer index에는 없고 선택기는 empty snapshot을 표시했다.

## Checks

OpenAPI에서 upload media type과 replay source를 확인한다.

```sh
rg -n 'runtime/lab/vital-files/(upload|replay)|multipart/form-data' \
  docs/runtime/runtime-control.openapi.json
```

Upload 후 `GET /runtime/lab/vital-files`가 각 파일의 `relativePath`를 제공하는지 확인한다.
Invalid batch를 보낼 때는 하나의 valid file도 library에 생기지 않아야 한다.

## Actions

- 최신 Helper/PWA/Platform Agent와 Guest Tools를 함께 설치한다.
- `Vital Files > Upload to library`에서 N개 `.vital` 파일을 선택해 upload한다.
- `Vital Files > Replay uploaded file`에서 library 목록의 한 파일을 선택하고 resource와
  repeat policy를 지정한다.
- 기존 파일명과 충돌하면 기존 파일을 암묵적으로 덮어쓰지 말고 파일명 또는 library
  content를 명시적으로 정리한 뒤 batch 전체를 다시 upload한다.

## Prevention

- OpenAPI upload contract는 multipart `files[]`이며 JSON Host/Guest path를 받지 않는다.
- PWA와 Swift native shell은 파일 선택과 byte 전달만 담당한다. Guest library adapter가
  VitalServer 파일명 규칙과 index 충돌을 검증하고 `POST /upload`를 호출한다.
- 업로드 완료는 HTTP 2xx만으로 판정하지 않는다. 본문 `success`와 후속
  `GET /api/filelist` index entry를 모두 확인한다.
- 여러 파일 중 일부만 VitalServer가 수락한 경우 partial completion을 명시적으로 실패
  보고하며, 이미 반영된 파일을 rollback했다고 추정하지 않는다.
- Replay request는 uploaded `relativePath`, resource selection, repeat policy를 필수로 가진다.
- Product Lab replay source는 실제 `vitaldb.VitalFile` track을 읽어 packet payload를 만든다.
- Native upload 완료 후 `GET /runtime/lab/vital-files`를 다시 읽고, 반환된 loaded 목록에서만
  replay 선택을 갱신한다. Upload 성공 문구를 library state로 사용하지 않는다.

## Operational Notes

Upload 실패를 빈 library나 zero imported files 성공으로 해석하지 않는다. 기존 destination은
자동 overwrite하지 않는다. Library가 missing/unreadable이면 먼저 configured storage 상태를
복구하고 같은 request를 다시 수행한다.

## Related Cases

- `TS-125`: Product Lab session collection과 recorder control이 보이지 않음
- `TS-128`: 실제 Vital Recorder read model과 packet graph가 비어 있음
- `TS-144`: Host shared storage 직접 복사 때문에 VitalServer index와 replay 목록이 비어 있음
