# VitalServer wrapper app

이 디렉터리는 `vendor/vitalserver`에 고정한 upstream VitalServer를 제품 실행 단위로 감싸는
app입니다.

upstream 코드는 이 디렉터리에 복사해 두지 않습니다. 각 배포 target은 root build context의
`vendor/vitalserver/vitalserver-old`를 가져오고, 이 app에서 관리하는 runtime shim만
추가합니다. 현재는 Docker target만 둡니다.

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
`websocket:ip`, `websocket:port` Redis key도 외부 접속 주소로 보정합니다. 기본값은
`localhost:8080`이고, `.env`에서 `VITALSERVER_PUBLIC_HOST`, `VITALSERVER_PUBLIC_PORT`로
바꿀 수 있습니다.

Compose stack은 repository root의 `compose.yaml`에서 관리합니다.

제품화 전체 맥락은 repository root의 `README.md`와 `docs/index.md`를 기준으로 봅니다.
