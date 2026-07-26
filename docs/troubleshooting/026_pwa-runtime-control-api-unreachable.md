# 026 PWA가 Runtime Control API unreachable을 표시

> ID: TS-026  
> Category: Runtime Control PWA  
> Owner: macOS runtime  
> Status: active

증상:

```text
Runtime Control API is unreachable
The PWA could not reach the local Runtime Control API endpoint.
```

최신 PWA에서는 실패한 요청 URL도 같이 표시됩니다.

```text
The PWA tried http://127.0.0.1:18321/runtime/overview, but the local Runtime Control API did not respond.
```

진단:

```sh
lsof -nP -iTCP:18321 -sTCP:LISTEN
curl -i http://127.0.0.1:18321/health
curl -i http://127.0.0.1:18321/
curl -i http://127.0.0.1:18321/sw.js
curl -i -X OPTIONS \
  -H 'Origin: http://127.0.0.1:5174' \
  -H 'Access-Control-Request-Method: GET' \
  -H 'Access-Control-Request-Headers: X-Runtime-Control-Token' \
  http://127.0.0.1:18321/runtime/overview
```

원인:

PWA 번들은 로드됐지만 Runtime Control API 호출이 브라우저에서 차단될 수 있습니다.

- Helper local API가 실행되지 않거나 `18321`에 listen하지 않음
- PWA를 dev server 등 다른 origin에서 열고 `18321` API를 직접 호출함
- `X-Runtime-Control-Token` 헤더 때문에 브라우저가 CORS preflight `OPTIONS`를 보내지만 Helper API가 preflight를 처리하지 못함
- 기존 PWA service worker가 오래된 `index.html`과 asset을 계속 돌려줘 현재 Helper/API와 PWA shell이 어긋남

조치:

- 화면에 표시된 `The PWA tried ...` URL을 그대로 `curl -i`로 확인합니다.
- `curl: (7) Failed to connect`가 나오면 PWA 문제가 아니라 Helper local API server가 떠 있지 않거나 다른 port에 떠 있는 상태입니다.
- packaged PWA는 Helper가 서빙하는 `http://127.0.0.1:18321/`에서 엽니다.
- local dev에서는 Vite proxy를 사용하거나, Helper API가 loopback origin CORS preflight를 허용하는 버전으로 업데이트합니다.
- Runtime Control PWA port를 변경한 경우 Settings 또는 Status에 표시된 새 URL로 접속합니다.
- non-loopback origin은 host operation API 보호를 위해 CORS 허용 대상에 넣지 않습니다.
- 화면 탭 순서나 asset hash가 최신 빌드와 다르면 브라우저의 기존 service worker/cache를 제거하거나 새 Helper build의 `sw.js` cleanup shim이 적용되도록 한 번 새로고침합니다.

수정:

Runtime Control local HTTP server가 loopback origin의 CORS preflight를 `204 No Content`로 응답하고, 실제 API 응답에도 `Access-Control-Allow-Origin`을 붙이도록 했습니다. Runtime Control PWA port는 root-owned `runtime-control-settings.json`의 명시적 Platform Agent 설정이며, Settings의 권한 상승 configure 흐름이 이를 기록한 뒤 Platform Agent를 재시작합니다. GUI-user `UserDefaults`는 listener port owner가 아닙니다. Runtime Control PWA는 Workbox app-shell precache를 사용하지 않고, 기존 service worker/cache를 제거하는 cleanup `sw.js`만 배포합니다. Helper static responder는 `index.html`, `sw.js`, `registerSW.js`, `manifest.webmanifest`를 장기 캐시하지 않습니다.

## Follow-up

- browser session과 root-owned automation token은 다른 credential입니다. remote administration 또는 same-user OS identity authorization은 별도 권한 모델로 설계합니다.
