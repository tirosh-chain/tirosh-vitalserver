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
```

## Contract Validation

Runtime Control API contract는 OpenAPI와 Zod schema 양쪽을 확인합니다.

- `generate:api`로 OpenAPI generated type을 갱신합니다.
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
