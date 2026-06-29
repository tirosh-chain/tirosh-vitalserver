# PWA Testing

## Test Scope

PWA 테스트는 세 계층으로 나눕니다.

| 계층 | 목적 | 예 |
|---|---|---|
| Domain test | API contract, formatting, policy 검증 | Zod schema, settings validation, event filter |
| Component test | shared UI behavior 검증 | DataTable card/table rendering, command disabled state |
| Runtime smoke test | 실제 local server와 화면 동작 확인 | route visibility, status/log/event load |

## Required Commands

PWA 변경은 최소 아래 명령을 통과해야 합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-runtime-pwa run build
make pwa/verify-contract
make e2e/smoke
```

`make e2e/smoke`는 Runtime Control local HTTP server를 실제로 띄운 뒤 `/runtime/capabilities`, `/runtime/status`, `/runtime/settings`, `/runtime/events`, `/runtime/overview`와 missing-token failure를 검증합니다. 설치, update 적용, rollback 같은 destructive 작업은 수행하지 않습니다.

Runtime Control host file 권한은 로컬 audit으로 확인합니다.

```sh
make runtime/permission/audit
```

설치물이 반드시 있어야 하는 환경에서는 `RUNTIME_PERMISSION_AUDIT_ARGS=--require-install`을 추가합니다.

로컬에서 한 번에 확인할 때는 아래 묶음 명령을 사용합니다.

```sh
make e2e/local
```

반복 실행이 필요하면 아래처럼 횟수와 간격을 지정합니다. `E2E_LOOP_COUNT=0`은 실패하거나 중단할 때까지 계속 실행합니다.

```sh
E2E_LOOP_COUNT=5 E2E_LOOP_INTERVAL=10 make e2e/local/loop
```

## Contract Validation

Runtime Control API contract는 OpenAPI와 Zod schema 양쪽을 확인합니다.

- `generate:api`로 OpenAPI generated type을 갱신합니다.
- `make pwa/verify-contract`는 OpenAPI generated type을 임시 생성본과 비교하고, committed generated client가 최신이 아니면 실패합니다.
- API response는 domain schema에서 검증합니다.
- feature/page는 raw JSON에 직접 의존하지 않습니다.

## Component Testing Priorities

우선 테스트 대상은 아래 순서입니다.

1. Capability에 따른 route visibility
2. Settings validation policy
3. Runtime command confirm/disabled behavior
4. DataTable desktop/mobile presentation
5. Runtime events period/type/limit filtering
6. VRecorder activity chart input aggregation

## Responsive Verification

자동화가 없더라도 반응형 변경은 아래 viewport를 수동 확인합니다.

| Viewport | 확인 항목 |
|---|---|
| iPhone compact | horizontal scroll 없음, card list readable |
| iPhone large | toolbar wrap, action button spacing |
| iPad portrait | panel/header wrapping, table/card 전환 |
| iPad landscape | table scan, settings grid |
| 24-inch desktop | dashboard density, table readability |
| 32-inch desktop | content max-width, log/table line length |

## Local Smoke Test

Runtime Control API smoke:

```sh
make e2e/smoke
```

Runtime Control API smoke와 PWA check/test/build 묶음:

```sh
make e2e/local
```

Installed runtime permission audit:

```sh
make runtime/permission/audit
```

개발 서버:

```sh
npm --prefix apps/vitalserver-runtime-pwa run dev
```

확인 대상:

- `/` Status route renders without uncaught error
- `/logs` toolbar remains sticky while scrolling
- `/recorders` switches to card layout on mobile width
- `/settings` validation prevents invalid resource values
- `/test` is hidden when `canUseTestTools=false`

## Regression Notes

- PWA는 native-only host affordance를 직접 수행하지 않습니다.
- TestKit 기능은 dev/test capability가 없으면 route에서 사라져야 합니다.
- Runtime API가 unavailable일 때 page는 crash 대신 `ErrorState`를 보여야 합니다.
- Service worker는 runtime API stale cache를 보여주면 안 됩니다.
