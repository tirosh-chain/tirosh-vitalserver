# VitalServer Remote Console PWA

macOS `VitalServer Helper`의 Runtime Control API를 브라우저에서 제어하기
위한 PWA입니다. 사용자 화면에서는 이 앱을 `Remote Console`로 부릅니다.
Swift Helper UI의 정보 구조를 최대한 유지하면서, 화면 동작은
OpenAPI contract와 React Query 기반으로 옮기는 것이 목표입니다.

설치 현장에서는 Node/Vite 앱으로 실행하지 않습니다. 빌드된 static assets를
Helper 앱 번들에 포함하고, Helper의 Runtime Control server가 이를
서빙합니다. 이 서버는 같은 네트워크의 원격 브라우저가 Remote Console에
접속할 수 있도록 Mac의 네트워크 인터페이스에서 열립니다.

## Quick Start

```sh
npm --prefix apps/vitalserver-runtime-pwa install
npm --prefix apps/vitalserver-runtime-pwa run generate:api
npm --prefix apps/vitalserver-runtime-pwa run dev
```

기본 개발 서버:

```text
http://127.0.0.1:5174/
```

개발 서버는 Runtime Control API 요청을 기본적으로 아래 Helper API로 proxy합니다.

```text
http://127.0.0.1:18321/
```

## Configuration

앱 설정은 bootstrap 시점에 `src/config/appSettings.ts`에서 한 번 로딩한 뒤
`AppSettingsProvider`로 주입합니다.

브라우저 번들에서 읽어야 하는 값은 Vite 규칙에 맞춰 `VITE_` prefix가 필요합니다.
단, `vite.config.ts`나 로컬 script에서 읽는 값은 기존 `.env`와의 호환을 위해
unprefixed key도 함께 허용합니다.

로컬 설정을 바꿀 때는 `.env.example`을 기준으로 `.env`를 만들어 사용합니다.

```text
VITE_RUNTIME_CONTROL_API_BASE_URL=
VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET=http://127.0.0.1:18321
VITE_RUNTIME_CONTROL_TOKEN=
VITE_RUNTIME_CONTROL_DEFAULT_PORT=18321
VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT=80
VITE_PWA_DEV_SERVER_PORT=5174
VITE_PWA_PREVIEW_PORT=4174
VITE_QUERY_REFETCH_ON_WINDOW_FOCUS=false
VITE_QUERY_RETRY=1
VITE_QUERY_STALE_TIME_MS=1000
```

주요 의미:

- `VITE_RUNTIME_CONTROL_API_BASE_URL`: 브라우저에서 직접 호출할 API base URL입니다.
  비워두면 same-origin을 사용합니다.
- `VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET`: Vite dev server가 `/runtime`, `/vitaldb`,
  `/lab`, `/host` 요청을 넘길 대상입니다.
- `VITE_RUNTIME_CONTROL_DEFAULT_PORT`: Status 화면에서 Remote Console link를
  만들 때 쓰는 fallback port입니다.
- `VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT`: VitalServer link를 만들 때 쓰는 fallback proxy port입니다.
- `VITE_PWA_DEV_SERVER_PORT`, `VITE_PWA_PREVIEW_PORT`: Vite dev/preview server port입니다.

## API Contract

Runtime Control API의 source of truth는 OpenAPI 문서입니다.

```text
docs/runtime/runtime-control.openapi.json
```

생성된 TypeScript type은 아래에 위치합니다.

```text
src/domain/runtime-control/contracts/generated/runtime-control.ts
```

OpenAPI가 바뀌면 type을 다시 생성합니다.

```sh
npm --prefix apps/vitalserver-runtime-pwa run generate:api
```

`check`와 `build`는 내부적으로 `generate:api`를 먼저 실행합니다.

Settings 화면은 owner 경계를 두 섹션으로 유지합니다.

- `Platform settings`: Host CPU/memory/disk, network/listener, local path,
  start-on-boot/recovery, backup, log retention. macOS Platform Agent는 조회와
  적용을 제공하고, Windows/Linux는 현재 명시적인 미지원 응답을 제공합니다.
- `Runtime product settings`: Runtime Controller가 소유하는 advertised endpoint,
  recorder ingress, container limit, Product backup, Redis Relay, administrator
  password command입니다. Platform settings 응답이나 UI가 Runtime secret을
  읽거나 보관하지 않습니다.

Recorders 화면은 실제 recorder의 activity를
`GET /runtime/vitaldb/recorders/{vrcode}/activity`에서 읽으며, Product Lab
recorder와 Bed 행은 선택 가능한 detail을 제공합니다. Info 화면은 Platform
release/install metadata를 독립적으로 읽고 미지원 응답을 오류 상태로 보존합니다.

## Architecture

