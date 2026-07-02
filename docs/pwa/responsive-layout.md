# PWA Responsive Layout

## Target Viewports

PWA는 특정 제품명보다 viewport width를 기준으로 설계합니다.

| 범위 | 대표 환경 | 설계 기준 |
|---|---|---|
| `<390px` | compact iPhone | single column, controls full width, dense text |
| `390-639px` | iPhone | card list, wrapped toolbar |
| `640-767px` | large mobile/small tablet | card list, compact metrics |
| `768-1023px` | iPad portrait | table 가능 여부를 화면별로 판단, 1-column 중심 |
| `1024-1439px` | iPad landscape/small desktop | 2-column settings, table scan |
| `1440-1919px` | 24-inch desktop | wide table, multi-panel scan |
| `>=1920px` | 32-inch desktop | wider content max-width, longer logs/tables |

## Layout Principles

- Primary status와 current operation은 항상 상단에서 보여야 합니다.
- Table은 `md` 이상에서 사용하고, 작은 화면은 card list로 전환합니다.
- Toolbar는 wrap을 허용하되, control이 부모 밖으로 밀리지 않아야 합니다.
- Logs toolbar는 sticky로 유지합니다.
- 위험 command는 mobile에서도 실수로 눌리지 않게 spacing과 confirmation을 유지합니다.
- Text는 viewport width에 따라 font-size를 계속 키우지 않습니다.
- Panel/card radius는 8px 이하로 유지합니다.

## Page Guidelines

### Status

- 상단 summary는 모든 viewport에서 먼저 노출합니다.
- Recorder details와 resource usage는 기본적으로 열려 있어도 mobile에서 세로 흐름이 깨지지 않아야 합니다.
- Data directory 같은 긴 path는 줄바꿈 가능해야 합니다.

### Logs

- Source, line limit, live toggle, open/export controls는 sticky toolbar에 둡니다.
- Mobile에서는 toolbar item을 full width로 wrap합니다.
- Log text는 monospace와 `overflow-wrap`을 유지합니다.

### Recorders

- Desktop: recorder table + selected details.
- Mobile: recorder card list + selected details.
- Activity chart는 period selector를 유지하고, x/y axis label이 잘리지 않아야 합니다.
- VRecorder identity는 `vrcode`입니다. IP는 표시 정보일 뿐 identity가 아닙니다.

### Beds

- Desktop: bed table + selected details.
- Mobile: bed card list + selected details.
- Bed/VRecorder relationship은 stale 상태여도 latest observation 기준을 명확히 보여줍니다.

### Observability

- Pipeline summary는 compact metric 형태로 유지합니다.
- Runtime events는 period, type, limit filter를 제공합니다.
- Event list는 최신순으로 보여줍니다.
- 상단 count는 하단 limit count와 구분해서 period 기준 count를 표시합니다.

### Settings

- Desktop: 2-column grid.
- Tablet/mobile: 1-column grid.
- Apply action은 validation과 confirmation을 거칩니다.
- Custom advertised URL 같은 advanced option은 의미를 설명하되 제품 UI를 복잡하게 만들지 않습니다.

### Advanced / Danger Zone

- Advanced는 Swift UI 순서와 의미를 따른 diagnostics, VM health, service health, recovery operations, advanced network, admin operations를 담당합니다.
- Runtime service controls는 Advanced의 Admin operations 안에 둡니다.
- Recovery operations는 update recovery, VitalServer backup, runtime repair, advanced repair tools, Redis-only recovery 순서를 유지합니다.
- Danger Zone은 update backup 삭제, VitalServer backup 삭제, destructive operations처럼 삭제/제거 성격의 command를 담당합니다.
- Capability가 없는 command는 숨기기보다 비활성화와 이유 표시를 우선합니다.
- Dangerous command는 confirmation 없이 실행하지 않습니다.

### Lab

- Lab은 product route입니다.
- Mobile에서는 scenario 선택, session create/start/stop, `.vital` replay flow가 우선입니다.
- TestKit container controls나 implementation diagnostics는 Lab primary flow와 섞지 않고 More/Diagnostics 성격으로 분리합니다.

## Verification Checklist

- iPhone width에서 horizontal scroll이 생기지 않습니다.
- iPad portrait에서 toolbar control이 겹치지 않습니다.
- desktop에서 table scan이 유지됩니다.
- 32-inch에서 content가 과도하게 늘어나지 않습니다.
- Logs toolbar는 scroll 중 상단에 유지됩니다.
- DataTable은 desktop table과 mobile card가 같은 데이터를 표시합니다.
