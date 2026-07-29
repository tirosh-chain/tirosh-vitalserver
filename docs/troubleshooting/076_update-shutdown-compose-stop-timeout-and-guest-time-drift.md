# Update shutdown compose stop timeout and guest time drift

> Owner: macOS runtime / guest tools

## Symptom

- Product update verification and bundle staging succeed.
- Update enters rollback during `stop-runtime-services`.
- Runtime status reports:

```text
bundle apply failed; rollback completed:
Guest update shutdown failed at guest-services-stop:
service app did not stop; remaining services: app, redis
```

- PWA observability timestamps may show Guest-side dates far behind Host time, such as `2025-02-22 06:21:36 +09:00` while Host is in 2026.
- Recorders/Beds의 상대 시간이 짧은 새 관측 뒤 `22s → 18s`처럼 감소할 수 있습니다.

## Cause

The update bundle was valid and storage preflight passed. The failure happened inside Guest shutdown preparation after Redis backup completed:

```text
redis backup completed
guest services stop started
docker compose stop timed out while stopping app after 90s
```

Older Guest shutdown used one whole-stack `docker compose stop` call. When one or two services remained running, the result only said that compose stop timed out. Operators had to inspect `guest-observability/shutdown-failure.latest.json` to learn which services were still up.

Guest time drift is a separate but related boot contract issue. Host writes explicit `host-time.json`, but if Guest only applies it during first bootstrap, a later restart or rollback that reuses the VM disk can keep the image/rootfs clock.

2026-07-15 재현에서는 Guest와 Host 시계가 모두 정상 속도로 진행했지만 Guest가 약 12분 뒤에 있었습니다. 설치본의 `host-time.json.updatedAt`은 설정 Apply보다 12분 앞선 시각이었고, 설정 restart의 bulk service-start 경로와 launchd `RunAtLoad` 경로가 기존 계약을 그대로 둔 채 `vitalserver-vm start`를 실행했습니다. Guest boot service는 계약을 정확히 적용했지만 입력 자체가 stale했으므로 Host가 stale state를 제공한 문제였습니다.

2026-07-28 재현에서는 Host가 VM 시작 직전에 기록한 `host-time.json`을 Guest가
부팅 지연 뒤 적용하면서 약 15초의 고정 offset이 생겼습니다. Guest가 새
`lastSeenAt`을 기록하는 주기와 브라우저/Host의 현재 시각이 서로 다른 clock을
사용하므로, 새 observation을 받은 직후 계산한 상대 시간이 이전 값보다 작아졌습니다.
UI 계산 오류가 아니라 Host와 Guest 사이의 지속 동기화가 없었던 문제입니다.

## Fix Direction

- Stop Guest compose services in an explicit update shutdown order: `testkit`, `edge`, `swagger-ui`, `redis-ui`, `recorder-ingress`, `vitaldb-observer`, `app`, then `redis`.
- Use service-specific timeouts: default 30s, `app` 90s, `redis` 60s. These give shutdown-heavy services more time without hiding which service is blocking shutdown.
- On timeout, write typed failure details into `prepare-update-shutdown-result.json`: `failedService`, `remainingServices`, `serviceStates`, stop timeouts, and `failureSnapshotPath`.
- Keep the Host update wait timeout larger than the maximum Guest shutdown path.
- Run Guest host-time synchronization on every boot before Docker, runtime-state, observability, command polling, compose, and TestKit services start.
- Write `host-time.json` in the actual `vitalserver-vm start` entrypoint immediately before the VM lifecycle run begins. Service-controller wrappers are not sufficient because launchd `RunAtLoad` and `KeepAlive` can invoke the launcher directly.
- Platform Agent는 명시적으로 읽은 Guest 주소와 동일 subnet인 Host interface 하나만
  선택해 UDP 123을 열고, 그 listener와 허용 Guest 주소를
  `time-authority.json`으로 게시합니다. 선택 불가, port 충돌, 파일 write 실패는
  각각 unavailable/failed로 남깁니다.
- Guest rootfs는 chrony를 포함하고, 네트워크 준비 뒤
  `time-authority.json`의 정확한 server address/port만 적용합니다. default gateway나
  interface 이름으로 NTP source를 추측하지 않습니다.
- Guest `/runtime/stack.clockQuality`는 `chronyc tracking -n`의 source, stratum,
  offset, uncertainty, dispersion, last-sync 증거가 모두 있을 때만
  `synchronized`입니다.
- PWA는 Host `timeAuthority`와 Guest `clockQuality`를 표시하며 상대 시간을
  단조 증가로 보정하거나 음수를 0으로 숨기지 않습니다.
- Preserve compose stop timeout as a typed Guest dependency failure. Do not infer success from partial logs or missing status.

## Diagnosis

Check the Guest shutdown result first:

```text
/Library/Application Support/VitalServerHelper/vm/data/run/prepare-update-shutdown-result.json
```

For ordered stop failures, expect explicit details:

```json
{
  "status": "failed",
  "step": "failed",
  "message": "Guest update shutdown failed at guest-services-stop: service app did not stop; remaining services: app, redis",
  "details": {
    "stopAction": "ordered-compose-stop",
    "failedService": "app",
    "remainingServices": ["app", "redis"],
    "failureSnapshotPath": "/mnt/tirosh/run/guest-observability/shutdown-failure.latest.json"
  }
}
```

Then inspect the snapshot referenced by `failureSnapshotPath`. It is Guest-owned observed state, not Host log inference.

시간 차이는 Runtime Control API에서 함께 확인합니다.

```text
GET /platform
  timeAuthority.state
  timeAuthority.document.state
  timeAuthority.document.serverAddress
  timeAuthority.document.issue

GET /runtime/stack
  clockQuality.state
  clockQuality.source
  clockQuality.stratum
  clockQuality.offsetMs
  clockQuality.lastSyncAt
  clockQuality.issue
```

Host가 upstream 동기화를 증명하지 못한 현재 helper profile은
`host-clock-only`입니다. 이는 Guest가 Host와 동기화되지 않았다는 뜻이 아니라,
Host clock 자체가 외부 authoritative source와 동기화됐다고 증명하지 않았다는
뜻입니다. Guest는 별도로 자신의 `synchronized` 증거를 보고합니다.

## Prevention

- Runtime smoke and update verification should include an update shutdown case with active TestKit/observer traffic.
- Update shutdown must report the service that failed to stop. A generic compose timeout is not enough to diagnose rollback cause.
- UI should display Guest-provided timestamps as observed state. It must not correct Guest time drift by formatting with Host time.
- Guest time synchronization must consume the Host-owned `host-time.json` contract. Missing, unreadable, invalid, or stale host time is a contract failure, not a display fallback.
- Continuous Host/Guest synchronization is a separate NTP service concern. The boot contract remains required for the pre-network boot phase; NTP unavailability must be reported as unsynchronized/degraded and must not be converted into boot-contract success.
- NTP 장애는 VitalServer traffic path를 성공으로 위장하거나 중단시키지 않습니다.
  Timer가 재시도하고 API/PWA가 failed/unavailable 상태와 원인을 그대로 표시합니다.
- Observer가 설치되지 않은 Recorder의 장비 NTP 상태는 `notReported`로 유지합니다.
  Host/Guest clock quality로 Recorder clock state를 만들어 내지 않습니다.
