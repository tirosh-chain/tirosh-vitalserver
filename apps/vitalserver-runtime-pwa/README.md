# VitalServer Runtime Control PWA

Runtime Control PWA is the browser client for the macOS VitalServer Helper
Runtime Control API. Its goal is to preserve the native Swift UI information
architecture while moving UI behavior behind the OpenAPI contract.

## Development

```sh
npm --prefix apps/vitalserver-runtime-pwa install
npm --prefix apps/vitalserver-runtime-pwa run generate:api
npm --prefix apps/vitalserver-runtime-pwa run dev
```

The Vite dev server runs on `http://127.0.0.1:5174` and proxies Runtime Control
API requests to `http://127.0.0.1:18321`.

## Configuration

Runtime Control PWA settings are loaded during bootstrap from
`src/shared/config/appSettings.ts`. Browser-visible `.env` values must use the
`VITE_` prefix. `vite.config.ts` and scripts also accept the matching
unprefixed keys for compatibility with existing local `.env` files.

Start from `.env.example` when overriding local values. Common keys:

```text
VITE_RUNTIME_CONTROL_API_BASE_URL=
VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET=http://127.0.0.1:18321
VITE_RUNTIME_CONTROL_TOKEN=vitalserver-helper-dev
VITE_RUNTIME_CONTROL_DEFAULT_PORT=18321
VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT=80
VITE_PWA_DEV_SERVER_PORT=5174
VITE_PWA_PREVIEW_PORT=4174
```

## Air-Gapped Deployment

The PWA is deployed as static files, not as a Node/Vite runtime. Release builds
run `make pwa-build`, then package `apps/vitalserver-runtime-pwa/dist/` into the
macOS Helper app bundle under `Contents/Resources/runtime-control-pwa/`.
The build machine must run `make pwa-install` before packaging so `node_modules`
is available. Field machines only receive the built static assets.

Installed systems serve the built PWA from the local Runtime Control server:

```text
http://127.0.0.1:18321/
```

The field machine does not need npm, Vite, or registry access. Package and
product update bundles carry the already-built static assets.

## API Contract

The source of truth is:

```text
docs/macos-runtime/runtime-control.openapi.json
```

Generated TypeScript types live in:

```text
src/domain/runtime-control/contracts/generated/runtime-control.ts
```

Regenerate them with:

```sh
npm --prefix apps/vitalserver-runtime-pwa run generate:api
```

## Architecture

The PWA follows the same boundary direction as the runtime code:

```text
src/
  domain/
    runtime-control/
      contracts/      OpenAPI-derived RuntimeContractAPI types
      events/         event filter policy and period calculations
      formatting/     runtime display and status formatting policy
  application/
    runtime-control/  React Query hooks and command/query orchestration
  infrastructure/
    runtime-control-api/
                     fetch-based Runtime Control API transport
  features/           route-level React pages
  shared/             app-wide config, styles, and reusable UI components
```

Dependency direction:

- `features` may use `application`, `domain`, and `shared`.
- `application` may use `domain` and `infrastructure`.
- `infrastructure` may use `domain` contracts, but must not import React UI.
- `domain` must not import React, React Query, or transport code.

Keep new business/display policy in `domain`, command/query composition in
`application`, and HTTP details in `infrastructure`.

## Validation

```sh
npm --prefix apps/vitalserver-runtime-pwa run check
npm --prefix apps/vitalserver-runtime-pwa test
npm --prefix apps/vitalserver-runtime-pwa run build
```

Equivalent make targets are available:

```sh
make pwa-check
make pwa-test
make pwa-build
```
