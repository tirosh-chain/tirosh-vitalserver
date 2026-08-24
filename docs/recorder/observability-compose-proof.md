# Recorder observability Guest compose proof

이 증명은 이미 구현된 Recorder observability 제품 계약을 Guest compose
PostgreSQL 위에서 확인합니다. Helper/PWA UI, updater, root compose
`send_data` proof, 실제 설치된 Helper POST, 실제 Recorder canary,
설치된 Guest Control API는 범위가 아닙니다.

## 증명 범위

```text
certified NDJSON
  -> POST /api/v1/recorders/{vrcode}/observations|boot-events
  -> recorder-ingress 202 admitted receipt
  -> PostgreSQL recorder_observability.records / current
  -> GET /runtime/vitaldb/recorders/{vrcode}/observability
  -> GET .../observability/timeline
  -> GET .../observability/incidents
```

대상 compose는
`apps/vitalserver-macos-runtime/Support/Guest/compose.yaml`입니다.
기본 query owner는 `recorder-ingress`이고 기본 URL은
`http://127.0.0.1:18083`입니다. 이 URL은 recorder-ingress direct query이며
VM Guest Control API가 아닙니다.

recorder-ingress는 Guest Control과 같은 `/runtime/vitaldb/recorders/...`
path를 구현합니다. VM Guest Control systemd proxy(`:18330`)는 별도
프로세스입니다. 이 증명은 recorder-ingress가 Guest Control을 소유한다고
말하지 않습니다. `--query-owner guest-control`은 이미 떠 있는 Guest
Control endpoint의 `--query-base-url`을 운영자가 명시한 때만 사용합니다.

root `compose.yaml` send_data testkit stack에는 PostgreSQL이 없습니다. 그
stack을 이 증명으로 재사용하지 않습니다.

## Profile 제외

certified `profile-v1-valid.json`의 `identity.vrcode`는 `BRMH-OR1`로
고정되어 있습니다. unique `PROOF-*` path에 그 profile을 POST하면
`profile_vrcode_mismatch`로 quarantine됩니다. 이 증명은 profile을
POST하지 않습니다. observation만 있는 current projection 계약은
associated profile이 없으므로 `report.state=missing`입니다.

## 상태

아래 상태는 서로 다른 의미이며, HTTP 200/202만으로 성공으로 바꾸지 않습니다.

| 상태 | 의미 |
|---|---|
| 202 `admitted` + `accepted` | 줄이 PostgreSQL에 accepted로 영속화됨 |
| 202 `admitted` + `duplicates` | 같은 `(vrcode,eventId)` content의 멱등 재전송 |
| 202 `admitted` + `quarantined` | 줄 검증 실패가 영속화됨. 호환 성공이 아님 |
| 4xx | 요청 계약 실패. 줄을 수락하지 않음 |
| 503 | PostgreSQL 또는 admission/query 의존성 실패 |
| `loaded` | current/timeline/incident read model이 명시적으로 채워짐 |
| `notReported` / ingress `not_found` | 문서 전체 projection이 없음. 이 경우만 typed pending으로 재시도 |
| loaded 안의 nested `notReported` | 이미 loaded된 current 계약. 즉시 mismatch. pending이 아님 |
| `unavailable` / request timeout | query 의존성 실패. pending으로 재시도하지 않음 |
| `unsupported` | 명시적 unsupported expectation. 빈 성공이 아님 |
| incidents `loaded` + `[]` | 조회는 성공했고 incident history가 비어 있음 |

Detail 성공은 goldens에서 넘긴 기댓값과 같아야 합니다.

- `boot.state=started`
- `boot.orderingState=ordered`
- `boot.bootId` = observation golden `bootId`이자 boot-event golden `bootId` (둘 다 비어 있지 않고 같음)
- `evidenceHealth.state=healthy`
- `incidentState.state=reported`
- `report.state=missing` (profile 없음)

## Unique VRCODE와 cleanup

스크립트는 `PROOF-{UTC}-{suffix}` VRCODE만 POST합니다. 기존 장비 데이터를
덮어쓰지 않습니다. 증명은 이 VRCODE를 삭제하지 않습니다. 정리와 restore는
운영자 승인 명령입니다.

## 실행과 운영자 승인

```sh
make testkit/recorder-observability/compose-proof
```

이 target은 `--start-compose`로 Guest compose의 postgres,
postgres-migrate, redis, app, recorder-recovery, recorder-ingress를
기동하고 PostgreSQL을 변경합니다. query owner는 `recorder-ingress`입니다.
실행이 운영자 승인입니다. updater `field_proof_preflight`에는 연결하지
않습니다. 모든 health/admission/query HTTP는 `--request-timeout`(기본
10초, 양수 finite만 허용)으로 묶입니다. 0, 음수, NaN, inf는 invalid
입력이며 mutation 전에 실패합니다.

## 게시된 PostgreSQL host port

Guest compose는 production 기본 host port `15432`를 유지합니다. compose
`postgres` 서비스는 `127.0.0.1:${VITALSERVER_POSTGRES_BIND_PORT:-15432}:5432`
로 게시하며, 내부 container port는 항상 `5432`입니다. production에서
환경 변수를 설정하지 않으면 `15432`가 그대로 사용됩니다. 설치된
Guest systemd 서비스(`VITALSERVER_DATABASE_URL`)는 계속 `127.0.0.1:15432`를
바라봅니다.

이 증명은 host에 게시된 PostgreSQL port를 소비하지 않습니다. 그래서
proof는 고정 대체 port를 추측하지 않고 ephemeral Docker host port
(`--postgres-host-port 0`)를 명시적으로 선택합니다. 0은 Docker가
빈 host port를 자동 할당한다는 뜻입니다. 다른 프로세스가 점유한
`15432`와 충돌하지 않습니다. `--postgres-host-port`는 0..65535 정수만
허용하고, 범위 밖·정수가 아닌 값은 compose mutation 전에 invalid로
실패합니다. `0`은 `VITALSERVER_POSTGRES_BIND_PORT` 환경 변수로도 선택할
수 있으며, Make target은 항상 `--postgres-host-port 0`을 명시합니다.

## 설치된 제품에서 아직 증명하지 않는 것

- 실제 설치된 Helper의 Recorder observability POST
- 실제 Recorder/Observer canary
- VM Guest Control API systemd proxy (`:18330`)
- Helper/PWA 화면
- capacity, retention, Catalog
