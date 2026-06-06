# Testing

이 문서는 Vital Server Helper의 검증 범위를 정리합니다. 검증의 목적은 단순히 test
수를 늘리는 것이 아니라, 상태 의미와 layer 경계가 변경 중에도 유지되는지 확인하는
것입니다.

## Verification Scope

| 범위 | 목적 |
|---|---|
| unit test | domain policy, contract, parser, formatter 검증 |
| integration test | observer, testkit, API client, package plan 검증 |
| testkit smoke | simulated recorder와 Vital Server 연결 확인 |
| testkit load | 반복 `send_data` 처리와 저장 흐름 확인 |
| runtime chaos | permission, update, observability failure injection |
| Health Check scenario | VR observed/missing/stale, `.vital` file failure 상태 확인 |

## Layer Test Rules

테스트의 우선순위는 happy path보다 state meaning과 failure boundary 보존입니다. 새 동작을
추가하거나 책임을 이동할 때는 정상 흐름 1개보다 missing, invalid, permission failure,
decode failure, dependency failure, stale, zero, empty를 분리해서 검증하는 테스트가 더
중요합니다.

| Layer | 반드시 검증할 것 | 실패/chaos 기준 |
|---|---|---|
| `Contracts` | 문서 decode/encode, enum case, explicit result shape | missing/invalid/failed/stale/zero/empty가 서로 바뀌지 않아야 함 |
| `Domain` | transition, guard, invariant | 불완전 입력은 전이 금지 또는 명시 failure decision으로 유지 |
| `Application/UseCases` | stateless decision, command/effect/event 계산 | dependency 실패를 empty/default success로 바꾸지 않아야 함 |
| `Workflow` | 진행 순서, progress, wait/retry loop, status persistence | failed/best-effort/degraded 결과가 status/event에 명시적으로 남아야 함 |
| `Adapters/Outbound` | filesystem/process/network/repository read-write | permission/decode/dependency failure를 typed result로 보고해야 함 |
| `Bootstrap` | dependency graph와 allowed composition만 존재 | process/filesystem/network/JSON 실행 책임이 들어오면 architecture test가 실패해야 함 |
| `Hosts` | process boundary와 host-owned effect closure | host state read/write 실패를 inward layer에 숨기지 않아야 함 |

Architecture boundary test는 regression guard입니다. 새 파일이나 새 target을 추가할 때는
해당 책임이 어느 layer에 속하는지 먼저 정하고, import direction, state ownership,
fallback 가능 여부를 함께 테스트합니다.

## Commands

```sh
make dev/check
make testkit/smoke
make testkit/load
make runtime/chaos
```

필요 시 package별 test를 직접 실행합니다.

```sh
uv run pytest packages/vitalserver-testkit/tests
uv run pytest packages/vitalserver-devtools/tests
uv run pytest packages/vitalserver-guest-tools/tests
uv run pytest apps/vitaldb-observer/tests
```

PWA와 audit proxy는 각각 Node 기반 검증을 실행합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-audit-proxy run check
npm --prefix apps/vitalserver-audit-proxy test
```

## Health Check Test Rules

- missing, invalid, failed, stale, empty를 각각 재현합니다.
- read failure를 empty로 처리하지 않는지 확인합니다.
- permission failure와 decode failure를 구분합니다.
- UI가 domain state를 생성하지 않는지 확인합니다.
- observer/runtime read model이 source of truth인지 확인합니다.

## Before Release

release 전에는 최소 아래를 확인합니다.

1. package build 성공
2. update bundle verify 성공
3. installed health 성공
4. testkit smoke 성공
5. 주요 troubleshooting case regression 없음

GitHub issue나 pull request에서 검증 실패를 보고할 때는 command, 환경, 실패 로그,
기대 결과를 함께 적습니다.
