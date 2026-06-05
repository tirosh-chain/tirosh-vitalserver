# Testing

이 문서는 Vital Server Helper 검증 범위를 정리합니다.

## 검증 범위

| 범위 | 목적 |
|---|---|
| unit test | domain policy, contract, parser, formatter 검증 |
| integration test | observer, testkit, API client, package plan 검증 |
| testkit smoke | simulated recorder와 VitalServer 연결 확인 |
| testkit load | 반복 `send_data` 처리와 저장 흐름 확인 |
| runtime chaos | permission, update, observability failure injection |
| Health Check scenario | VR observed/missing/stale, `.vital` file failure 상태 확인 |

## 기본 command

```sh
make check
make testkit-smoke
make testkit-load
make runtime-chaos
```

필요 시 package별 test를 직접 실행합니다.

```sh
uv run pytest packages/vitalserver-testkit/tests
uv run pytest packages/vitalserver-devtools/tests
uv run pytest apps/vitaldb-observer/tests
```

## Health Check 테스트 원칙

- missing, invalid, failed, stale, empty를 각각 재현합니다.
- read failure를 empty로 처리하지 않는지 확인합니다.
- permission failure와 decode failure를 구분합니다.
- UI가 domain state를 생성하지 않는지 확인합니다.
- observer/runtime read model이 source of truth인지 확인합니다.

## Release 전 확인

release 전에는 최소 아래를 확인합니다.

1. package build 성공
2. update bundle verify 성공
3. installed health 성공
4. testkit smoke 성공
5. 주요 troubleshooting case regression 없음
