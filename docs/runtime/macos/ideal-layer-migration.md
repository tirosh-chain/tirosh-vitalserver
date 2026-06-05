# macOS Runtime Ideal Layer Migration

이 문서는 GitHub issue #47의 구현 준비 문서입니다. 목적은 macOS runtime을 Clean Architecture/DDD에 가까운 레이어 구조로 수렴시키되, 기존 runtime 동작을 한 번에 갈아엎지 않고 operation 단위로 검증 가능한 migration을 진행하는 것입니다.

## 현재 위치

현재 코드는 이미 다음 기반을 갖고 있습니다.

- `Contracts`: 공유 document, command, event, state 계약
- `Core`: pure policy, state machine, verification
- `Application`: 일부 usecase
- `RuntimeWorkflow`: operation order, progress, completion gate 일부
- `HostCLI`: CLI parsing, composition, host adapter/effect ownership
- `HostInfrastructure`: repository/filesystem infrastructure
- `MacHostRuntimeAdapter`, `MacRuntimeControlApp`, `RuntimeControlAPI`: app/API/UI boundary

TS-048에서는 HostCLI/Runtime fragmentation을 줄이고 일부 install/apply-bundle effect를 HostCLI 쪽 concrete adapter 영역으로 되돌렸다. 그러나 #47의 목표 관점에서는 아직 `Application/UseCase`, `HostAdapters`, `Interfaces`, `Bootstrap/DI`가 명시적이고 균일한 구조로 분리되어 있지 않습니다.

## 목표 구조

최종적으로는 아래 구조를 목표로 합니다.

```text
apps/vitalserver-macos-runtime/
  Sources/
    Contracts/
      Documents/
      Commands/
      Events/
      Errors/

    Domain/
      Models/
      Policies/
      StateMachines/
      Invariants/

    Application/
      UseCases/
        RuntimeServices/
        RuntimeHealth/
        ConfigureRuntime/
        InstallRuntime/
        ApplyRuntimeBundle/
        UninstallRuntime/
        RepairRuntime/
      Ports/

    Workflow/
      RuntimeServiceLifecycle/
      RuntimeHealth/
      RuntimeConfigureLifecycle/
      RuntimeInstallLifecycle/
      RuntimeUpdateLifecycle/
      RuntimeUninstallLifecycle/
      RuntimeRepairLifecycle/

    Infrastructure/
      FileSystem/
      Repositories/
      ObservabilityStore/
      PackageReceipts/

    HostAdapters/
      Launchd/
      Process/
      Hdiutil/
      Pkgutil/
      Virtualization/
      CloudInit/

    Interfaces/
      HostCLI/
      RuntimeControlAPI/
      MacRuntimeControlApp/

    Bootstrap/
      DI/
      Composition/
```

## Dependency Direction

의존성은 안쪽으로만 흐릅니다.

```text
Contracts
  <- Domain
    <- Application
      <- Workflow
        <- Interfaces
        <- Bootstrap

Infrastructure/HostAdapters는 Application/Workflow port를 구현하고,
Bootstrap/DI에서 concrete implementation으로 조립합니다.
```

레이어별 규칙은 다음과 같습니다.

- `Contracts`는 shared explicit contract만 둡니다. missing, invalid, failed, stale, zero, empty 의미를 합치지 않습니다.
- `Domain`은 pure model, policy, state machine, invariant만 둡니다. Host, Guest, filesystem, process, network, logs, command output을 읽지 않습니다.
- `Application`은 usecase와 port contract를 둡니다. operation intent, explicit state read, domain decision, port command dispatch를 소유합니다.
- `Workflow`는 step order, progress, persisted workflow state, completion gate를 소유합니다. command success를 final state로 추론하지 않습니다.
- `Infrastructure`와 `HostAdapters`는 concrete filesystem/process/launchd/pkgutil/hdiutil/Virtualization.framework effect를 소유합니다.
- `Interfaces`는 CLI/API/UI input mapping과 output formatting만 담당합니다.
- `Bootstrap`은 concrete adapter와 usecase/workflow 조립을 담당합니다.

## Migration Strategy

큰 폴더 rename으로 시작하지 않습니다. 기존 runtime을 유지한 상태에서 vertical slice 단위로 새 구조를 도입합니다.

1. Boundary tests를 먼저 확장합니다.
2. operation별 `UseCase + Ports`를 만듭니다.
3. 기존 HostCLI composition을 새 usecase/workflow 조립으로 대체합니다.
4. 기존 workflow와 새 workflow의 parity test를 둡니다.
5. operation path를 새 구현으로 전환합니다.
6. 전환된 기존 구현은 제거하거나 deprecated shim으로 축소합니다.
7. 충분한 operation이 이동한 뒤 `Core -> Domain`, `RuntimeWorkflow -> Workflow`, `HostCLI -> Interfaces/HostAdapters/Bootstrap` rename을 진행합니다.

## Recommended Slices

### Slice 1: Configure + ServiceLifecycle + HealthWait

첫 브랜치에서는 아래 세 영역을 같이 옮기는 것이 좋습니다.

- `ConfigureRuntimeUseCase`
- `ControlRuntimeServicesUseCase`
- `WaitForRuntimeHealthUseCase`
- `RuntimeConfigureLifecycle`
- `RuntimeServiceLifecycle`
- `RuntimeHealth`

