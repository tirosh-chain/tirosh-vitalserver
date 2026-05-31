# 028 Host proxy가 Homebrew nginx runtime directory에 의존함

> ID: TS-028
> Category: Host proxy / Packaging
> Owner: macOS runtime
> Status: resolved

## Symptoms

다른 Mac에 설치한 뒤 VitalServer service 또는 Remote Console이 열리지 않고, export logs도 정상 UI 경로로 동작하지 않을 수 있습니다. `proxy.err.log`에는 아래처럼 Homebrew 기본 경로가 보입니다.

```text
nginx: [alert] could not open error log file: open() "/opt/homebrew/var/log/nginx/error.log" failed (2: No such file or directory)
nginx: [emerg] mkdir() "/opt/homebrew/var/run/nginx/client_body_temp" failed (2: No such file or directory)
nginx: configuration file /Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf test failed
```

정상 동작에서는 host proxy nginx가 `/opt/homebrew/var/...`를 쓰지 않아야 합니다. nginx runtime file은 VitalServer product root 안에서만 생성되어야 하며, 사람이 보는 proxy log는 중앙 `logs/runtime` 아래에 기록되어야 합니다.

## Impact

Host proxy가 시작되지 않아 브라우저와 VRecorder device가 VitalServer에 접속할 수 없습니다. Guest VM과 container가 일부 정상이어도 macOS host proxy health가 계속 실패합니다. Remote Console 또는 export logs 버튼이 proxy/API 상태에 의존하는 경로로 실행되면 현장에서는 “서비스가 아예 실행되지 않음”처럼 보일 수 있습니다.

## Cause

제품 버그입니다. 설치형 package가 host nginx binary를 포함하지만, nginx config가 모든 runtime directory를 명시하지 않아 Homebrew build의 compile-time default path가 남았습니다.

`nginx -p "/Library/Application Support/TiroshVitalServer/nginx"`를 사용하더라도 `error_log` 또는 temp path가 명시되지 않은 phase에서는 nginx가 `/opt/homebrew/var/log/nginx`, `/opt/homebrew/var/run/nginx/client_body_temp` 같은 기본 경로를 참조할 수 있습니다. Homebrew가 설치되어 있지 않거나 해당 directory가 없는 Mac에서는 `nginx -t`부터 실패합니다.

## Checks

```sh
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/runtime/proxy.err.log"
tail -n 200 "/Library/Application Support/TiroshVitalServer/logs/runtime/watchdog.out.log"
cat "/Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf"
```

실패 signature:

```text
/opt/homebrew/var/log/nginx/error.log
/opt/homebrew/var/run/nginx/client_body_temp
```

## Actions

영구 해결은 수정된 package 또는 update bundle을 적용하는 것입니다. 수정된 runtime은 host nginx config에 아래 runtime directory를 명시하고, proxy runner가 시작 전에 해당 directory를 생성합니다.

```text
logs/runtime/proxy-nginx.access.log
logs/runtime/proxy-nginx.error.log
nginx/logs/nginx.pid
temp/client_body
temp/proxy
temp/fastcgi
temp/uwsgi
temp/scgi
```

현장 임시 우회가 반드시 필요하면 아래 directory를 만들 수 있습니다. 단, 이는 해당 PC의 Homebrew path를 맞춰주는 임시 조치일 뿐이며 제품 수정으로 간주하지 않습니다.

```sh
sudo mkdir -p /opt/homebrew/var/log/nginx
sudo mkdir -p /opt/homebrew/var/run/nginx/client_body_temp
sudo launchctl kickstart -k system/com.tirosh.vitalserver-proxy
```

## Prevention

Host proxy nginx를 self-contained runtime으로 고정했습니다.

- `infra/macos-nginx/vitalserver.conf.template`에서 top-level `error_log`와 모든 temp path를 VitalServer nginx prefix 상대 경로로 명시합니다.
- `infra/macos-nginx/vitalserver.conf.template`에서 nginx access/error log를 중앙 `logs/runtime/proxy-nginx.*.log`로 직접 기록하게 합니다.
- `apps/vitalserver-macos-runtime/Support/Packaging/proxy-run.template`에서 `nginx -t` 전에 필요한 중앙 `logs/runtime`, nginx `logs/`, `temp/` 하위 directory를 생성합니다.
- packaging template test에서 proxy runner가 nginx temp directory를 생성하는지 확인합니다.

## Operational Notes

이 문제는 VM disk attachment invalid와 동시에 나타날 수 있지만 원인은 분리해서 봐야 합니다. `/opt/homebrew/var/...` 로그가 있으면 먼저 host proxy packaging 문제를 해결합니다. 이후에도 `VZErrorDomain Code=2 "The storage device attachment is invalid."`가 남으면 VM disk repair 절차를 별도로 진행합니다.

## Related Cases

- `TS-008`: watchdog이 host proxy 502를 복구하지 못함
- `TS-025`: update 후 VM disk attachment가 invalid로 실패

## Follow-up

- 2026-05-29: 다른 PC 설치 로그에서 Homebrew nginx runtime directory 의존성이 확인되어 host proxy config/runner를 self-contained로 수정했습니다.
