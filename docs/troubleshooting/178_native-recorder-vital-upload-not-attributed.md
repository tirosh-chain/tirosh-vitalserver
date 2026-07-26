# TS-178: Native Recorder Vital upload is not attributed to a Recorder

## Metadata

- Category: Recorder streaming / Runtime Control PWA
- Owner: Recorder ingress
- Status: active

## Symptom

VitalServer가 `.vital` upload를 받아 My Files에 표시하지만 Helper의 Recorder
Details `Vital files`에는 파일이 나타나지 않습니다. 또는 source state가
`partiallyLoaded`/`readFailed`이고 native upload가 귀속되지 않은 수로 남습니다.

## Cause

기존 VitalServer `/upload` multipart는 `vitalfile`만 제공하며 authoritative
Recorder identity 또는 bed assignment를 제공하지 않습니다. 파일명이
`bedname_yymmdd_hhmmss.vital` 형식이어도 filename은 identity 계약이 아닙니다.

추적 요청에는 다음 explicit metadata가 모두 필요합니다.

- `X-Vital-Upload-Id`
- `X-Vital-Bed-Name`
- `X-Vital-Filename`
- `X-Vital-File-Size`

`X-Vital-Recorder-Code`가 없으면 upload 수신 시각에 해당 bedName을 소유한
assignment가 정확히 하나여야 합니다. relationship read 실패, assignment 부재,
동일 시각의 복수 후보는 귀속 실패이며 임의 Recorder로 진행하지 않습니다.

## Verification

```bash
curl -sS http://127.0.0.1:18083/recorder-ingress/vital-files/uploads
curl -sS http://127.0.0.1:18081/runtime/vitaldb/recorders/VR_CODE/vital-files
```

첫 응답에서 upload state와 `bedName`, `declaredVrcode`, failure를 확인합니다.
두 번째 응답에서는 `sources.nativeUpload`, `sources.coldPathRecovery`,
`unattributedCount`, `readError`를 각각 확인합니다.

## Fix direction

Recorder uploader가 하나의 완전한 multipart request를 streaming하면서 위 header를
제공하도록 수정합니다. 가능하면 Recorder가 알고 있는 vrcode도
`X-Vital-Recorder-Code`로 선언합니다. bedName만 제공하는 경우에는 upload 전후의
Guest relationship assignment가 수신 시각을 정확히 포함하는지 확인합니다.

이미 header 없이 완료된 legacy upload는 filename으로 backfill하지 않습니다.
재전송이 필요하면 새 upload ID로 tracked upload를 수행합니다.
추적 header를 보낸 요청에서 `native_upload_tracking_unavailable`이 반환되면
일반 upload로 재시도하지 말고 Recorder ingress의 tracking owner 구성과 state
volume을 복구한 뒤 새 upload ID로 전송합니다.

## Prevention

- Upload acceptance와 VitalServer file-index proof를 별도 상태로 유지합니다.
- bedName/vrcode를 filename에서 파싱하지 않습니다.
- missing, ambiguous, relationship read failure를 unattributed success로 바꾸지 않습니다.
- Native Recorder upload, cold-path recovery, Product Lab file의 origin을 섞지 않습니다.
- 긴 `.vital` 파일을 추적 목적으로 시간 segment로 나누지 않습니다.
