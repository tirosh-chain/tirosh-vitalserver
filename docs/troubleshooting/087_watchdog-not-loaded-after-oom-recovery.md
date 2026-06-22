# Watchdog Not Loaded After OOM Recovery

> ID: TS-087
> Category: Runtime health / Launchd recovery
> Owner: macOS runtime service control
> Status: implemented

## Symptom

VM 내부 VitalServer process가 OOM killed 된 뒤 data plane은 다시 살아납니다.
`http://127.0.0.1/`과 VM upstream은 응답하지만 Helper status는 계속 `recovering`에 머뭅니다.

`runtime-status.json`은 오래된 `recovering + watchdog` 상태를 유지하고, `launchctl print`에서는
`ai.tirosh.vitalserver.helper.watchdog` service를 찾지 못합니다.

현장 로그에서는 장시간 TestKit VRecorder session 이후 아래 흐름이 함께 보일 수 있습니다.

1. TestKit VRecorder 장시간 session이 실행됐습니다.

   ```text
   elapsed_seconds=61837   # 61,837 seconds, about 17h 10m 37s
   messages_sent=58069     # 58,069 messages, about 0.94 messages/sec
   bytes_sent=102908154    # 102,908,154 bytes, about 102.9 MB / 98.1 MiB
   ```

   평균 전송량은 message당 약 1,772 bytes, 즉 약 1.7 KiB/message입니다.

2. 이후 VM 로그에서 guest 내부 OOM kill이 확인됩니다.

   ```text
   Out of memory: Killed process ... (node)
   anon-rss:5157484kB      # about 4.9 GiB resident anonymous memory
   ```

   Linux kernel log의 `kB`는 보통 1024-byte 단위로 해석하므로 `anon-rss:5157484kB`는 약
   5,281,263,616 bytes, 즉 약 5.28 GB / 4.92 GiB입니다.

3. OOM 이후 guest HTTP 상태가 비정상으로 전환됩니다.

   ```text
   guestHTTP: 502          # Bad Gateway
   ```

4. Edge log에서 recorder-ingress upstream 관련 오류가 확인됩니다.

   ```text
   unexpected DNS response for recorder-ingress
   ```

5. Host proxy log에서 VM upstream readiness 실패가 확인됩니다.

   ```text
   VM upstream is not ready; stopping proxy upstream=192.168.64.122:80
   ```

6. Helper status에는 critical failure reason이 연쇄로 기록됩니다.

   ```text
   host-proxy-http-http-probe-command-failed
   recorder-ingress-http-failed
   guest-runtime-state-stale
   ```

이 흐름은 TestKit 전송량 자체가 곧 OOM 원인이라는 뜻은 아닙니다. 명확한 원인 증거는 guest kernel이
`node` process를 OOM kill 했다는 점이고, 이후 502, recorder-ingress DNS/upstream 오류, host proxy readiness
실패, stale guest runtime state는 같은 장애의 관측 결과로 함께 나타날 수 있습니다.

## Cause

OOM의 1차 원인은 guest 내부 VitalServer process가 큰 작업 중 메모리 한계에 도달한 것입니다.
그 뒤 VM/proxy는 다시 살아날 수 있지만, watchdog launchd job이 빠진 상태면 다음 health pass가 실행되지 않습니다.

기존 start/install 순서는 watchdog을 proxy 뒤에 시작했습니다. proxy 시작 또는 복구가 중간에 끊기면
runtime status owner인 watchdog이 올라오지 못하고, 마지막 `recovering` 문서가 terminal 상태로 갱신되지 않았습니다.

## Fix Direction

- runtime service start/repair 경로에서 watchdog을 proxy보다 먼저 시작합니다.
- install start 경로도 VM, guest-log-sync, watchdog, proxy 순서로 시작합니다.
- proxy repair는 proxy만 담당하고, supervisor 복구는 `start-services` 또는 `repair-services`의 명시적 계약으로 처리합니다.

## Prevention Principle

- data plane readiness와 control plane supervision은 별도 상태입니다.
- proxy가 살아난 사실만으로 watchdog recovery 완료를 추정하지 않습니다.
- watchdog service가 required runtime service인 경로는 launchd loaded 상태를 확인한 뒤 완료해야 합니다.
- status command는 상태를 고치지 않고, service repair command가 명시적으로 빠진 supervisor를 복구합니다.

## Verification

다음 조건을 확인합니다.

1. `runtime start-services`와 `runtime repair-services`가 watchdog loaded 확인 전에는 healthy 완료를 쓰지 않습니다.
2. install service start가 proxy보다 watchdog을 먼저 bootstrap합니다.
3. OOM 이후 `watchdog service not loaded`가 보이면 `runtime repair-services`로 watchdog을 다시 bootstrap합니다.
