# Dev Troubleshooting

이 문서는 개발/운영 지원자가 내부 장애를 조사하고 문서화하는 기준을 설명합니다.

정식 troubleshooting index는 `docs/troubleshooting/index.md`와 `docs/troubleshooting/*.md`를
사용합니다. 이 초안은 Vital Server Helper release/dev 문서군에 맞춘 작성 기준을
정리합니다.

## 작성 형식

```text
Symptom:
Cause:
Fix direction:
Prevention:
Evidence:
Related tests:
```

## 기록해야 하는 장애

| 장애 유형 | 기록 이유 |
|---|---|
| contract failure | 상태 의미가 깨질 수 있음 |
| decode/read/permission failure | empty/default success로 숨기면 안 됨 |
| update failure | rollback, preserved state, changed artifact 범위가 중요 |
| VM lifecycle failure | host adapter와 guest service boundary가 섞일 수 있음 |
| observer failure | Health Check와 runtime read model에 영향 |
| stale state | old command output이나 log inference로 잘못 복구될 수 있음 |

## 조사 원칙

- 로그에서 state를 추측하지 않습니다.
- absence를 default success로 바꾸지 않습니다.
- Host가 Guest internals를 추측하지 않습니다.
- UI가 domain transition을 결정하지 않습니다.
- recurring failure는 troubleshooting 문서에 남깁니다.

## 기존 문서 연결

기존 failure pattern은 `docs/troubleshooting/index.md`와 `docs/troubleshooting/*.md`를
기준으로 확인합니다.
