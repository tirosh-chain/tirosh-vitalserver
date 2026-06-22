# 084 TestKit vital upload가 My Files에 표시되지 않음

> ID: TS-084
> Category: TestKit / Upstream integration
> Owner: vitalserver-testkit
> Status: active

## Symptoms

VitalServer Helper의 Test 탭에서 Virtual Vital Recorder를 stop한 뒤 `.vital` 생성과 upload가 완료된 것처럼 표시됩니다.

하지만 VitalServer Web UI의 My Files에는 해당 `.vital` 파일이 나타나지 않습니다.

또는 My Files에는 파일과 track list가 나타나지만, preview graph가 비어 있거나 monitor view가 생체신호 group을 표시하지 못합니다.

또는 My Files preview가 `LOADING...`에서 멈추고 `.vital` graph로 전환되지 않습니다.

## Impact

운영자는 Test 탭의 `uploaded` 상태를 보고 VitalServer가 파일을 수신, 파싱, 인덱싱했다고 판단할 수 있습니다. 실제로는 HTTP upload request만 완료됐고 My Files index에는 들어가지 않았을 수 있으므로 end-to-end 검증이 거짓 성공으로 보입니다.

## Cause

원인은 여러 경계 의미가 섞인 것입니다.

첫 번째 원인은 upload 성공 판정입니다. upstream VitalServer의 `POST /upload`는 파일을 받은 뒤 `monitor.upload_vital(...)` 결과 text를 HTTP 200 body로 반환합니다. 정상 파싱과 저장이 끝나면 body는 `success`입니다. 파싱 실패나 저장 실패도 HTTP status만 보면 200일 수 있으므로, TestKit이 `2xx`만 보고 `uploaded`로 표시하면 실제 VitalServer 저장 성공을 보장하지 못합니다.

두 번째 원인은 filename prefix입니다. upstream My Files는 Redis `api:filelist:*` entry 중 filename에서 추출한 bed name이 로그인 사용자의 bed 목록에 포함되는 항목만 보여줍니다. `.vital` filename은 `bedname_yymmdd_hhmmss.vital` 형태여야 합니다. multi-bed TestKit session에서 `testkit-session_yymmdd_hhmmss.vital` 같은 synthetic prefix를 쓰면 VitalServer가 파일을 저장하거나 인덱싱해도 My Files 권한/bed 필터에서 제외될 수 있습니다. TestKit artifact filename은 request의 임의 label이 아니라 실제 VRecorder playback payload에 들어간 `roomname`을 prefix로 사용해야 합니다.

세 번째 원인은 `.vital` header compatibility입니다. Python `vitaldb` writer는 VITA v3 header에 `dtstart`, `dtend`, `packed` field를 포함합니다. vendored VitalServer의 JS parser는 header length를 사용해 건너뛰지 않고, legacy 20-byte header 뒤에서 바로 packet을 읽습니다. 이 mismatch가 있으면 VitalServer는 파일을 storage folder에 저장하고 HTTP body로 `success`를 반환할 수 있지만, Redis `api:filelist:dtstart`와 `api:filelist:dtend`에는 `0`을 기록합니다. My Files 기본 조회는 오늘 날짜 범위로 `api:filelist:dtstart`를 조회하므로 `dtstart=0` 파일은 화면에 나타나지 않습니다.

네 번째 원인은 `.vital` track info의 `montype` 손실입니다. TestKit recorder payload에는 `ECG_WAV`, `IABP_WAV`, `PLETH_WAV`, `CO2_WAV` 같은 Vital Recorder monitor type이 들어 있지만, Python `vitaldb.add_track(...)` API는 `montype` parameter를 받지 않습니다. TestKit exporter가 반환된 Track 객체에 legacy VitalServer numeric montype을 명시적으로 세팅하지 않으면 VitalServer Web UI는 파일과 track name은 보여도 monitor-style graph grouping을 만들 수 없습니다.

