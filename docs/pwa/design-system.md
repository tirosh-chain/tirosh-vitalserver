# PWA Design System

## Goal

PWA는 Tailwind를 직접적인 화면 구현 도구로만 쓰지 않습니다. Tailwind는 design token과 responsive utility를 제공하고, 제품 UI의 SoT는 shared UI component입니다.

## Styling Ownership

| 계층 | 책임 |
|---|---|
| `tailwind.config.cjs` | color, radius, font, breakpoint token |
| `shared/styles/global.css` | base reset, app shell, 기존 class compatibility, responsive layout rules |
| `shared/ui/*` | button, panel, table/card, badge, metric, confirm interaction 같은 reusable primitive |
| `features/*` | 화면 조합, query state, feature-specific local state |

## Tailwind Rules

- page에 긴 utility class를 반복하지 않습니다.
- 반복되는 조합은 `shared/ui` component로 승격합니다.
- variant가 있는 컴포넌트는 `class-variance-authority`로 관리합니다.
- 조건부 class 조합은 `clsx` 기반 `cn()` helper를 사용합니다.
- domain/application/infrastructure 계층에는 Tailwind class를 두지 않습니다.
- 색상/spacing/radius는 가능한 한 Tailwind token을 사용합니다.

## Current Tokens

| Token | 의미 |
|---|---|
| `app.bg` | app background |
| `app.panel` | panel/card surface |
| `app.text` | primary text |
| `app.muted` | secondary text |
| `app.border` | section/table border |
| `app.control` | input/button border |
| `app.accent` | selected/link/accent |
| `app.accentSoft` | selected row/card background |
| `app.success` | healthy/online |
| `app.warning` | stale/degraded |
| `app.danger` | failed/critical |
| `app.neutral` | unknown/not available |

## Shared UI Priority

PWA 화면은 아래 component를 우선 사용합니다.

- `Button`
- `ConfirmButton`
- `Panel`
- `DataTable`
- `StatusBadge`
- `MetricStrip`
- `KeyValueRows`
- `ErrorState`
- `CommandResult`

새 화면에서 동일한 패턴이 세 번 이상 반복되면 shared UI로 올릴지 검토합니다.

## Data Presentation

Table은 desktop에서 빠른 scan에 유리하지만 iPhone/iPad portrait에서는 가독성이 떨어집니다. `DataTable`은 동일한 column definition을 사용해서:

- `md` 이상: table
- `md` 미만: card list

로 렌더링합니다. page는 별도 mobile 전용 데이터를 만들지 않습니다.

## Button Policy

중요 command는 확인 단계가 있어야 합니다.

- destructive command: `ConfirmButton`
- runtime operation: command result 표시
- capability가 없는 command: disabled 상태와 이유 표시

Native처럼 macOS confirm sheet를 직접 제공하지 못하므로, PWA는 우선 browser confirm을 사용하고 나중에 shared modal로 교체할 수 있게 `ConfirmButton`에 모읍니다.

## Migration Policy

기존 CSS를 모두 한 번에 제거하지 않습니다.

1. shared UI primitive를 Tailwind token 기반으로 고정합니다.
2. 기존 feature class는 유지하면서 `global.css`의 Tailwind layer로 매핑합니다.
3. page별 긴 className이 늘어나면 shared UI로 승격합니다.
4. 시각 regression이 안정화되면 legacy compatibility class를 줄입니다.
