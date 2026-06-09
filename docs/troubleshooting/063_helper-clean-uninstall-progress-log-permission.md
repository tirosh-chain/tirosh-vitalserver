# Helper Clean Uninstall Progress Log Permission Failure

> ID: TS-063  
> Category: Uninstall  
> Owner: macOS Helper uninstall command wrapper  
> Status: resolved

## Symptoms

Helper app에서 clean uninstall을 시작하면 Terminal progress window가 열리지만 곧바로 실패를 표시합니다.

```text
VitalServer uninstall progress
Log: /private/tmp/tirosh-vitalserver-uninstall.log

/tmp/tirosh-vitalserver-uninstall-progress.command: line 31: /private/tmp/tirosh-vitalserver-uninstall.log: Permission denied

Uninstall failed. Check the log above.
```

## Impact

progress viewer가 실패로 보이기 때문에 실제 background uninstaller 상태를 읽기 어렵습니다.
기존 log 파일이 root-owned 또는 제한된 mode로 남아 있으면 Terminal 사용자에게 log read/write가
허용되지 않을 수 있습니다.

## Cause

uninstall start wrapper가 기존 `/private/tmp/tirosh-vitalserver-uninstall.log`를 truncate하면서
파일 mode를 명시하지 않았습니다. 기존 파일이 restrictive mode로 남아 있으면 Terminal에서 실행되는
progress viewer가 log를 읽거나 쓰지 못합니다.

또한 progress viewer가 worker pid disappearance를 발견했을 때 missing-marker를 log에 직접 쓰고
있었습니다. viewer는 log owner가 아니므로 log 상태를 생성하면 안 됩니다.

## Checks

```sh
ls -l /private/tmp/tirosh-vitalserver-uninstall.log
ls -l /private/tmp/tirosh-vitalserver-uninstall-progress.command.pid
tail -n 80 /private/tmp/tirosh-vitalserver-uninstall.log
```

Terminal output에 `Permission denied`가 있고 log file mode가 Terminal 사용자에게 읽기 불가능하면
progress wrapper permission failure를 먼저 봅니다.

## Actions

최신 Helper app은 uninstall start wrapper에서 새 log와 worker pid file을 생성한 뒤 `0644` mode를
명시합니다. progress viewer는 log를 읽고 화면에 completed/failed 상태를 표시하지만, missing-marker를
log에 직접 쓰지 않습니다.

이미 이 실패가 난 설치본에서는 최신 Helper app 또는 Reset Installer package로 다시 실행합니다.

## Prevention

- progress viewer는 Host-owned uninstall log에 상태를 쓰지 않습니다.
- log/pid file 생성 책임을 가진 wrapper가 file mode를 명시합니다.
- tests는 generated uninstall command에 `chmod 0644`가 포함되는지와 viewer가 log에 쓰지 않는지
  확인합니다.

## Related Cases

- TS-019
- TS-037
- TS-058
- TS-062

## Follow-up

- 2026-06-10: 설치된 Helper app의 progress terminal에서 `/private/tmp/tirosh-vitalserver-uninstall.log:
  Permission denied`가 표시되는 로그를 확인했습니다. wrapper log/pid file mode와 viewer write boundary를
  수정했습니다.