다섯 번째 원인은 My Files preview URL 생성입니다. upstream `/webview` route는 `http://` + `db.get_websocket_host()` + `/vital_files/...` 형태로 `.vital` fetch URL을 만듭니다. wrapper runtime이 Socket.IO same-origin을 위해 `get_websocket_host()`를 `/`로 반환하면 webview HTML에는 `http:////vital_files//...` 같은 invalid URL이 들어갑니다. 이 경우 browser fetch가 `.vital` payload에 도달하지 못하고 preview가 `LOADING...`에 머뭅니다.

## Checks

TestKit session API에서 upload result를 먼저 확인합니다.

```sh
curl -s http://127.0.0.1:<testkit-port>/sessions/<session-id> \
  | jq '.vital.uploadStatus, .vital.uploadResult.responseText, .vital.uploadError'
```

`responseText`가 정확히 `success`가 아니면 VitalServer upload는 성공으로 취급하면 안 됩니다.

생성된 artifact filename도 확인합니다.

```sh
curl -s http://127.0.0.1:<testkit-port>/sessions/<session-id> \
  | jq '.vital.artifact.filename, .bedRoomNames'
```

filename prefix가 실제 TestKit bed room name과 일치해야 My Files에서 보일 수 있습니다.

VitalServer filelist API로 server-side index time도 확인합니다.

```sh
curl -sS -X POST -d 'id=admin&pw=admin' \
  http://127.0.0.1/api/login

curl -sS \
  'http://127.0.0.1/api/filelist?access_token=<token>&unixtimestamp=1' \
  -o /tmp/vital-filelist.gz

gzip -dc /tmp/vital-filelist.gz
```

응답의 `dtstart`와 `dtend`가 `0`이면 My Files의 기본 날짜 필터에 표시되지 않습니다. 이 경우 파일이 storage folder에 있더라도 VitalServer index time이 비어 있는 상태입니다.

My Files에 파일은 보이지만 graph가 비어 있으면 생성된 `.vital`의 track info에 device-bound track, non-zero record dt, legacy numeric `montype`이 모두 들어 있는지 확인해야 합니다. TestKit integration test의 `legacy_vitalserver_webview_preview(...)` helper는 vendored webview reader와 같은 packet 구조를 검사합니다.

Preview가 `LOADING...`에서 멈추면 `/webview` HTML이 내려주는 `path` 값을 확인합니다.

```sh
curl -sS 'http://127.0.0.1:<vitalserver-port>/webview?filename=<filename>.vital' \
  | grep -o 'var path = "[^"]*"'
```

`http:////vital_files//...`처럼 host가 빠진 URL이면 wrapper runtime의 webview path 보정이 적용되지 않은 image입니다. 정상은 same-origin `/vital_files/<bed>/<yyyy>/<yymmdd>/<filename>.vital`입니다.

실제 VitalServer를 대상으로 upload와 filelist visibility를 검증하려면 아래 opt-in integration test를 실행합니다.

```sh
VITALSERVER_TEST_URL=http://<vitalserver-host> \
VITALSERVER_TEST_USER=admin \
VITALSERVER_TEST_PASSWORD=admin \
uv run pytest \
  packages/vitalserver-testkit/tests/integration/adapters/test_vital_artifact.py \
  -k live_vitalserver
```

## Actions

제품 수정 방향:

