# VitalServer wrapper app

이 디렉터리는 `vendor/vitalserver`에 고정한 원본 VitalServer snapshot을 제품 실행 단위로 감싸는
app입니다.

VitalServer 코드는 이 디렉터리에 복사해 두지 않습니다. 각 배포 target은 root build context의
`vendor/vitalserver/vitalserver-old`를 가져오고, 이 app에서 관리하는 runtime shim만
추가합니다. 현재는 Docker target만 둡니다. VitalServer 애플리케이션 자체 수정은 기본 제품 경로로
삼지 않고, wrapper/runtime sidecar에서 필요한 운영 보정을 수행합니다.

## 구성

```text
apps/vitalserver/
├── docker/
│   └── Dockerfile
└── runtime/
    └── node-preload.js
```

- `docker/Dockerfile`: upstream VitalServer Docker image 정의
- `runtime/node-preload.js`: upstream code를 직접 고치지 않고 실행 시점에 보정하는 Node preload
  shim

`runtime/node-preload.js`는 Web Monitoring 브라우저가 Socket.IO에 붙을 때 사용하는
`websocket:ip`, `websocket:port` Redis key도 보정합니다. Socket.IO 기본값은 same-origin path(`/`)입니다.
즉 브라우저가 `http://localhost`로 접속하면 Socket.IO도 localhost로 붙고,
`http://172.31.0.146/`으로 접속하면 Socket.IO도 같은 host로 붙습니다. 단일 public 주소로
고정해야 하는 환경에서는 `.env`에서 `VITALSERVER_PUBLIC_HOST`, `VITALSERVER_PUBLIC_PORT`를
명시합니다.

My Files의 `.vital` preview는 upstream `/webview`가 `http://<websocket_host>/vital_files/...`
형태의 absolute URL을 만들기 때문에 Socket.IO와 같은 `/` 값을 사용할 수 없습니다. wrapper runtime은
`webview` render 시 `.vital` fetch path를 same-origin `/vital_files/...` 경로로 보정합니다.

My Files의 날짜 input은 upstream static JS에서 `change` 이벤트를 실제 조회로 연결하지 않습니다.
wrapper runtime은 `/static/js/my-files.js` 응답을 실행 시점에 보정해 date picker 변경이
`request_data()`로 이어지도록 합니다. 보정 대상 upstream handler가 사라지면 500 응답으로 드러나게
해서 silent success로 숨기지 않습니다.

업로드된 `.vital` 파일은 VitalServer container 내부의 `/opt/vitalserver/vital_files`에 저장됩니다.
root `compose.yaml`은 이 경로를 `${VITALSERVER_VITAL_FILES_DIR:-./data/vital-files}` host directory로
bind mount합니다. macOS Helper 배포에서는 Settings의 `Vital files directory` 값이 같은 guest 경로로
전달됩니다. 파일을 수동 복사하는 것만으로는 My Files Redis index가 생성되지 않으므로, My Files에
보이게 하려면 upload endpoint를 통해 저장과 index 생성을 함께 수행해야 합니다.

upstream VitalServer는 Redis client를 `0.0.0.0:6379`로 생성합니다. wrapper runtime은 이
값을 `VITALSERVER_REDIS_HOST`, `VITALSERVER_REDIS_PORT`로 보정해 Compose 내부 Redis service에
연결합니다. 그래서 app container가 redis container의 network namespace를 공유하지 않아도 됩니다.

VR 접속이 신뢰할 수 있는 host-level proxy나 ingress를 지날 때 실제 VR IP 선택과 Redis
`ip_<vrcode>` 보정은 `vitalserver-audit-proxy`가 담당합니다. 원본 VitalServer에는 proxy-header
IP patch를 넣지 않습니다.

macOS Docker Desktop에서는 Docker published port를 VR 장비에 직접 노출하지 말고, host
nginx 같은 proxy가 외부 접속을 받은 뒤 Docker backend로 전달해야 실제 VR IP를 header로
보존할 수 있습니다. nginx config template은 `infra/macos-nginx/`에 있습니다.
제품 배포에서는 Docker backend를 loopback에만 publish합니다.

```env
VITALSERVER_BIND_HOST=127.0.0.1
VITALSERVER_HTTP_PORT=18080
VITALSERVER_REDIS_HOST=redis
VITALSERVER_REDIS_PORT=6379
```

외부 장비와 브라우저는 macOS host nginx의 public port로 접속합니다.

Compose stack은 repository root의 `compose.yaml`에서 관리합니다. 이 wrapper app은 VitalServer 실행
단위만 소유하고, command audit은 `vitalserver-audit-proxy`, Redis/proxy 기반 runtime 관측은
`vitaldb-observer`가 sidecar로 처리합니다.

제품화 전체 맥락은 repository root의 `README.md`와 `docs/index.md`를 기준으로 봅니다.
