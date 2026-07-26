# Settings restart or Host reboot leaves VM lifecycle in stopping

> ID: TS-142
> Category: Runtime health / VM lifecycle / macOS Helper
> Owner: macOS runtime
> Status: source fixed; package verification pending

## Symptoms

- Settings의 `Apply`가 VM 재시작 이후 완료되지 않는다.
- macOS 재부팅 뒤 Vital Server Helper VM이 다시 시작되지 않는다.
- `/private/tmp/tirosh-vitalserver-manager-command.log`가 `waiting for runtime health`를 반복한다.
- VM launchd job은 반복해서 exit code 1로 종료되고 다음 오류를 남긴다.

```text
VM lifecycle transition is invalid from=stopping to=starting
```

- Host proxy port는 열리지 않고 desired settings와 applied settings가 계속 다르다.

## Cause

Settings restart는 Guest Control의 명시적인 `poweroff-ready` 결과를 받은 뒤 poweroff를 요청하고 VM launchd job을 unload한다. 기존 service controller는 launchd job이 unloaded인지만 기다렸고, restart 시작 전에 처음 캡처한 VM PID의 종료와 SQLite lifecycle terminal state를 함께 검증하지 않았다.

실패한 설치에서는 VM launcher가 SIGTERM을 받아 `stopping`을 기록했지만 `guestDidStop` callback이 `stopped`를 기록하기 전에 프로세스가 종료됐다. workflow는 이 non-terminal lifecycle을 그대로 둔 채 VM service를 다시 bootstrap했다. 새 launcher의 `starting` write는 상태 머신의 `stopping -> starting` 금지 규칙에 의해 거부됐고, launchd `KeepAlive`가 같은 실패를 반복했다.

같은 순서는 Host 재부팅에서도 발생한다. macOS가 VM launcher에 종료 신호를 전달하면 launcher는 먼저
`stopping`을 기록한다. Guest stop callback과 terminal lifecycle write 전에 Host shutdown이 완료되면 SQLite에는
non-terminal lifecycle이, PID file에는 종료된 이전 process ID가 남는다. 기존 start entrypoint는 이 Host-owned
process evidence를 읽지 않고 곧바로 `starting`을 기록했기 때문에 다음 부팅에서 복구되지 않았다.

Health wait에도 별도 시간 계약 오류가 있었다. `timeoutSeconds=600`을 실제 deadline으로 사용하지 않고 `200 attempts × 3 seconds`로 변환했기 때문에, 각 attempt의 launchd read와 HTTP probe 시간이 600초에 추가됐다. 따라서 UI와 privileged configure command가 명시한 제한보다 오래 대기했다.

## Fix

- Guest poweroff 뒤 VM service를 unload한 경우에도 처음 캡처한 PID의 종료를 반드시 확인한다.
- PID 종료 뒤 SQLite lifecycle을 읽어 `stopped` 또는 기존 `failed` terminal proof를 확인한다.
- 프로세스가 종료됐는데 lifecycle이 `starting`, `bootstrapping`, `running`, `stopping`이면 성공으로 보정하지 않는다. `process-exited-without-terminal-state` terminal failure를 기록하고, 상태 머신의 명시적인 `failed -> starting` 새 run 규칙을 사용한다.
- 기존 설치본의 data-preserving package reinstall이 서비스를 명시적으로 정지했는데도 과거 lifecycle이 non-terminal이면 이를 성공이나 `stopped`로 추정하지 않는다. `service-stopped-without-terminal-state` failure를 기록해 과거 실패를 보존하고 다음 run을 시작할 수 있게 한다. lifecycle이 명시적으로 missing이면 이전 VM run이 없는 상태로 그대로 보존한다.
- VM service start entrypoint는 새 run을 기록하기 전에 Host PID contract를 읽는다. PID가 stale이면 이전 process
  부재가 명시적으로 증명된 것이므로 non-terminal lifecycle을 `process-exited-without-terminal-state`로 종결하고
  stale PID file을 제거한 뒤 새 run을 시작한다.
- PID file이 missing, invalid, unreadable이거나 PID가 실제 실행 중이면 process 부재를 추정하지 않고 start를
  차단한다. 이미 terminal인 lifecycle과 명시적으로 missing인 lifecycle은 missing PID와 함께 그대로 허용한다.
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

Host reboot 검증에서는 재부팅 전 VM이 `running`인 상태에서 macOS를 재부팅한다. 부팅 후 stale PID가 남았다면
이전 run은 `process-exited-without-terminal-state`로 보존되고, 별도 boot ID의 새 lifecycle run이 `running`이어야
한다. `stopping -> starting` 오류가 반복되면 안 된다.

## Prevention

- launchd job state와 그 job이 실행했던 VM process state는 서로 다른 증거로 검증한다.
- operation은 non-terminal lifecycle에서 다음 run으로 진행하지 않는다.
- 프로세스 종료를 lifecycle 성공으로 추정하지 않고, terminal callback이 없었다는 실패를 명시적으로 기록한다.
- Host boot recovery도 PID file과 실제 process provider 결과가 일치할 때만 이전 run을 종결한다.
- timeout이라는 이름의 계약은 외부 probe 실행 시간을 포함한 실제 deadline이어야 한다.

## Related Cases

- [TS-040 VM lifecycle stale after healthy boot](040_vm-lifecycle-stale-after-healthy-boot-log-export-gap.md)
- [TS-049 Update VM stop follows launchd-restarted pid](049_update-vm-pid-restart-race.md)
- [TS-131 Settings VM restart fails after saving VM activation settings](131_settings-vm-restart-invalid-config-and-platform-agent-stop.md)
