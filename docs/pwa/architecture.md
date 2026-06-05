# Runtime Control PWA Architecture

## Owner

PWA owns browser runtime control presentation. Runtime Control API owns runtime state, command execution, logs, observability, and host affordance contracts.

## Source of Truth

| 영역 | SoT | PWA 책임 |
|---|---|---|
| Runtime status | `GET /runtime/overview`, `GET /runtime/status` | status summary, health details, resource usage 표시 |
| Runtime events | `GET /runtime/events` | period/type/limit filter와 최신순 event list 표시 |
| Logs | `/host/logs/read`, `/host/logs/stream` | source/line/live controls, text rendering |
| Settings | `GET/PUT /runtime/settings` | validation, capability gating, apply confirmation |
| Operations | Runtime command routes | command availability, confirmation, result 표시 |
| VRecorder | `/vitaldb/recorders`, `/vitaldb/relationships` | recorder list/detail/activity chart 표시 |
| Bed | `/vitaldb/beds`, `/vitaldb/relationships` | bed list/detail/relation 표시 |
| TestKit | `/dev/testkit/*` | test-enabled build에서만 virtual recorder controls 표시 |
| Capability | `GET /runtime/capabilities` | route visibility와 command availability 결정 |

## Layering

```text
src/
  app/                         # bootstrap, routing, providers, app shell
  console/                     # RuntimeControlGateway port, React Query hooks, request builders
  domain/runtime-control/      # API contract validation, formatting, display policy
  infrastructure/console-api/  # fetch-based RuntimeControlApiClient adapter
  pages/                       # route-level Remote Console screens
  components/                  # app-wide reusable UI components
  config/                      # app settings and config provider
  styles/                      # Tailwind layers and global shell styles
  testing/                     # test utilities and fixtures
```

## Boundary Rules

- `domain/runtime-control`은 React와 Tailwind를 알면 안 됩니다.
- `console`은 `RuntimeControlGateway` port, query/mutation orchestration, request validation wrapper를 소유합니다.
- `infrastructure/console-api`는 `RuntimeControlGateway`를 구현하는 HTTP adapter입니다.
- `pages/*`는 page 조합과 page-local form state만 가집니다.
- `components`는 reusable presentation primitive를 소유합니다.
- `styles`는 token 기반 global layout과 legacy class compatibility만 둡니다.
- Runtime Control API response는 Zod schema에서 먼저 검증한 뒤 feature에 전달합니다.
- OpenAPI generated type은 compile-time contract이고, Zod schema는 runtime contract gate입니다.
- `app`은 concrete `RuntimeControlApiClient`를 만들고 `RuntimeControlGatewayProvider`로 주입하는 composition root입니다.
- `pages`와 `components`는 HTTP client를 직접 import하지 않습니다.

## Runtime Control Gateway

PWA application layer의 port 이름은 `RuntimeControlGateway`입니다.

| 코드 | 책임 |
|---|---|
| `src/console/runtimeControlGateway.ts` | Remote Console이 필요로 하는 Runtime Control read/command port |
| `src/console/runtimeControlGatewayContext.tsx` | React provider/hook boundary |
| `src/console/hooks.ts` | React Query query/mutation orchestration |
| `src/console/requestBuilders.ts` | command request body validation and construction |
| `src/infrastructure/console-api/runtimeControlApiClient.ts` | fetch, URL, token, response schema parsing |

이 이름은 의도적으로 `console`과 `runtime-control`을 나눕니다. `console`은 이 PWA의 application layer이고,
`runtime-control`은 Host/API가 제공하는 product contract입니다. HTTP 세부 구현은 infrastructure adapter에만
있어야 합니다.

## Contract Drift Guard

Runtime Control API 계약은 세 곳에서 동시에 관리됩니다.

| 위치 | 역할 |
|---|---|
| `docs/runtime/macos/runtime-control.openapi.json` | transport contract source |
| `src/domain/runtime-control/contracts/generated/runtime-control.ts` | OpenAPI generated TypeScript type |
| `src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts` | runtime response validation |

Schema는 OpenAPI type보다 보수적으로 동작할 수 있습니다. 특히 Swift contract가 non-optional로 제공하는
상태 의미는 generated type이 optional로 보이더라도 Zod schema에서 required로 검증합니다.

중요한 guard:

- `vitalDBObservationSnapshot.state=loaded`이면 `observation`이 있어야 합니다.
- `vitalDBObservationSnapshot.state=failed`이면 `readError`가 있어야 합니다.
- `vitalRecorder.source`는 항상 있어야 합니다.
- `vitalRecorder.source=vitalDBObservation`이면 observed metric과 `observedAt`이 있어야 합니다.
- `latestRecorder`가 있으면 `vrcode`와 `source`가 있어야 합니다.

## Capability Gating

PWA는 native Helper와 달리 host OS 권한을 직접 갖지 않습니다. 따라서 기능 노출은 `runtime/capabilities`를 기준으로 합니다.

- `canControlRuntime=false`: start/stop/repair/uninstall 같은 command를 비활성화합니다.
- `canUseTestTools=false`: Test 탭과 `/dev/testkit/*` 의존 UI를 숨깁니다.
- host file path 기반 기능은 PWA에서 직접 열지 않고 API가 제공하는 download/export endpoint 또는 native shell affordance로 분리합니다.

## Test Boundary

TestKit은 제품 runtime 검증을 위한 도구입니다. 제품 PWA의 기본 정보 구조를 오염시키지 않도록 아래 규칙을 지킵니다.

- TestKit UI는 test capability가 있을 때만 route에 추가합니다.
- TestKit API contract와 product runtime API contract를 혼합하지 않습니다.
- TestKit 상태는 runtime status/observability의 product state로 승격하지 않습니다.
- virtual VRecorder/bed 관리 기능은 Test 탭 안에서 닫힌 경계로 유지합니다.

## Verification

PWA 변경은 최소 아래 명령을 통과해야 합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-runtime-pwa run build
```

반응형 변경은 가능하면 아래 viewport에서 확인합니다.

- iPhone compact width
- iPad portrait/landscape
- desktop width
- wide desktop width
