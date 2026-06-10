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
- URL, admin password, start on boot, auto recovery, sleep prevention, Redis backup retention 같은 설정은 VM runtime restart requirement를 만들지 않습니다.
- guest shutdown workflow는 progress status와 operation을 context로 받습니다.
- update bundle shutdown은 기존처럼 `.updating / .applyBundle`을 기록합니다.
- settings restart shutdown은 `.recovering / .configure`를 기록합니다.

## Prevention Principle

- UI 또는 API는 restart intent를 default로 생성하지 않습니다.
- Configure 정책은 제출된 필드 이름만 보지 않고, Host가 제공한 명시적 현재 상태와 planned state의 차이를 비교합니다.
- settings apply, update apply, repair는 guest shutdown mechanism을 공유할 수 있지만 operation/status는 caller가 명시적으로 제공합니다.
- shared worker name이나 log phrase만 보고 operation state를 추정하지 않습니다.
