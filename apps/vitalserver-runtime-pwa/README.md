# VitalServer Helper Console PWA

macOS `VitalServer Helper`의 Runtime Control API를 브라우저에서 제어하기
위한 PWA입니다. 사용자 화면에서는 이 앱을 `Helper Console`로 부릅니다.
Swift Helper UI의 정보 구조를 최대한 유지하면서, 화면 동작은
OpenAPI contract와 React Query 기반으로 옮기는 것이 목표입니다.

설치 현장에서는 Node/Vite 앱으로 실행하지 않습니다. 빌드된 static assets를
Helper 앱 번들에 포함하고, Helper의 local Runtime Control server가 이를
서빙합니다.

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

앱 설정은 bootstrap 시점에 `src/shared/config/appSettings.ts`에서 한 번 로딩한 뒤
`AppSettingsProvider`로 주입합니다.

브라우저 번들에서 읽어야 하는 값은 Vite 규칙에 맞춰 `VITE_` prefix가 필요합니다.
단, `vite.config.ts`나 로컬 script에서 읽는 값은 기존 `.env`와의 호환을 위해
unprefixed key도 함께 허용합니다.

로컬 설정을 바꿀 때는 `.env.example`을 기준으로 `.env`를 만들어 사용합니다.

```text
VITE_RUNTIME_CONTROL_API_BASE_URL=
VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET=http://127.0.0.1:18321
VITE_RUNTIME_CONTROL_TOKEN=vitalserver-helper-dev
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
  `/host`, `/dev/testkit` 요청을 넘길 대상입니다.
- `VITE_RUNTIME_CONTROL_DEFAULT_PORT`: Status 화면에서 Helper Console link를
  만들 때 쓰는 fallback port입니다.
- `VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT`: VitalServer link를 만들 때 쓰는 fallback proxy port입니다.
- `VITE_PWA_DEV_SERVER_PORT`, `VITE_PWA_PREVIEW_PORT`: Vite dev/preview server port입니다.

## API Contract

Runtime Control API의 source of truth는 OpenAPI 문서입니다.

```text
docs/macos-runtime/runtime-control.openapi.json
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

## Architecture

`src` 내부 import는 package-relative alias인 `@/*`를 사용합니다. 같은 폴더의 파일만
`./file` 형태로 import하고, 상위 폴더를 타고 올라가는 `../../` import는 피합니다.

```text
src/
  app/
    bootstrap.tsx    settings 로딩, API gateway 생성, provider 구성
    providers.tsx    React Query, AppSettings, RuntimeControlGateway provider
    routes.tsx       Swift UI 순서에 맞춘 route metadata
  domain/
    runtime-control/
      contracts/     OpenAPI-derived RuntimeContractAPI types and schemas
      events/        event filter policy and period calculations
      formatting/    runtime display/status formatting policy
      settings/      runtime settings validation and form mapping policy
  application/
    runtime-control/ gateway port, React Query hooks, command/query orchestration
  infrastructure/
    runtime-control-api/
                    fetch-based Runtime Control API gateway implementation
  features/          route-level React pages
  shared/
    config/          AppSettings and app-wide config context
    styles/          global styles
    ui/              reusable UI components
```

Dependency direction:

- `features`는 `application`, `domain`, `shared`를 사용할 수 있습니다.
- `application`은 `domain`과 application-owned gateway port만 사용합니다.
- `infrastructure`는 application gateway port를 구현하고, `domain` contract를 사용할 수 있습니다.
- `app` composition root는 settings를 읽고 concrete infrastructure gateway를 주입합니다.
- `domain`은 React, React Query, transport code를 import하지 않습니다.

새로운 business/display policy는 `domain`에 둡니다. 여러 API 호출을 조합하는
command/query 흐름은 `application`에 둡니다. fetch, token, URL 조립 같은 HTTP
detail은 `infrastructure`에 둡니다. 화면 form draft와 API DTO 사이의 변환은
도메인 의미가 있는 경우 `domain/runtime-control/*`에 둡니다.

## Air-Gapped Deployment

PWA는 Node/Vite runtime으로 배포하지 않습니다. release build에서 static files를
생성하고, macOS Helper app bundle 아래에 포함합니다.

```sh
make pwa-install
make pwa-build
```

빌드 결과물:

```text
apps/vitalserver-runtime-pwa/dist/
```

Helper app bundle 내 포함 위치:

```text
Contents/Resources/runtime-control-pwa/
```

설치된 시스템에서는 Helper의 local Runtime Control server가 Helper Console을 제공합니다.

```text
http://127.0.0.1:18321/
```

현장 PC에는 npm, Vite, registry access가 필요하지 않습니다. package/update bundle은
이미 빌드된 static assets를 포함해야 합니다.

## Validation

기본 검증:

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-runtime-pwa run build
```

동일한 make target:

```sh
make pwa-check
make pwa-test
make pwa-build
```

README나 문서만 수정했다면 full build가 꼭 필요하지는 않습니다. 설정, routing,
API client, domain policy를 바꿨다면 `check`, `test`, `build`를 모두 돌리는 것을
권장합니다.

## Local Troubleshooting

Helper Console에서 `Runtime Control API is unreachable`가 보이면 먼저 아래를 확인합니다.

- Helper local API server가 실행 중인지 확인합니다.
- PWA가 기대하는 API URL이 맞는지 확인합니다. 개발 중이면
  `VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET`가 핵심입니다.
- 설치된 PWA라면 Helper가 실제로 `http://127.0.0.1:18321/`에서 static assets와
  API를 함께 제공하는지 확인합니다.
- 포트를 바꾼 경우 `VITE_RUNTIME_CONTROL_DEFAULT_PORT`, Helper server bind port,
  현재 접속 URL이 서로 맞아야 합니다.
