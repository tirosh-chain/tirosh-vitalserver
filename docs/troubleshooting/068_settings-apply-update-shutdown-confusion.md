# Settings Apply Enters Update-Like Shutdown

> ID: TS-068  
> Category: Runtime health / Runtime Control PWA  
> Owner: Settings apply / macOS runtime watchdog  
> Status: resolved

## Symptom

Settings에서 vital files directory 같은 설정만 바꿔 Apply 했는데 VM이 내려가고, UI나 logs가 update 중인 것처럼 보입니다.
helper message log에는 다음과 같은 메시지가 반복될 수 있습니다.

```text
waiting for guest update shutdown worker
Redis backup completed. Stopping guest services.
```

status가 `updating` 또는 operation `apply-bundle`처럼 보이면 설정 적용과 update bundle 적용의 경계가 흐려집니다.

## Cause

두 가지가 겹쳤습니다.

1. `RuntimeSettings.restartAfterSave` 기본값이 `true`라 Settings read model이 명시 저장값 없이도 restart를 요청했습니다.
2. Settings restart가 guest shutdown worker를 재사용하면서 shutdown progress status를 `.updating / .applyBundle`로 하드코딩했습니다.

따라서 settings apply가 실제 update bundle을 적용하지 않는데도 update 상태처럼 기록될 수 있었습니다.

## Fix Direction

- Settings apply의 `restartAfterSave` 기본값은 `false`입니다.
- `restartAfterSave`는 "저장 후 항상 restart"가 아니라, Configure 정책이 VM runtime restart를 요구할 때 즉시 restart할지에 대한 사용자 의도입니다.
- VM runtime restart가 필요한 설정은 CPU, memory, disk increase, network mode, bridged interface, vital files directory 변경입니다.
- URL, admin password, start on boot, auto recovery, sleep prevention, VitalServer Helper backup retention 같은 설정은 VM runtime restart requirement를 만들지 않습니다.
- guest shutdown workflow는 progress status와 operation을 context로 받습니다.
- update bundle shutdown은 기존처럼 `.updating / .applyBundle`을 기록합니다.
- settings restart shutdown은 `.recovering / .configure`를 기록합니다.

## Prevention Principle

- UI 또는 API는 restart intent를 default로 생성하지 않습니다.
- Configure 정책은 제출된 필드 이름만 보지 않고, Host가 제공한 명시적 현재 상태와 planned state의 차이를 비교합니다.
- settings apply, update apply, repair는 guest shutdown mechanism을 공유할 수 있지만 operation/status는 caller가 명시적으로 제공합니다.
- shared worker name이나 log phrase만 보고 operation state를 추정하지 않습니다.

## 2026-06-13 Follow-up: Failed Apply Must Not Mutate Local Presentation State

### Symptom

Advanced network의 advertised service URL이 비어 있거나 invalid인 상태에서 Settings Apply를 눌러도
사용자에게 명확한 실패 상태가 보이지 않고, 일부 local API 설정은 적용된 것처럼 보일 수 있었습니다.

### Cause

Control Panel host composition이 CLI `configure` 결과를 받은 뒤 `exitCode`를 확인하지 않고
`localAPISettings.apply(settings:)`를 호출했습니다. 따라서 command boundary에서는 실패한 설정이
presentation-local state에 성공처럼 반영될 수 있었습니다.

### Fix Direction

Local API port 같은 presentation-local 설정은 `applySettings` command가 성공한 경우에만 갱신합니다.
command failure response는 그대로 UI로 전달되어야 하며, local coordinator가 실패한 draft 값을 현재
상태로 승격하면 안 됩니다.

### Prevention Principle

- Command result owner가 실패를 반환하면 composition/presentation 계층은 local state를 성공처럼 mutate하지 않습니다.
- Missing, invalid, failed, saved, applied, draft settings는 서로 다른 의미이며 refresh 또는 display 보정으로 합치지 않습니다.
- Settings apply 실패 case test는 response preservation과 local state non-mutation을 함께 검증합니다.
