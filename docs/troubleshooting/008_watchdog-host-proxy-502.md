# 008 watchdog이 host proxy 502를 복구하지 못함

> ID: TS-008  
> Category: Host proxy  
> Owner: macOS runtime  
> Status: active

증상:

```text
watchdog recovery started: host-proxy-http-failed, guest-http-missing-vm-ip
Failure reasons: host-proxy-http-502, guest-http-missing-vm-ip
```

또는 recovery 이후 아래처럼 남습니다.

```text
watchdog recovery failed: host-proxy-http-502
```

원인:

`guest-http-missing-vm-ip`는 VM 첫 부팅 중 아직 Guest address bootstrap evidence가 준비되지 않았을 때 나올 수 있습니다. 현재 Host proxy는 `runtime-observation.json.vmIP`를 address fallback으로 읽지 않고, explicit `vm-ip` bootstrap file과 `runtime-observation.json.guestHTTP` readiness evidence를 기다립니다. 이후 Guest address가 생겼는데도 `host-proxy-http-502`가 계속 남으면 host nginx proxy 쪽을 봅니다.

이번 사례에서는 guest VM IP는 생성됐지만, 설치된 host nginx가 port 80을 bind하지 못했습니다.

```text
nginx: [emerg] bind() to 0.0.0.0:80 failed (48: Address already in use)
```

다른 설치본에서는 host nginx가 Homebrew runtime directory에 의존해서 시작하지 못하는 사례도 있었습니다.

```text
nginx: [alert] could not open error log file: open() "/opt/homebrew/var/log/nginx/error.log" failed (2: No such file or directory)
nginx: [emerg] mkdir() "/opt/homebrew/var/run/nginx/client_body_temp" failed (2: No such file or directory)
```

이 경우는 port 점유가 아니라 packaging/config 문제입니다. `TS-028`을 먼저 봅니다.

확인:

```sh
cat "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-observation.json"
cat "/Library/Application Support/TiroshVitalServer/vm/logs/proxy.err.log"
sudo lsof -nP -iTCP:80 -sTCP:LISTEN
```

조치:

port 80을 점유한 기존 nginx 또는 다른 web server를 중지한 뒤 proxy LaunchDaemon을 다시 시작합니다.

Helper app이 열리는 상태라면 `Repair Proxy` 버튼을 사용할 수 있습니다. 이 버튼은 관리자 승인을 받은 뒤 configured proxy port를 점유한 `nginx` listener를 종료하고 `com.tirosh.vitalserver-proxy`를 다시 시작합니다. `nginx`가 아닌 프로세스가 port를 점유한 경우에는 자동 종료하지 않고 로그에 표시합니다.

Update apply는 host proxy를 다시 시작하기 직전에 proxy port를 확인합니다. VitalServer가 설치한 nginx 잔재로 판별되면 자동으로 정리한 뒤 proxy를 시작하고, 다른 프로세스가 점유 중이면 VM은 시작한 상태에서 명확한 port conflict 오류로 중단합니다. 외부 nginx/httpd 같은 프로세스는 자동 종료하지 않습니다.

```sh
sudo launchctl kickstart -k system/com.tirosh.vitalserver-proxy
```

개발용 host proxy가 남아 있는 경우에는 repository에서 아래 명령으로 정리합니다.

```sh
make proxy-stop-orphans
```

최신 runtime은 host proxy health가 실패할 때 `proxy-port-80-in-use-by-...` 형태의 failure reason도 같이 기록합니다.

## Follow-up

- 관련 issue/PR, 재현 로그, 수정 버전, 운영 판단이 생기면 이 섹션에 추가합니다.
- `TS-028`: host nginx runtime directory가 Homebrew 기본 경로에 의존하던 문제를 별도 케이스로 분리했습니다.
- 2026-06-07: dev product update rollback 중 host proxy runner가 `started proxy`를 기록했지만 곧바로 `/ready` probe가 실패해 nginx를 내리는 false-start 흐름을 확인했습니다. `vitalserver-proxy-run`은 이제 nginx start/reload 후 host proxy readiness가 성공한 경우에만 `started/reloaded proxy`를 기록하고, readiness 실패 시 nginx를 중지한 뒤 retry 상태로 남깁니다.
