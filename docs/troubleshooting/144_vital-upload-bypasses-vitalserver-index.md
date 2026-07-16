# Vital Files upload reports success but Replay list stays empty

> ID: TS-144
> Category: Runtime Control PWA / Product Lab
> Owner: Guest VitalServer file-library adapter
> Status: package verification pending

## Symptoms

- Swift/PWA가 여러 `.vital` 파일을 업로드했다고 표시하지만 Replay 선택기는 `-`로 남는다.
- Host shared Vital Files directory에는 파일이 생기지만 VitalServer My Files와
  `GET /api/filelist`에는 나타나지 않는다.
- 같은 화면을 refresh하거나 VM을 재시작해도 Replay 목록이 채워지지 않는다.
- API upload 경로로 전환한 설치본에서는 upload와 Replay 목록 조회가 모두
  `vitalFileLibraryUnavailable` 및 `<urlopen error [Errno 111] Connection refused>`로
  실패할 수 있다.
- 아직 한 번도 업로드하지 않은 library에서는 `GET /api/filelist`가 HTTP 404와 정확히
  `{"message":"No result found"}`를 반환해 첫 upload가 `vitalFileLibraryReadFailed`로
  막힐 수 있다.

## Cause

Host Platform Agent/native shell이 선택한 파일을 configured shared directory에 직접
복사했다. 이 경로는 VitalServer `POST /upload` parser와 file index 등록을 거치지 않는다.
목록 read도 Product Lab mount scan에 의존해 upload owner와 replay catalog owner가 달랐다.
UI의 복사 건수는 VitalServer가 파일을 수락하고 index했다는 증거가 아니었다.

API 전환 후 Guest file-library adapter가 VM 외부 ingress의 Docker publication인
`127.0.0.1:80`을 Guest host process의 loopback endpoint로 사용한 문제도 있었다.
설치 VM에서는 VM interface의 `:80`은 reachable이어도 Guest loopback `:80` listener가
존재하지 않는다. Guest 내부 VitalServer API 경계는 Compose가 명시적으로 publish한
recorder ingress `127.0.0.1:18083`이다.

VitalServer의 empty indexed library는 일반적인 REST missing-route 응답과 다르게
HTTP 404 `{"message":"No result found"}`로 명시된다. Guest adapter가 status code만으로
이를 dependency failure로 처리하면 import가 upload 전 conflict check를 위해 library를
읽는 시점에 막힌다. 이 문서는 authenticated exact response만 loaded empty library로
해석해야 하며, 다른 404, malformed body, authentication failure는 여전히 read failure라는
경계를 기록한다.

## Checks

VitalServer API 자체의 upload와 index를 확인한다.

```sh
curl -sS -X POST --data-urlencode 'id=admin' --data-urlencode 'pw=<password>' \
  http://127.0.0.1:18083/api/login
curl -sS 'http://127.0.0.1:18083/api/filelist?access_token=<token>&unixtimestamp=1' \
  --output /tmp/vital-filelist.json.gz
gzip -dc /tmp/vital-filelist.json.gz
```

Runtime Control 목록은 같은 index 의미를 보존해야 한다.

```sh
curl -sS -H 'X-Runtime-Control-Token: <token>' \
  http://127.0.0.1:<runtime-control-port>/runtime/lab/vital-files
```

## Actions

- Host/PWA가 선택한 bytes를 Runtime Control multipart upload로 전달한다.
- Guest library adapter가 전체 선택을 사전 검증한 뒤 각 파일을 VitalServer
  `POST /upload`의 `vitalfile` field로 보낸다. Guest adapter는 이를
  `http://127.0.0.1:18083` recorder ingress를 통해 호출한다.
- 응답이 HTTP 2xx이면서 본문이 정확히 `success`인지 확인한다.
- `GET /api/filelist`가 404 `{"message":"No result found"}`이면 authenticated empty
  library로 확인하고 첫 upload를 진행한다. 이외 404는 endpoint/dependency failure로
  진단한다.
- 업로드 후 인증된 `GET /api/filelist`를 다시 읽어 모든 파일의 index entry를 확인한다.
- Swift/PWA는 성공 뒤 `/runtime/lab/vital-files` query를 다시 읽고, 그 explicit loaded
  목록만 Replay 선택기에 표시한다.

## Prevention

- Host shared directory 직접 복사를 VitalServer upload 성공으로 취급하지 않는다.
- Replay catalog의 owner는 filesystem scan이 아니라 VitalServer `/api/filelist`다.
- `.vital` 확장자뿐 아니라 `<bed>_YYMMDD_HHMMSS.vital` indexable filename을 API 호출 전에
  검증한다.
- HTTP 200 error text, authentication failure, invalid gzip/JSON, missing index entry, partial
  multi-file completion을 empty/success로 변환하지 않는다.
- empty library는 VitalServer가 정한 exact 404 JSON document일 때만 empty collection으로
  변환한다. generic 404, body decode failure, or a different error document를 empty library로
  바꾸지 않는다.
- 연결 실패에는 실패한 VitalServer API URL을 포함해 외부 interface와 Guest loopback
  endpoint를 바로 구분할 수 있게 한다.
- VM interface reachability를 Guest loopback reachability로 추정하지 않는다. Guest host
  process가 사용하는 endpoint는 Compose의 explicit host publication과 같아야 한다.
- Swift gateway, Guest usecase, VitalServer adapter, PWA query invalidation을 각각 focused test로
  고정한다.

## Operational Notes

이전 버전이 shared directory에 직접 복사한 파일은 자동으로 indexed 상태로 승격하지 않는다.
원본 `.vital` 파일을 새 upload 경로로 다시 제출하고 VitalServer index에서 확인해야 한다.

## Related Cases

- `TS-084`: storage copy와 VitalServer My Files index의 차이
- `TS-130`: Vital Files upload/replay source와 UI 의미