이 slice는 작지만 구조적 효과가 큽니다. Settings/UI/API/CLI와 연결되어 있고, advertised URL validation, admin password reset, proxy port update, restart decision, health completion gate를 모두 테스트할 수 있습니다.

완료 기준:

- HostCLI configure path는 command parsing과 composition만 담당합니다.
- Configure validation과 document mutation decision은 Application/Workflow/Core에서 테스트됩니다.
- service restart completion은 explicit required service observation으로 판단합니다.
- health wait는 service read failure, permission denied, missing, not-loaded를 구분합니다.
- 기존 configure runner와 새 구조 사이 parity test가 있습니다.

### Slice 2: InstallRuntime

- install settings
- VM config mutation
- cloud-init seed
- directory/executable/permission setup
- service start
- health completion gate

완료 기준:

- install workflow의 transition rule은 Domain state machine에 있습니다.
- cloud-init access는 explicit SSH key contract만 허용하고 password access를 열지 않습니다.
- Host adapters는 filesystem/process/hdiutil/launchd effect만 구현합니다.

### Slice 3: ApplyRuntimeBundle

- bundle materialize/verify/stage
- artifact replacement
- guest shutdown/activation
- rollback trigger

완료 기준:

- archive safety, checksum, manifest compatibility는 pure policy 또는 workflow port boundary에서 검증됩니다.
- update stop phase는 command return이 아니라 explicit VM stopped lifecycle observation으로 완료됩니다.
- rollback trigger와 rollback failure status가 테스트됩니다.

### Slice 4: UninstallRuntime

- service stop
- package receipt state
- artifact absence observation
- clean uninstall state

완료 기준:

- uninstall cleanup은 explicit artifact/receipt absence로 완료됩니다.
- permission/read/decode failure는 success로 변환되지 않습니다.

### Slice 5: RepairRuntime

- VM disk repair
- datastore/redis repair
- attachability/result observation
- recovery status

완료 기준:

- repair command success와 final repair success가 분리됩니다.
- repair result와 attachability observation이 명시적으로 테스트됩니다.

## Testing Strategy

목표는 “실제 macOS/VM이 필요한 영역”을 최소화하는 것입니다.

| Layer | 테스트 방식 |
|---|---|
| Contracts | decode/encode, required field, unknown value, migration boundary |
| Domain | pure unit test, state transition, invariant |
| Application | fake port 기반 usecase test |
| Workflow | fake repository/adapter/clock 기반 step order, failure transition, completion gate |
| Infrastructure/HostAdapters | temp directory, fake process runner, plist/json fixture |
| Interfaces | CLI parsing, API request mapping, UI/read model formatting |
| Bootstrap | composition smoke test |
| Platform E2E | actual VM boot, launchd system domain, pkg receipt, hdiutil seed image recognition, guest Docker/systemd |

현실적인 목표는 운영 로직의 대부분을 unit/workflow/adapter test로 검증하고, 실제 VM/launchd/pkg/hdiutil은 smoke/e2e로 남기는 것입니다.

## Boundary Test Roadmap

현재 branch에서는 미래 구조를 위한 guard만 준비합니다. 새 폴더가 생기면 아래 규칙이 즉시 적용되어야 합니다.

- `Domain`은 `Application`, `Workflow`, `Infrastructure`, `HostAdapters`, `Interfaces`, `Bootstrap`을 import하지 않습니다.
- `Application`은 `Workflow`, `Infrastructure`, `HostAdapters`, `Interfaces`, `Bootstrap`을 import하지 않습니다.
- `Workflow`는 `Infrastructure`, `HostAdapters`, `Interfaces`, `Bootstrap`을 import하지 않습니다.
- `Infrastructure`와 `HostAdapters`는 UI/API/CLI presentation을 import하지 않습니다.
- `Interfaces`는 concrete platform effect를 직접 실행하지 않고 port/usecase/workflow를 호출합니다.
- `Bootstrap`만 concrete adapter와 workflow/usecase를 조립합니다.

## Out Of Scope For This Branch

이 branch에서는 #47 구현을 시작하지 않습니다.

- 새 runtime operation 구현을 만들지 않습니다.
- `Core -> Domain` rename을 하지 않습니다.
- `RuntimeWorkflow -> Workflow` rename을 하지 않습니다.
- `HostCLI` 대이동을 하지 않습니다.
- 기존 configure/install/apply/uninstall 동작을 전환하지 않습니다.

이 branch의 목적은 다음 branch에서 #47을 시작할 수 있도록 migration map과 boundary guard를 준비하는 것입니다.

## References

- GitHub issue #47: macOS runtime을 이상적 레이어 구조로 수렴
- `docs/troubleshooting/048_hostcli-runtime-workflow-boundary-fragmentation.md`
- `docs/troubleshooting/043_runtime-workflow-state-machine-layer-boundary.md`
- `docs/troubleshooting/045_runtime-install-workflow-state-machine-parity.md`
- `docs/troubleshooting/047_guest-log-sync-stopped-after-restart.md`
- `docs/troubleshooting/032_macos-runtime-explicit-responsibility-review.md`
- `docs/troubleshooting/039_agents-compliance-fallback-audit.md`
