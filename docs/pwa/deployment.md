# PWA Deployment

## Deployment Model

Runtime Control PWA는 별도 container로 배포하지 않습니다. PWA build output은 macOS Helper app resource에 포함되고, Helper가 실행하는 Runtime Control API local server가 static asset을 제공합니다.

```text
apps/vitalserver-runtime-pwa/
  npm run build
    -> dist/

macOS Helper app bundle
  Contents/Resources/runtime-control-pwa/
    index.html
    assets/*
    sw.js
```

Runtime Control API local server는 같은 origin에서 PWA asset과 `/runtime/*`, `/runtime/vitaldb/*`, `/host/*` API를 제공합니다.

## Local Browser Session Boundary

설치된 Platform Agent는 numeric loopback address에만 bind합니다. PWA 정적 asset에는
Platform Agent API token을 넣지 않습니다. 같은 origin의 PWA는 시작 시
`POST /platform/browser-session`을 호출하고, Agent는 body에 비밀을 반환하지 않은 채
opaque `HttpOnly; SameSite=Strict` session cookie를 발급합니다. Cookie로 인증된
`POST`/`PUT`/`DELETE` 요청은 정확히 같은 loopback origin을 다시 제시해야 합니다.

설치 프로그램과 acceptance 도구가 쓰는 root-owned API token은 별도 automation
credential로 유지합니다. 이 경계는 LAN이나 다른 browser origin의 호출 및 정적 PWA에
비밀을 넣는 문제를 막기 위한 local-browser transport boundary입니다. 같은 OS 사용자로
실행되는 악성 local process를 식별하거나 권한 분리하지는 않습니다. remote administration,
multi-user authorization, 또는 role separation이 필요하면 OS identity broker/pairing/role
model을 별도 계약으로 설계해야 합니다.

## Air-Gapped Assumption

기본 배포 대상은 air-gapped 환경입니다.

- PWA runtime asset은 package/update bundle 안에 포함되어야 합니다.
- 설치 후 외부 CDN, npm registry, web font, third-party script에 의존하면 안 됩니다.
- PWA service worker는 runtime control API 응답을 offline cache로 대체하지 않습니다.
- Runtime Control PWA는 app-shell precache를 사용하지 않습니다. `sw.js`는 이전 build에서 등록된 service worker와 cache를 제거하는 cleanup shim입니다.

## Build Inputs

PWA build는 repository-local source와 lockfile을 기준으로 재현 가능해야 합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa ci
npm --prefix apps/vitalserver-runtime-pwa run build
```

개발 중에는 아래 명령으로 확인합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run dev
```

## Runtime Paths

| 경로 | 책임 |
|---|---|
| `/` | PWA static entry |
| `/assets/*` | Vite generated static assets |
| `/sw.js` | service worker cleanup shim |
| `/registerSW.js` | compatibility hook for older cached PWA shells |
| `/runtime/*` | runtime control API |
| `/runtime/vitaldb/*` | VitalDB observability API |
| `/host/*` | host affordance API |
| `/dev/runtime-control` | browser diagnostics page only |

## Capability and Profile

PWA route visibility is capability-driven.

- Stable build에서도 PWA static assets와 product API는 제공할 수 있어야 합니다.
- `/dev/runtime-control`은 browser diagnostics page로만 둡니다. Product Lab은 `/runtime/lab/*`를 사용하고 `/dev/testkit/*`는 stable/product profile에 노출하지 않습니다.
- PWA는 `GET /runtime/capabilities`를 source of truth로 사용합니다.

## Update Bundle Impact

PWA 변경은 product update bundle로 반영될 수 있습니다.

- PWA asset 변경은 Helper app resource 변경으로 취급합니다.
- Runtime Control API contract 변경이 동반되면 OpenAPI/schema/client generation을 함께 갱신해야 합니다.
- PWA asset만 바뀌는 경우에도 브라우저가 이전 service worker/app shell에 묶여 있지 않은지 확인해야 합니다.

## Deployment Checklist

- `npm run check`, `npm test`, `npm run build` 통과
- `dist/`에 외부 URL 의존 asset이 없는지 확인
- `dist/index.html`에 `registerSW.js`가 주입되지 않는지 확인
- Runtime Control API OpenAPI와 generated type이 최신인지 확인
- Stable profile에서 `/dev/testkit/*` route가 노출되지 않는지 확인
- Air-gapped package/update bundle에 PWA dist가 포함되는지 확인
