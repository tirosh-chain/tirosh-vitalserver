# Runtime Control PWA

Runtime Control PWA는 macOS Helper native UI와 같은 runtime control 경험을 브라우저/PWA로 제공하기 위한 UI입니다. 이 문서군은 PWA 구현의 source of truth, 레이어 경계, 디자인 시스템, 반응형 기준을 정리합니다.

PWA는 Runtime Control API를 primary boundary로 사용합니다. native shell이 직접 처리하던 local file affordance, 권한 상승, Finder 열기 같은 작업은 API capability 또는 host affordance로 분리해서 다룹니다.

## 문서

| 문서 | 역할 |
|---|---|
| [Architecture](pwa/architecture.md) | PWA 레이어, SoT, API boundary, 테스트 경계 |
| [Design system](pwa/design-system.md) | Tailwind token, shared UI component, styling ownership |
| [Responsive layout](pwa/responsive-layout.md) | 24/32인치, iPad, iPhone 대응 기준 |
| [Swift UI parity](pwa/parity.md) | Swift UI 대비 PWA 기능 parity와 host affordance gap |
| [Deployment](pwa/deployment.md) | air-gapped 배포, Helper resource 포함, update bundle 영향 |
| [Testing](pwa/testing.md) | PWA test scope, 검증 명령, responsive smoke test 기준 |

## 목표

- Swift UI가 제공하는 runtime control 정보를 PWA에서도 같은 의미로 보여줍니다.
- Runtime Control API 계약을 기준으로 UI를 구성하고, 임시 dev/test 화면에 종속되지 않습니다.
- 도메인 타입과 표시 정책은 `domain/runtime-control`, query/command orchestration은 `console`, reusable UI는 `components`에 두고 page는 조합 책임만 갖습니다.
- 반응형 UI는 같은 기능을 화면 폭에 맞게 재배치하되, 제품 기능을 숨기거나 별도 구현으로 분기하지 않습니다.

## 비목표

- PWA에서 macOS native 권한을 직접 대체하지 않습니다.
- 인증/session 정책은 별도 이슈에서 독립적으로 다룹니다.
- TestKit 전용 기능은 capability가 허용될 때만 노출하며, 제품 UI 경계와 섞지 않습니다.

## 관련 문서

- [Runtime Control API](macos-runtime/runtime-control-api.md)
- [Runtime observability model](macos-runtime/observability.md)
- [ADR 0002: Helper client boundary](adr/0002-helper-client-boundary-for-local-and-remote-runtime.md)
