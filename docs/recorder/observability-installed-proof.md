# Installed Recorder observability proof

이 증명은 **이미 설치된 제품**의 두 명시 endpoint를 대상으로 Recorder
observability certified NDJSON을 반복 검증합니다. Guest compose를 기동하지
않고(`--start-compose` 없음), endpoint를 log/file/부재에서 추론하지
않습니다. 설치된 endpoint를 명시하지 않으면 installed evidence를 주장하지
않습니다.

`make testkit/recorder-observability/compose-proof`(Guest compose PostgreSQL
mutation)와 별개입니다. 이 증명은 제품 데이터를 변경합니다(certified NDJSON
admission + projection). 운영자 mutation confirmation `YES`가 없으면
certified NDJSON을 POST하지 않습니다.

## 입력 계약

| 입력 | 필수 | 의미 |
|---|---|---|
| `RECORDER_ADMISSION_BASE_URL` | 필수 | 설치된 admission edge base URL (예: `http://127.0.0.1`) |
| `RECORDER_GUEST_CONTROL_BASE_URL` | 필수 | 설치된 Guest Control `/runtime/vitaldb` proxy base URL (예: `http://127.0.0.1:18330`) |
| `RECORDER_PROOF_CONFIRMATION` | 필수, 정확히 `YES` | operator mutation 승인 |

기본 URL fallback이 없습니다. 빈/미설정 입력은 `missing`, 비어 있지 않지만
`http(s)://` base URL이 아니거나 정확히 `YES`가 아닌 승인 입력은
`invalid`로 구분되어, 어떤 HTTP 요청도 POST도 보내기 전에 실패합니다.
승인 값과 endpoint 값은 오류 메시지에 노출하지 않습니다.

## 운영자 명령

설치된 제품이 admission edge(`:80`)와 Guest Control proxy(`:18330`)를
제공할 때:

```sh
RECORDER_ADMISSION_BASE_URL=http://127.0.0.1 \
RECORDER_GUEST_CONTROL_BASE_URL=http://127.0.0.1:18330 \
RECORDER_PROOF_CONFIRMATION=YES \
make testkit/recorder-observability/installed-proof
```

또는:

```sh
make testkit/recorder-observability/installed-proof \
  RECORDER_ADMISSION_BASE_URL=http://127.0.0.1 \
  RECORDER_GUEST_CONTROL_BASE_URL=http://127.0.0.1:18330 \
  RECORDER_PROOF_CONFIRMATION=YES
```

이 target은 기존 proof script를 `queryOwner=guest-control`로,
`--start-compose` 없이 실행합니다. `RECORDER_PROOF_CONFIRMATION`은 정확히
`YES`여야 합니다. `yes`/`YES `(공백 포함)/`1`은 `invalid`입니다.

## 증명 범위

```text
certified NDJSON
  -> POST {RECORDER_ADMISSION_BASE_URL}/api/v1/recorders/{vrcode}/observations|boot-events
  -> 설치된 admission 202 admitted receipt
  -> GET {RECORDER_GUEST_CONTROL_BASE_URL}/runtime/vitaldb/recorders/{vrcode}/observability
  -> GET .../observability/timeline
  -> GET .../observability/incidents
```

상태 의미와 `loaded`/`notReported`/`unavailable` 구분은
[Guest compose proof](observability-compose-proof.md)와 같습니다. 설치된
제품의 read path가 그 상태를 정확히 반환할 때만 성공입니다. admission
rejected/503, Guest Control `notReported`/`unavailable`/read failure,
missing/invalid 입력, confirmation blocked/invalid는 모두 성공으로
합쳐지지 않습니다.

## 이 증명이 증명하지 않는 것

- 실제 Recorder/Observer canary
- Helper가 POST한 실제 관측
- Helper/PWA UI 화면
- updater `field_proof_preflight`
- capacity, retention, Catalog

즉 이 증명은 certified NDJSON이 설치된 admission과 Guest Control
`/runtime/vitaldb` read path를 통과한다는 것만 증명합니다. Helper/PWA UI와
실제 Recorder/Observer canary는 별개 검증입니다.

## 출력

성공하면 structured proof JSON이 stdout으로 출력됩니다. `vrcode`, admission
count, detail/timeline/incidents, `queryOwner=guest-control`,
`queryBaseUrl`(명시된 Guest Control URL)을 함께 검토할 수 있습니다.
`proofScope`는 `guest-control-recorder-observability`입니다.
