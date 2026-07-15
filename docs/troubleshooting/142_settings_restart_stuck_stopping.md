# Settings restart leaves VM lifecycle in stopping

> ID: TS-142
> Category: Runtime health / VM lifecycle / macOS Helper
> Owner: macOS runtime
> Status: source fixed; package verification pending

## Symptoms

- Settings의 `Apply`가 VM 재시작 이후 완료되지 않는다.
- `/private/tmp/tirosh-vitalserver-manager-command.log`가 `waiting for runtime health`를 반복한다.
- VM launchd job은 반복해서 exit code 1로 종료되고 다음 오류를 남긴다.

```text
VM lifecycle transition is invalid from=stopping to=starting
```

- Host proxy port는 열리지 않고 desired settings와 applied settings가 계속 다르다.

## Cause

Settings restart는 Guest Control의 명시적인 `poweroff-ready` 결과를 받은 뒤 poweroff를 요청하고 VM launchd job을 unload한다. 기존 service controller는 launchd job이 unloaded인지만 기다렸고, restart 시작 전에 처음 캡처한 VM PID의 종료와 SQLite lifecycle terminal state를 함께 검증하지 않았다.

실패한 설치에서는 VM launcher가 SIGTERM을 받아 `stopping`을 기록했지만 `guestDidStop` callback이 `stopped`를 기록하기 전에 프로세스가 종료됐다. workflow는 이 non-terminal lifecycle을 그대로 둔 채 VM service를 다시 bootstrap했다. 새 launcher의 `starting` write는 상태 머신의 `stopping -> starting` 금지 규칙에 의해 거부됐고, launchd `KeepAlive`가 같은 실패를 반복했다.

Health wait에도 별도 시간 계약 오류가 있었다. `timeoutSeconds=600`을 실제 deadline으로 사용하지 않고 `200 attempts × 3 seconds`로 변환했기 때문에, 각 attempt의 launchd read와 HTTP probe 시간이 600초에 추가됐다. 따라서 UI와 privileged configure command가 명시한 제한보다 오래 대기했다.

## Fix

- Guest poweroff 뒤 VM service를 unload한 경우에도 처음 캡처한 PID의 종료를 반드시 확인한다.
- PID 종료 뒤 SQLite lifecycle을 읽어 `stopped` 또는 기존 `failed` terminal proof를 확인한다.
- 프로세스가 종료됐는데 lifecycle이 `starting`, `bootstrapping`, `running`, `stopping`이면 성공으로 보정하지 않는다. `process-exited-without-terminal-state` terminal failure를 기록하고, 상태 머신의 명시적인 `failed -> starting` 새 run 규칙을 사용한다.
- 기존 설치본의 data-preserving package reinstall이 서비스를 명시적으로 정지했는데도 과거 lifecycle이 non-terminal이면 이를 성공이나 `stopped`로 추정하지 않는다. `service-stopped-without-terminal-state` failure를 기록해 과거 실패를 보존하고 다음 run을 시작할 수 있게 한다. lifecycle이 명시적으로 missing이면 이전 VM run이 없는 상태로 그대로 보존한다.
- 캡처한 PID 종료를 확인한 Settings restart 경로에서 lifecycle missing, read failure, unknown state는 restart를 차단한다.
- Runtime health wait는 Host clock의 실제 deadline을 사용하며 HTTP probe와 service read 시간도 timeout에 포함한다.

## Checks

```sh
launchctl print system/ai.tirosh.vitalserver.helper.vm

sudo sqlite3 \
  "/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite" \
  'select revision, run_id, state, terminal_reason, message, updated_at from vm_lifecycle;'

rg -n 'process exited without terminal|stopping to=starting|runtime health timed out' \
  "/Library/Application Support/VitalServerHelper/logs/runtime/launchd.err.log" \
  /private/tmp/tirosh-vitalserver-manager-command.log
```

수정된 패키지에서 Settings Apply가 성공하면 새로운 lifecycle run이 `running`이어야 하고, `host_runtime_settings.applied_run_id`가 그 run ID와 같아야 한다. 실패하면 applied revision은 이전 값으로 남고 command는 제한 시간 안에 실패해야 한다.

## Prevention

- launchd job state와 그 job이 실행했던 VM process state는 서로 다른 증거로 검증한다.
- operation은 non-terminal lifecycle에서 다음 run으로 진행하지 않는다.
- 프로세스 종료를 lifecycle 성공으로 추정하지 않고, terminal callback이 없었다는 실패를 명시적으로 기록한다.
- timeout이라는 이름의 계약은 외부 probe 실행 시간을 포함한 실제 deadline이어야 한다.

## Related Cases

- [TS-040 VM lifecycle stale after healthy boot](040_vm-lifecycle-stale-after-healthy-boot-log-export-gap.md)
- [TS-049 Update VM stop follows launchd-restarted pid](049_update-vm-pid-restart-race.md)
- [TS-131 Settings VM restart fails after saving VM activation settings](131_settings-vm-restart-invalid-config-and-platform-agent-stop.md)
