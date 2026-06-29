# Helper Settings Slider Crash

> ID: TS-096  
> Category: Runtime health / macOS Helper UI  
> Owner: macOS Helper Settings presentation  
> Status: active

## Symptoms

- VitalServer Helper가 Settings에서 VM 설정 또는 `.vital` file path 설정을 변경한 직후 종료됩니다.
- macOS crash report에 아래 frame이 보입니다.

```text
Exception Type: EXC_BREAKPOINT (SIGTRAP)
SwiftUI Normalizing.init(min:max:stride:)
SwiftUI Slider.init(...)
RuntimeSettingsPanel.settingSliderControl(value:range:step:suffix:)
```

## Impact

- VM이나 guest container가 직접 종료된 증거는 아닙니다.
- Helper UI process가 종료되므로 사용자는 Settings 적용 결과와 runtime 상태를 앱에서 확인할 수 없습니다.
- 저장된 runtime settings에 범위 밖 numeric value가 남아 있으면 Helper를 다시 열 때 Settings 화면 렌더 중 같은 crash가 반복될 수 있습니다.

## Cause

Settings UI가 provider-owned settings 값을 SwiftUI `Slider`에 직접 전달했습니다. 저장된 설정 또는 읽기 중인 draft 값이 slider range 밖이거나, VM memory 계산 때문에 slider range가 단일값이 되면 SwiftUI가 `max stride must be positive` precondition으로 process를 종료합니다.

Presentation layer가 invalid settings state를 만들지는 않았지만, invalid 값을 표시하기 전에 Slider contract 위반으로 crash했습니다.

## Checks

Crash report:

```sh
log show --predicate 'process == "VitalServer Helper"' --last 1h
```

최근 crash report:

```sh
ls -lt ~/Library/Logs/DiagnosticReports/*VitalServer*Helper*.crash
```

설치 runtime 상태는 Helper UI 대신 CLI로 확인합니다.

```sh
vitalserver-vm runtime health
```

## Actions

1. 최신 Helper app 또는 update bundle로 교체합니다.
2. Helper가 계속 Settings 화면에서 종료되면 CLI로 runtime health를 먼저 확인하고, Settings 변경을 다시 적용하기 전에 저장된 settings JSON의 numeric field가 범위 밖인지 확인합니다.
3. Settings 화면이 열리면 validation message를 확인하고, VM CPU/memory/disk, backup retention, log archive, container memory limit 값을 허용 범위 안으로 저장합니다.

## Prevention

- Settings presentation은 Slider에 provider value를 직접 넣지 않습니다.
- Slider display binding은 렌더 전에 value를 range로 clamp합니다.
- Slider range가 단일값이면 SwiftUI `Slider`를 렌더하지 않고 비활성 placeholder를 표시합니다.
- Regression test는 out-of-range Settings snapshot으로 `RuntimeSettingsPanel`을 렌더해 SIGTRAP이 재발하지 않는지 확인합니다.

## Operational Notes

- 이 문제는 UI crash이며 VM compile/runtime failure proof가 아닙니다. VM 상태는 CLI 또는 runtime status 파일로 별도 확인합니다.
- invalid settings는 success/default로 숨기지 말고 Settings validation 또는 read issue로 표시해야 합니다.

## Related Cases

- TS-034: Runtime Control Helper read permission failures
- TS-039: Settings/PWA fallback audit

## Follow-up

- 2026-06-29: 다른 Mac에서 Helper `0.1.17` crash report를 확인했습니다. `RuntimeSettingsPanel` slider-safe binding과 out-of-range render regression test를 추가했습니다.
