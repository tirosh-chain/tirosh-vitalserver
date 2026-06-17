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

Progress viewer는 worker PID 파일과 run-specific terminal marker를 함께 봅니다. 이전 viewer window가 같은 log/PID 파일을 계속 보고 있거나, viewer가 자기 run의 terminal marker를 보기 전에 worker PID 종료를 먼저 보면, 실제 uninstall worker가 정상 완료했는데도 viewer가 이를 실패로 표시할 수 있습니다.

특히 worker가 정상 종료하면서 `completed` marker를 쓰는 순간과 viewer가 dead PID를 관찰하는 순간이 엇갈리면, log의 최종 marker는 성공인데 Terminal window만 실패를 표시할 수 있습니다.

또한 Terminal viewer는 일반 사용자 권한으로 실행되고 background uninstall worker는 관리자 권한으로 실행됩니다. Viewer가 `kill -0 <worker-pid>`로 root-owned worker 생존 여부를 확인하면 권한 문제를 process exit로 오판할 수 있습니다. 이 경우 worker가 아직 cleanup을 진행 중인데 viewer가 먼저 `Uninstall result is unavailable`을 표시하고 종료할 수 있습니다.

다른 형태로는 worker가 `started` marker만 쓴 뒤 terminal marker 없이 종료될 수 있습니다. 이때 result document가 `running`에 머물면 Helper UI나 progress viewer는 clean uninstall이 계속 진행 중인 것처럼 보입니다. 실제 Host artifact, launchd service, package receipt는 이미 제거됐을 수 있으므로 cleanup 상태와 progress handoff 상태를 분리해서 봐야 합니다.

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

Progress viewer는 자기 run의 `started` marker를 본 뒤에만 worker PID 종료를 실패로 해석해야 합니다. worker PID가 먼저 사라져도 짧게 자기 run의 terminal marker를 다시 확인해야 하며, `completed` 또는 explicit `failed` marker가 있으면 그 marker가 최종 판단입니다.

Viewer는 root-owned worker 생존 여부를 signal permission에 의존해 판단하면 안 됩니다. `kill -0`의 permission failure는 operation state가 아니므로, viewer는 `ps -p` 기반의 best-effort process existence check와 result/terminal marker를 조합해야 합니다.

Worker는 예상하지 못한 종료에서도 `running` result를 남기지 않아야 합니다. `EXIT` trap은 현재 run의 terminal marker가 없으면 `missing-marker` 실패 marker와 failed result document를 기록해야 합니다.

## Prevention

- Progress UI must not infer operation failure from shared PID/log state until it has observed ownership for its own run.
- Root uninstaller terminal markers remain the completion contract.
- Stale progress windows must not affect the current uninstall result.
- Background worker exit must close the progress result explicitly; a stale `running` document is not an operation state.

## Follow-up

- 2026-06-10: 현장 로그에서 Terminal은 실패를 표시했지만 uninstall log가 `exitCode=0`으로 끝난 케이스를 확인했습니다. Viewer가 자기 run의 `started` marker를 확인한 뒤에만 worker PID 종료를 실패로 처리하도록 수정했습니다.
- 2026-06-10: 같은 증상이 반복되어 viewer가 owned worker PID 종료를 본 뒤에도 짧게 terminal marker를 재확인하도록 보강했습니다. Backend uninstall success marker가 있으면 Terminal viewer는 완료로 표시해야 합니다.
- 2026-06-11: Terminal viewer가 user 권한에서 root-owned worker PID를 `kill -0`으로 확인하면서 permission failure를 worker exit로 오판하는 케이스를 확인했습니다. Viewer의 worker liveness check를 `ps -p` 기반으로 바꾸고, signal permission을 uninstall state로 사용하지 않도록 테스트를 추가했습니다.
- 2026-06-17: Helper clean uninstall이 `started` marker 이후 terminal marker 없이 끊기고 result document가 `running`에 머무는 케이스를 확인했습니다. Worker `EXIT` trap이 terminal marker 부재를 `missing-marker` 실패 result로 닫도록 보강했습니다.
