# 066 Clean Uninstall Progress Viewer Shows Failed After Successful Uninstall

## Summary

Helper app에서 Clean Uninstall을 실행한 뒤 Terminal progress window가 아래처럼 실패를 표시합니다.

```text
VitalServer uninstall progress
Log: /private/tmp/tirosh-vitalserver-uninstall.log

Uninstall failed. Check the log above.
```

하지만 `/private/tmp/tirosh-vitalserver-uninstall.log`의 마지막은 성공으로 끝납니다.

```text
uninstall process completed exitCode=0 runID=<run-id>
```

## Cause

Progress viewer는 worker PID 파일과 run-specific terminal marker를 함께 봅니다. 이전 viewer window가 같은 log/PID 파일을 계속 보고 있거나, viewer가 자기 run의 `started` marker를 아직 확인하지 않은 상태에서 worker PID 종료를 먼저 보면, 실제 uninstall worker가 정상 완료했는데도 viewer가 이를 실패로 표시할 수 있습니다.

Root uninstaller의 source of truth는 `/private/tmp/tirosh-vitalserver-uninstall.log`의 run marker입니다. Terminal viewer는 사람이 보는 보조 표시이며, 다른 run의 worker PID 종료를 자기 run 실패로 추정하면 안 됩니다.

## Confirm

```bash
tail -n 120 /private/tmp/tirosh-vitalserver-uninstall.log
```

아래 marker가 있으면 cleanup 자체는 성공입니다.

```text
uninstall process completed exitCode=0 runID=<run-id>
```

실패 marker가 있으면 실제 uninstall 실패로 보고 해당 step 로그를 봅니다.

```text
uninstall process failed exitCode=<status> runID=<run-id>
```

## Fix Direction

Progress viewer는 자기 run의 `started` marker를 본 뒤에만 worker PID 종료를 실패로 해석해야 합니다. `completed` 또는 explicit `failed` marker가 있으면 그 marker가 최종 판단입니다.

## Prevention

- Progress UI must not infer operation failure from shared PID/log state until it has observed ownership for its own run.
- Root uninstaller terminal markers remain the completion contract.
- Stale progress windows must not affect the current uninstall result.

## Follow-up

- 2026-06-10: 현장 로그에서 Terminal은 실패를 표시했지만 uninstall log가 `exitCode=0`으로 끝난 케이스를 확인했습니다. Viewer가 자기 run의 `started` marker를 확인한 뒤에만 worker PID 종료를 실패로 처리하도록 수정했습니다.