`src` 내부 import는 package-relative alias인 `@/*`를 사용합니다. 같은 폴더의 파일만
`./file` 형태로 import하고, 상위 폴더를 타고 올라가는 `../../` import는 피합니다.

```text
src/
  app/
    bootstrap.tsx    settings 로딩, API gateway 생성, provider 구성
    providers.tsx    React Query, AppSettings, RuntimeControlGateway provider
    routes.tsx       Swift UI 순서에 맞춘 route metadata
  console/           RuntimeControlGateway port, React Query hooks, request builders
  components/        app-wide reusable UI components
  config/            AppSettings and app-wide config context
  styles/            global styles
  domain/
    runtime-control/
      contracts/     OpenAPI-derived RuntimeContractAPI types and schemas
      events/        event filter policy and period calculations
      formatting/    runtime display/status formatting policy
      settings/      runtime settings validation policy
  infrastructure/
    console-api/     fetch-based RuntimeControlApiClient implementation
  pages/             route-level Remote Console pages and page-owned form logic
```

Dependency direction:

- `pages`는 `console`, `domain`, `components`, `config`를 사용할 수 있습니다.
- `console`은 `domain`과 `RuntimeControlGateway` port만 사용합니다.
- `infrastructure`는 `RuntimeControlGateway` port를 구현하고, `domain` contract를 사용할 수 있습니다.
- `app` composition root는 settings를 읽고 concrete infrastructure gateway를 주입합니다.
- `domain`은 React, React Query, transport code를 import하지 않습니다.

새로운 business/display policy는 `domain`에 둡니다. 여러 API 호출을 조합하는
command/query 흐름은 `console`에 둡니다. fetch, token, URL 조립 같은 HTTP
detail은 `infrastructure`에 둡니다.

Route/page 컴포넌트와 특정 화면에 묶인 form draft 변환은 `pages/<page>/`에
둡니다. 이 PWA는 Remote Console 전용 앱이므로 UI route 경로에 `runtime-control`
depth를 한 번 더 두지 않습니다. PWA 내부의 gateway, hooks, query key도 `console`
이름으로 관리하고, `runtime-control` 이름은 OpenAPI contract와 runtime policy
경계에만 남깁니다. 여러 화면에서 공유되는 UI는 `components`에 두고, 여러 화면에서
공유되는 runtime contract, validation, formatting, capability policy는
`domain/runtime-control`에 둡니다.

## Air-Gapped Deployment

PWA는 Node/Vite runtime으로 배포하지 않습니다. release build에서 static files를
생성하고, macOS Helper app bundle 아래에 포함합니다.

```sh
make pwa-install
make pwa/build
```

빌드 결과물:

```text
apps/vitalserver-runtime-pwa/dist/
```

Helper app bundle 내 포함 위치:

```text
Contents/Resources/runtime-control-pwa/
```

설치된 시스템에서는 Helper의 Runtime Control server가 Remote Console을 제공합니다.
원격 브라우저에서는 Mac의 IP나 hostname을 사용합니다.

```text
http://<mac-host-or-ip>:18321/
```

현장 PC에는 npm, Vite, registry access가 필요하지 않습니다. package/update bundle은
이미 빌드된 static assets를 포함해야 합니다.

## Validation

기본 검증:

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-runtime-pwa run coverage
npm --prefix apps/vitalserver-runtime-pwa run build
```

동일한 make target:

```sh
make pwa-check
make pwa-test
make pwa-coverage
make pwa/build
```

Coverage report:

- Terminal summary: printed by `npm --prefix apps/vitalserver-runtime-pwa run coverage`.
- HTML report: `apps/vitalserver-runtime-pwa/coverage/index.html`.
- LCOV report: `apps/vitalserver-runtime-pwa/coverage/lcov.info`.

README나 문서만 수정했다면 full build가 꼭 필요하지는 않습니다. 설정, routing,
API client, domain policy를 바꿨다면 `check`, `test`, `build`를 모두 돌리는 것을
권장합니다.

## Troubleshooting

Remote Console에서 `Runtime Control API is unreachable`가 보이면 먼저 아래를 확인합니다.

- Helper Runtime Control API server가 실행 중인지 확인합니다.
- PWA가 기대하는 API URL이 맞는지 확인합니다. 개발 중이면
  `VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET`가 핵심입니다.
- 설치된 PWA라면 Helper가 실제로 `http://<mac-host-or-ip>:18321/`에서 static assets와
  API를 함께 제공하는지 확인합니다. Mac에서만 확인할 때는 `http://127.0.0.1:18321/`도 사용할 수 있습니다.
- 포트를 바꾼 경우 `VITE_RUNTIME_CONTROL_DEFAULT_PORT`, Helper server bind port,
  현재 접속 URL이 서로 맞아야 합니다.
