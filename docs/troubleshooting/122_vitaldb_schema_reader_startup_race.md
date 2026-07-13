# TS-122: VitalDB read model schema startup race

## Symptom

새 설치 직후 Helper의 Guest product services가 generic `RuntimeGuestControlHTTPGatewayError error 3`으로 표시되고 Recorder/Bed 상태가 `Not reported`로 남습니다. Postgres log에는 `relation "vitaldb_observation_snapshots" does not exist`가 주기적으로 반복됩니다.

## Cause

Guest Control reader는 시작됐지만 VitalDB schema 생성은 observation writer의 첫 successful write에만 묶여 있었습니다. Observation 수집이 아직 unavailable이면 writer가 schema를 만들지 않으므로 reader가 존재하지 않는 table을 계속 조회했습니다. Swift gateway error도 `LocalizedError`를 제공하지 않아 typed transport/decode 원인이 Cocoa 기본 문자열로 손실됐습니다.

## Fix direction

Runtime observation writer lifecycle이 observation document 유무와 관계없이 SQLAlchemy metadata migration을 먼저 실행합니다. Bootstrap은 ordered Compose가 Postgres readiness를 확인한 뒤 초기 observation과 schema migration을 실행합니다. Guest Control core route는 Product Postgres 시작에 결합하지 않습니다. VitalDB와 Product Lab persistence는 domain class, ORM record, mapper, repository로 분리하고 운영 Postgres engine을 명시 database URL로 제공합니다. Gateway error는 typed description을 `localizedDescription`으로 그대로 노출합니다.

## Prevention

Schema 준비는 writer의 우연한 첫 successful observation side effect에 맡기지 않습니다. 동시에 Postgres readiness 이전에 migration을 호출하지 않습니다. Bootstrap의 ordered Compose completion을 명시 lifecycle gate로 사용하고, 이후 writer dependency failure는 typed failure로 유지합니다. Reader availability 이전의 명시 lifecycle gate가 schema를 소유해야 하며, missing schema와 empty read model을 서로 다른 실패로 보존합니다. Repository portability는 SQLite contract test로 검증하지만 운영 failure를 SQLite fallback success로 바꾸지 않습니다.
