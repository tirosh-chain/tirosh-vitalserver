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

## API Contract

The source of truth is:

```text
docs/macos-runtime/runtime-control.openapi.json
```

Generated TypeScript types live in:

```text
src/api/generated/runtime-control.ts
```

Regenerate them with:

```sh
npm --prefix apps/vitalserver-runtime-pwa run generate:api
```

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
