# VM launcher requires UI-hosted Platform API

> ID: TS-110  
> Category: Packaging / Local development  
> Owner: macOS Platform Agent  
> Status: resolved

## Symptoms

`make runtime/proof/smoke` 또는 golden rootfs compile이 VM을 시작하기 전에 실패합니다.
launcher log에는 VM boot log가 없고, local Runtime Control API의
`PUT /platform/runtime-provider` 연결 실패가 먼저 나타납니다.

PWA나 macOS Control Panel을 실행하면 같은 명령이 우연히 진행될 수 있지만,
headless package build와 설치 후 launchd 기동에서는 API listener가 없으므로
재현됩니다.

## Impact

VM 이미지 compile과 설치된 Platform Agent의 자동 기동이 UI 실행 여부에
의존합니다. VM 자체나 Guest bootstrap의 실패는 아니며 데이터 손실은 없습니다.

## Cause

VM launcher, stop workflow, watchdog가 Platform Agent 소유 상태인 runtime provider
lifecycle을 기록하기 위해 UI process가 호스팅하는 HTTP API를 호출했습니다.
API가 그 상태의 유일한 owner repository처럼 사용되어 다음 순환 의존성이
생겼습니다.

```text
Platform API 실행 -> VM launcher 실행 -> Platform API에 lifecycle 기록
```

Platform 상태 owner가 UI의 생명주기에 종속된 것이 원인입니다. HTTP resource는
상태의 소유자가 아니라 동일한 owner repository를 노출하는 adapter여야 합니다.

## Checks

```sh
tail -n 200 .tmp/vitalserver-vm-golden/logs/launcher.log
cat .tmp/vitalserver-vm-golden/run/vm-lifecycle.json
```

- VM serial boot output 전에 `/platform/runtime-provider` connection failure가 있는지 확인합니다.
- lifecycle document가 없거나 갱신되지 않았다면 Platform owner repository wiring을 확인합니다.

## Actions

- Golden-rootfs build VM은 `.tmp/.../run/vm-lifecycle.json` compile proof를 사용합니다.
- Installed runtime의 VM launcher, stop workflow, watchdog는 `SQLiteRuntimeVMLifecycleResourceStore`를 통해 `runtime-state.sqlite`에 lifecycle을 직접 기록합니다.
- Runtime Control API의 `/platform/runtime-provider` resource도 installed runtime에서 같은 SQLite repository를 읽고 씁니다.
- 두 환경의 계약을 섞지 않으며 missing, invalid, read, write failure를 성공이나 기본 상태로 바꾸지 않습니다.

수정 후 `make runtime/proof/smoke`로 golden rootfs compile과 golden disk 재부팅
smoke를 모두 확인합니다.

## Prevention

- Platform Agent 소유 상태는 UI process나 HTTP listener의 생명주기에 두지 않습니다.
- API, CLI, launcher, watchdog는 하나의 명시적인 durable owner repository를 공유합니다.
- VM compile은 UI를 실행하지 않은 headless 환경에서 검증합니다.
- Windows Service와 systemd service 구현도 Runtime Provider 상태를 동일한 Platform
  계약으로 제공하고, UI는 그 계약의 consumer로만 둡니다.

## Operational Notes

이 수정은 lifecycle 문서를 새로 소유하는 변경이며 VM disk나 Product Stack data를
삭제하지 않습니다. 기존 lifecycle 문서가 invalid하면 decode failure를 명시적으로
보고하고 자동으로 `stopped`를 추측하지 않습니다.

## Related Cases

- TS-071: golden rootfs apt snapshot fast-fail
- TS-076: update shutdown compose stop timeout

## Follow-up

- 2026-07-11: UI-hosted API 의존을 durable lifecycle owner repository로 교체했습니다.
- 2026-07-11: golden rootfs와 golden disk runtime boot smoke 통과를 확인했습니다.
- 2026-07-11: API listener를 launchd KeepAlive
  `vitalserver-platform-agent` process로 분리하고 Control Panel을 consumer-only로
  변경했습니다. Headless HTTP E2E와 signed app bundle 포함을 확인했습니다.
