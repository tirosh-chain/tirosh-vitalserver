# Helper Clean Uninstall Nohup Detach Failure

> ID: TS-062  
> Category: Uninstall  
> Owner: macOS Helper uninstall command wrapper  
> Status: resolved

## Symptoms

Helper app에서 clean uninstall을 시작하면 progress terminal이 바로 실패를 표시합니다.

`/private/tmp/tirosh-vitalserver-uninstall.log`에는 아래처럼 매우 짧은 로그만 남습니다.

```text
nohup: can't detach from console: Inappropriate ioctl for device
uninstall process failed exitCode=127 runID=<run-id>
```

Helper message log에는 아래 흐름이 보일 수 있습니다.

```text
Preparing runtime removal...
Waiting for administrator approval...
Starting background uninstaller...
execution error: The command exited with a non-zero status. (127)
```

## Impact

실제 uninstaller가 실행되기 전에 background worker wrapper가 실패합니다. 따라서 VM stop,
Redis backup, package receipt cleanup, runtime artifact cleanup은 시작되지 않았을 수 있습니다.

이 증상은 clean uninstall workflow 내부 실패가 아니라 Helper app이 생성한 privileged shell wrapper
실패입니다.

## Cause

Helper app의 uninstall command wrapper가 background worker를 시작할 때 `nohup /bin/bash ... &`를
사용했습니다. 일부 macOS privileged shell 실행 환경에서는 `nohup`이 console detach를 수행하지
못하고 `Inappropriate ioctl for device`와 exit 127로 종료됩니다.

## Checks

```sh
cat /private/tmp/tirosh-vitalserver-uninstall.log
tail -n 80 /private/tmp/tirosh-vitalserver-helper-message.log
```

`nohup: can't detach from console`가 있으면 VM/runtime state보다 uninstall wrapper failure를 먼저
봅니다.

## Actions

최신 Helper app은 uninstall background worker를 시작할 때 `nohup`에 의존하지 않습니다. worker는
stdin을 `/dev/null`로 분리하고 stdout/stderr를 uninstall log로 redirect한 뒤 background로 실행합니다.

이미 이 실패가 난 설치본에서는 최신 Helper app 또는 Reset Installer package로 다시 실행합니다.

## Prevention

- privileged shell wrapper에서 `nohup` 성공을 background 실행 계약으로 사용하지 않습니다.
- background worker 시작 방식은 테스트에서 `nohup` 문자열이 없는지 확인합니다.
- uninstall progress terminal은 worker pid file과 terminal marker를 통해 completed/failed/missing-marker를 구분합니다.

## Related Cases

- TS-019
- TS-037
- TS-058

## Follow-up

- 2026-06-10: 설치된 Helper app의 clean uninstall이 exit 127로 실패한 로그를 확인했습니다.
  현재 소스에도 `nohup` 사용이 남아 있어 wrapper를 수정했습니다.
