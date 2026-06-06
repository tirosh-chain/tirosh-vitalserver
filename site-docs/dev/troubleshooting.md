# Dev Troubleshooting

이 문서는 장애를 조사하고 문서화하는 기준을 설명합니다. troubleshooting 문서는 단순
사후 기록이 아니라, 반복되는 failure pattern을 regression test와 설계 원칙으로
되돌리는 연결점입니다.

정식 troubleshooting index는 `docs/troubleshooting/index.md`와 `docs/troubleshooting/*.md`를
사용합니다. 이 문서는 공개 dev 문서에서 GitHub issue와 failure pattern 기록을
연결하는 기준을 정리합니다.

## Record Format

```text
Symptom:
Cause:
Fix direction:
Prevention:
Evidence:
Related tests:
```

## Failures Worth Recording

| 장애 유형 | 기록 이유 |
|---|---|
| contract failure | 상태 의미가 깨질 수 있음 |
| decode/read/permission failure | empty/default success로 숨기면 안 됨 |
| update failure | rollback, preserved state, changed artifact 범위가 중요 |
| VM lifecycle failure | host adapter와 guest service boundary가 섞일 수 있음 |
| observer failure | Health Check와 runtime read model에 영향 |
| stale state | old command output이나 log inference로 잘못 복구될 수 있음 |

## Investigation Rules

- 로그에서 state를 추측하지 않습니다.
- absence를 default success로 바꾸지 않습니다.
- Host가 Guest internals를 추측하지 않습니다.
- UI가 domain transition을 결정하지 않습니다.
- recurring failure는 troubleshooting 문서에 남깁니다.

## Existing Records

기존 failure pattern은 `docs/troubleshooting/index.md`와 `docs/troubleshooting/*.md`를
기준으로 확인합니다.

## GitHub Issue Linkage

외부 issue에서 반복 failure pattern이 확인되면, 공개 issue에는 개인정보와 현장
식별 정보를 제거한 재현 절차를 남깁니다. 원인, 예방 원칙, 관련 regression test는
troubleshooting 문서에 연결합니다.
