# 053 Update와 watchdog이 runtime status를 두고 경합함

> ID: TS-053  
> Category: Update / Runtime health  
> Owner: macOS runtime  
> Status: active

## Symptoms

Update apply 또는 rollback 중 Helper의 Diagnostics가 짧은 시간 안에 아래처럼 흔들릴 수 있습니다.

- `Operation`이 `Apply Bundle`, `Rollback`, `Watchdog` 사이에서 바뀝니다.
- Service health는 모두 green인데 Diagnostics만 `Critical` 또는 `Watchdog`으로 표시됩니다.
- Update command는 아직 진행 중인데 watchdog이 `runtime watchdog passed`, `watchdog recovery started`, `watchdog skipped` 같은 이벤트를 기록합니다.
- `runtime-status.json`만 보면 update 작업 소유자가 누구인지 판단하기 어렵습니다.

## Cause

`runtime-status.json`은 diagnostics/status projection artifact입니다. 작업 소유권, current operation, current progress, service liveness, 또는 mutual exclusion 계약이 아닙니다.

기존 watchdog guard는 `runtime-status.json`의 `status`, `operation`, `updatedAt`을 보고 active managed operation을 추정했습니다. update apply가 긴 작업을 진행하는 동안 watchdog이 health snapshot을 관측해 같은 status 파일을 갱신하면, update 작업의 active operation 표시가 사라질 수 있습니다.

이 구조에서는 상태 writer가 여러 개이고, 별도의 durable operation owner가 없기 때문에 watchdog과 update apply가 status read-model을 lock처럼 공유하는 race가 생깁니다.

Update 실패 후 rollback으로 전환되는 구간에서는 `updating`과 `recovering` 우선순위도 분리되어야 합니다. Current operation 표시는 Runtime Control operation-state API와 Host operation lease owner에서 오고, recovery/update current state는 explicit workflow/health owner read에서 조립해야 합니다. `runtime-operation-lease.json`은 active owner가 아니라 diagnostics/export artifact로만 남을 수 있습니다. rollback workflow는 runtime service restart와 health wait를 함께 수행하므로, apply-bundle failure recovery가 rollback 성공 뒤에 다시 service restart를 추가로 수행하면 같은 service state가 두 번 흔들릴 수 있습니다.

## Checks

Runtime Control operation-state owner를 먼저 확인합니다.

```sh
curl -fsS -H "X-Runtime-Control-Token: ${RUNTIME_CONTROL_TOKEN}" \
  "http://127.0.0.1:${RUNTIME_CONTROL_PORT:-18321}/runtime/operation-state" | jq .
```

log export 또는 local diagnostics가 필요할 때만 operation lease artifact presence를 확인합니다. 이 artifact는 current operation owner가 아니며, troubleshooting 판단은 Runtime Control operation-state API 결과를 기준으로 합니다.

runtime status projection과 event history를 diagnostics로 함께 확인합니다.

```sh
jq '{status,operation,message,updatedAt,progress}' \
  "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"

tail -n 120 \
  "/Library/Application Support/TiroshVitalServer/status/runtime-events.jsonl"
```

command log에서 apply-bundle process가 아직 진행 중인지 확인합니다.

```sh
tail -n 240 /private/tmp/tirosh-vitalserver-manager-command.log
ps aux | rg 'vitalserver-vm runtime apply-bundle|osascript'
```

## Fix Direction

managed operation 소유권은 `runtime-status.json`이 아니라 Host operation lease owner contract로 표현하고, Runtime Control API를 통해 mutate/read합니다.

- apply-bundle은 시작 시 Host operation lease owner를 acquire합니다.
- 기존 lease가 있으면 새 managed operation은 덮어쓰지 않고 실패합니다.
- watchdog은 status guard보다 operation lease owner guard를 먼저 봅니다.
- lease read failure는 성공/empty로 취급하지 않고 watchdog recovery를 차단합니다.
- apply-bundle 종료 시 lease를 release합니다. release 실패는 원래 apply 실패를 덮지 않고 로그에 남깁니다.
- diagnostic log export는 `runtime-operation-lease.json`을 포함해야 합니다.
- Service liveness 표시 우선순위는 install, initialization, recovery, update, explicit service state 순서로 적용합니다. recovery를 update 표시로 흡수하지 않습니다.
- apply-bundle failure recovery는 rollback workflow를 recovery owner로 취급합니다. rollback 성공 뒤 apply-bundle layer가 별도의 runtime service restart를 추가로 수행하지 않습니다.

## Prevention

- `runtime-status.json`은 diagnostics/export용 status projection으로 유지합니다.
- operation order와 ownership은 Runtime Control API를 통과하는 별도 owner contract와 guard로 표현합니다.
- missing lease와 lease read failure는 다른 상태입니다.
- read/decode/permission failure를 empty/default success로 바꾸지 않습니다.
- watchdog은 explicit operation owner가 있을 때 domain recovery 판단을 진행하지 않습니다.
- 긴 update 작업은 status writer와 별개로 operation owner를 남겨야 합니다.

## Related Cases

- `TS-008`: watchdog이 host proxy 502를 복구하지 못함
- `TS-035`: Update가 Guest capability 계약 없이 request/result worker를 가정함
- `TS-049`: Update VM stop이 launchd-restarted pid를 따라감
