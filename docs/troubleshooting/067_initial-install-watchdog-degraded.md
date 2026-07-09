# Initial Install Shows Degraded During VM Bootstrap

> ID: TS-067  
> Category: Runtime health / Packaging  
> Owner: macOS runtime watchdog  
> Status: resolved

## Symptom

초기 설치 직후 Helper 또는 status command가 잠시 `Degraded`를 표시합니다. watchdog log에는 다음과 같은 deferred recovery 메시지가 남습니다.

```text
watchdog recovery deferred: vm-lifecycle-bootstrapping
```

이후 VM과 guest service가 준비되면 `Healthy`로 전환되지만, 설치 직후 사용자는 설치가 실패한 것처럼 볼 수 있습니다.

## Cause

설치 workflow는 package/runtime 파일 배치가 끝난 뒤 runtime status projection을 `initializing`으로 기록하고, active operation은 Host operation lease가 소유합니다. 이 상태에서 VM lifecycle은 아직 `bootstrapping`일 수 있고, Guest HTTP, Host proxy, Guest readiness 관측은 아직 실패할 수 있습니다.

watchdog recovery policy는 이 구간을 복구 대상이 아니라 deferred recovery로 판단하지만, 기존 runner는 deferred observation status를 무조건 `degraded`로 저장했습니다. 초기 설치 상태와 active operation ownership이 status projection과 섞여 있던 구조에서는 watchdog 관측 결과가 표시 상태와 작업 소유권을 덮어쓸 수 있었습니다.

## Fix Direction

watchdog runner는 active operation을 Host operation lease에서만 판단하고, status projection이나 install-state artifact에서 operation을 추론하지 않습니다. deferred recovery event는 남기되, 초기 설치/managed operation 소유권은 lease가 제공하는 명시 상태를 따르고 install state document는 diagnostics/export artifact로만 남깁니다.

missing, failed, non-install status는 보정하지 않습니다. 그런 경우 watchdog deferred observation은 explicit policy 결과로만 기록됩니다.

## Prevention Principle

- watchdog은 recovery 이벤트를 기록할 수 있지만, 초기 설치 상태를 추정하거나 생성하지 않습니다.
- 초기 설치 상태는 install workflow/operation-state owner가 제공한 explicit state로 판단합니다. `runtime-status.json`은 diagnostics/status projection이며 current operation owner가 아닙니다.
- status read failure나 missing document를 `initializing`으로 보정하지 않습니다.
- bootstrapping defer와 실제 degraded 상태는 owner-provided current status로만 구분합니다.

## Verification

초기 설치 직후 다음 순서가 유지되는지 확인합니다.

1. package/runtime 파일 배치 중 status는 `installing`입니다.
2. install provision 완료 후 VM이 준비되는 동안 status는 `initializing`입니다.
3. watchdog은 `recovery-deferred` event를 기록할 수 있지만 status를 `degraded`로 낮추지 않습니다.
4. guest readiness가 정상화되면 status는 `healthy`로 전환됩니다.