1. TestKit session uploader는 `POST /upload` 응답이 HTTP 2xx이고 body가 정확히 `success`일 때만 `uploaded`로 표시합니다.
2. 그 외 body는 `upload-failed` 상태와 `uploadError`로 보존합니다.
3. TestKit session `.vital` artifact filename은 synthetic session label이 아니라 실제 VRecorder playback `roomname` prefix를 사용합니다.
4. 자동 생성 bed room name은 같은 prefix를 여러 번 써도 충돌하지 않도록 `prefixxxxx` 형식의 짧은 random suffix를 붙입니다.
5. TestKit exporter는 Python `vitaldb`가 쓴 VITA v3 header를 vendored VitalServer legacy parser가 packet offset을 맞출 수 있는 header로 재작성합니다.
6. TestKit exporter는 recorder payload의 `montype`을 legacy VitalServer numeric monitor type id로 보존해 `.vital` track info에 기록합니다.
7. VitalServer wrapper runtime은 My Files `webview` render의 `.vital` fetch path를 same-origin `/vital_files/...` 경로로 보정합니다.
8. integration test는 virtual recorder session의 stop 이후 `.vital` 생성, multipart upload, VitalServer식 `success` body, live VitalServer filelist의 non-zero `dtstart/dtend`, webview-compatible device/track/record/montype 확인까지 포함해야 합니다.

## Prevention

외부 시스템의 domain success를 HTTP transport success와 같은 의미로 쓰지 않습니다.

VitalServer upload contract는 다음처럼 분리해서 다룹니다.

- Transport success: HTTP request/response가 완료됨
- Upstream parse/store success: response body가 `success`
- My Files visibility precondition: filename prefix가 실제 VRecorder playback room name
- My Files date visibility precondition: VitalServer Redis filelist index의 `dtstart`가 조회 날짜 범위 안에 있음
- My Files graph visibility precondition: `.vital` track이 named device에 연결되어 있고, record dt가 non-zero이며, known 생체신호 track은 legacy numeric `montype`을 보존함
- My Files preview fetch precondition: `/webview`가 browser가 접근 가능한 `/vital_files/...` URL을 내려줌

TestKit UI/API는 이 의미들을 섞지 않고, 실패 body와 artifact filename을 그대로 노출해야 합니다.

## Related Cases

- `TS-039`: AGENTS.md 상태/실패 fallback 감사
- `TS-081`: Upstream VitalServer contract verification failure

## Follow-up

- 2026-06-17: Helper Test 탭이 `uploaded`를 표시하지만 My Files가 비어 있는 증상을 등록했습니다.
- 2026-06-17: upstream `/upload`가 HTTP 200 body text로 parser/store 결과를 반환하며, 정상 성공 body는 `success`임을 확인했습니다.
- 2026-06-17: My Files가 filename-derived bed name을 로그인 사용자의 bed 목록과 비교해 필터링함을 확인했습니다.
- 2026-06-17: TestKit `.vital` artifact filename을 실제 playback `roomname` 기반으로 만들고, 자동 bed 생성은 `prefixxxxx` 형식의 충돌 방지 suffix를 사용하도록 수정했습니다.
- 2026-06-17: storage folder에는 파일이 존재하지만 VitalServer filelist index의 `dtstart/dtend`가 `0`인 경우 My Files 기본 날짜 조회에 표시되지 않음을 확인했습니다.
- 2026-06-17: Python `vitaldb` VITA v3 header와 vendored VitalServer JS legacy parser의 packet offset mismatch를 확인하고, TestKit exporter가 legacy-compatible header로 재작성하도록 수정했습니다.
- 2026-06-17: My Files에 파일과 track list는 보이지만 graph가 비어 있는 증상에서 Python `vitaldb.add_track(...)`이 `montype`을 받지 않아 generated `.vital` track info의 monitor type이 `0`으로 저장되는 문제를 확인했습니다. TestKit exporter가 returned Track 객체의 `montype`을 legacy VitalServer numeric id로 명시 세팅하고, integration test가 webview-compatible device/track/record/montype을 확인하도록 보강했습니다.
- 2026-06-17: My Files preview가 `LOADING...`에 머무는 증상에서 `/webview`가 `http:////vital_files//...` invalid URL을 내려주는 문제를 확인했습니다. wrapper runtime이 `webview` render 시 `.vital` fetch path를 same-origin `/vital_files/...`로 보정하도록 수정했습니다.
