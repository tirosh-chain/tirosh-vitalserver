# macOS VitalServer Proxy

macOS에서 Docker나 OrbStack으로 container port를 직접 publish하면 VitalServer container가
실제 VRecorder IP 대신 container runtime gateway IP를 볼 수 있습니다. `Network Settings`가
실제 장비 IP를 열어야 하므로, 운영 구성에서는 Docker 밖의 macOS host nginx를 public edge로 둡니다.

```text
VRecorder / Browser
  -> macOS host nginx public port
  -> backend 127.0.0.1:18080 or VM shared/NAT IP:80
  -> VitalServer :80
```

## Backend 환경

Docker backend는 loopback에만 열고, VitalServer는 host proxy가 전달한 IP header만 신뢰합니다.
Redis는 host에 publish하지 않고 Compose 내부 network의 `redis:6379`로 붙습니다.

```env
VITALSERVER_PROXY_PORT=80
VITALSERVER_BIND_HOST=127.0.0.1
VITALSERVER_HTTP_PORT=18080
VITALSERVER_REDIS_HOST=redis
VITALSERVER_REDIS_PORT=6379
VITALSERVER_TRUST_PROXY=1
VITALSERVER_PUBLIC_HOST=
VITALSERVER_PUBLIC_PORT=
```

외부 VRecorder 장비와 브라우저는 Docker backend port가 아니라 macOS host proxy port로 접속해야
합니다.

VM shared/NAT mode에서는 backend upstream을 VM endpoint로 바꿉니다.

```sh
VM_PROXY_UPSTREAM=<vm-ip>:80 make vm-proxy-start
```

## nginx config 렌더링

```sh
make proxy-config \
  > /Library/Application\ Support/TiroshVitalServer/nginx/vitalserver.conf
```

생성된 config는 client가 직접 보낸 forwarding header를 그대로 믿지 않고, macOS host nginx가 본
`$remote_addr`로 `X-Forwarded-For`, `X-Real-IP`, `X-Client-IP`, `Forwarded`를 덮어씁니다.

proxy/access log는 운영 진단용 raw log입니다. VitalDB observation의 최종 SoT는 이 로그가 아니라
watchdog/runtime observability SQLite입니다. `vitaldb-observer`는 필요할 때 access JSONL log를 읽어
proxy connection snapshot을 계산할 수 있지만, Runtime Control API는 watchdog이 저장한 read model을
노출합니다.

## Homebrew nginx로 로컬 PoC

로컬 검증에서는 Homebrew nginx를 설치하고 일반 stack을 실행합니다. `make up`은 Docker backend를
loopback-only로 띄운 뒤 repository가 관리하는 임시 prefix로 host nginx proxy를 실행합니다.

```sh
brew install nginx

make up
make proxy-status
make down
```

기본 proxy port는 80이므로 nginx 실행 시 관리자 권한이 필요할 수 있습니다. 로컬 PoC는 렌더링된
config를 `.tmp/macos-nginx/vitalserver.conf`에 쓰며, Homebrew service나 LaunchDaemon을 수정하지
않습니다.

proxy만 따로 확인하거나 재시작하고 싶을 때는 아래 target을 사용합니다.

```sh
make proxy-start
make proxy-status
make proxy-reload
make proxy-stop
make proxy-stop-orphans  # pid file 없이 남은 nginx listener 정리
make proxy-clean
```

`make proxy-status`는 nginx pid file뿐 아니라 proxy port listener와 Docker backend
`/check` 응답도 함께 확인합니다. `make proxy-stop`은 pid file이 없거나 stale이어도 repository
config 기준으로 nginx stop을 한 번 더 시도합니다.

## 502 Bad Gateway 확인

nginx 화면에서 `502 Bad Gateway`가 보이면 proxy는 요청을 받았지만 Docker backend에 연결하지
못한 상태입니다. nginx error log에는 보통 아래와 같은 메시지가 남습니다.

```text
connect() failed (61: Connection refused) while connecting to upstream
upstream: "http://127.0.0.1:18080/..."
```

이때는 아래 순서로 확인합니다.

```sh
make proxy-status
docker compose ps
curl -sv http://127.0.0.1:18080/check
tail -80 .tmp/macos-nginx/logs/error.log
```

`proxy-status`에서 backend가 reachable하지 않다고 나오면 `make up` 또는 `docker compose up -d`로
backend를 먼저 살립니다. proxy port가 nginx가 아닌 다른 process에 잡혀 있으면 해당 process를
중지하거나 `VITALSERVER_PROXY_PORT`를 바꿔 실행합니다.

## launchd plist 렌더링

```sh
make proxy-plist \
  > /Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist
```

설치형 배포에서는 nginx binary, 렌더링된 nginx config, LaunchDaemon plist,
VM deploy `runtime-config.json`을 함께 제공합니다. 그래야 container backend와 native proxy가 같은
port 계약을 유지합니다.
