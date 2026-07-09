# macOS Runtime Ideal Layer Migration

이 문서는 GitHub issue #47의 구현 준비 문서입니다. 목적은 macOS runtime을 Clean Architecture/DDD에 가까운 레이어 구조로 수렴시키되, 기존 runtime 동작을 한 번에 갈아엎지 않고 operation 단위로 검증 가능한 migration을 진행하는 것입니다.

## 현재 위치

현재 코드는 이미 다음 기반을 갖고 있습니다.

- `Contracts`: 공유 document, command, event, state 계약. HostCLI configure와 runtime settings가 함께 쓰는 `RuntimeNetworkMode` 같은 closed enum도 여기 둡니다.
- `Domain`: #47 최종 구조의 pure model/policy/state-machine/invariant skeleton과 configure/service/health/install/update/repair policy, status document builder, operation plan, transition state machine
- `Application`: service/health usecase와 #47 `ConfigureRuntimeUseCase`, `InstallRuntimeUseCase`, external state/effect port contracts; 더 이상 `Core` target에 의존하지 않음
- `Core`: 전환기 legacy compatibility shim. 현재 `Core/Sources`의 public 선언은 `Contracts`, `Domain`, `Application/Ports` typealias만 남깁니다.
- `Workflow`: #47 최종 구조의 operation lifecycle skeleton과 이주된 `RuntimeConfigureLifecycle`, `RuntimeServiceLifecycle`, `RuntimeHealth`, `RuntimeInstallLifecycle`, `RuntimeUpdateLifecycle`, `RuntimeUninstallLifecycle`, `RuntimeRepairLifecycle`, `RuntimeWatchdog` 단위
- `Infrastructure`: filesystem, guest config reading/writing, repository, Redis backup result document loading, SQLite observability/read-model implementation
- `HostAdapters`: launchd/process/cloud-init/install host adapter implementation
- `Interfaces`, `Bootstrap`: #47 최종 구조로 이동할 outer-layer skeleton
- `HostCLI`: CLI entrypoint and transitional composition shims
- `RuntimeControlAPI`: 전환기 legacy compatibility shim. 현재 public 선언은 `Interfaces/RuntimeControlAPI` typealias만 남깁니다.
- `MacHostRuntimeAdapter`, `MacRuntimeControlApp`: app/API/UI boundary

TS-048에서는 HostCLI/Runtime fragmentation을 줄이고 일부 install/apply-bundle effect를 HostCLI 쪽 concrete adapter 영역으로 되돌렸다. 그러나 #47의 목표 관점에서는 아직 `Application/UseCase`, `HostAdapters`, `Interfaces`, `Bootstrap/DI`가 명시적이고 균일한 구조로 분리되어 있지 않습니다.

2026-06-05 현재 #47은 skeleton-first migration으로 시작했습니다. 새 ideal layer target과 folder root는 SwiftPM과 boundary test에 반영했고, `RuntimeConfigureWorkflow`는 `Workflow/RuntimeConfigureLifecycle`에, `RuntimeServiceLifecycleWorkflow`는 `Workflow/RuntimeServiceLifecycle`에, `RuntimeHealthWaitWorkflow`, `RuntimeHealthRefreshWorkflow`, `RuntimeGuestRuntimeStateObservationReader`는 `Workflow/RuntimeHealth`에 배치했습니다. install 쪽에서는 `InstallRuntimeUseCase`를 Application boundary로 추가했고, `RuntimeInstallWorkflow`, `RuntimeInstallDirectoryPreparer`, `RuntimeInstallSettingsCleaner`, `RuntimeInstallServiceStarter`, `RuntimeInstallVMRuntimeConfigurator`, `RuntimeInstallStepExecutor`를 `Workflow/RuntimeInstallLifecycle`로 옮겼습니다. update/apply-bundle/rollback 쪽에서는 `UpdateBundleVerifier`, `UpdateBundleArchiveVerifier`, `UpdateBundleChecksumFileParser`, `RuntimeUpdateCompatibilityChecker`, `RuntimeUpdatePreflightPolicy`, `GuestActivationEvaluator`, `GuestShutdownEvaluator`를 `Domain/Policies`로, `ApplyBundlePreflightContext`, `RollbackPreflightContext`, `RuntimeOperationPlanRunner`를 `Domain/Models`로 옮기고, `RuntimeApplyBundlePreflightRunner`, `RuntimeApplyBundleRunner`, `RuntimeApplyBundleStepExecutor`, `RuntimeApplyBundleWorkflow`, `RuntimeRollbackPreflightRunner`, `RuntimeRollbackRunner`, `RuntimeRollbackStepExecutor`, `RuntimeRollbackWorkflow`, `RuntimeBundlePreparationWorkflow`, `RuntimeBundleStager`, `RuntimeBundleDigestVerifier`, `RuntimeBundleDirectoryVerifier`, `RuntimeBundleMaterializer`, `RuntimeArtifactReplacer`, `RuntimeMigrationRunner`, `RuntimeGuestCapabilityChecker`, `RuntimeGuestCapabilityCheckError`, `RuntimeGuestActivationRunner`, `RuntimeGuestActivationWorkflow`, `RuntimeGuestShutdownRunner`, `RuntimeGuestShutdownWorkflow`를 `Workflow/RuntimeUpdateLifecycle`로 옮겼습니다. uninstall 쪽에서는 `RuntimeUninstallWorkflow`를 `Workflow/RuntimeUninstallLifecycle`로 옮겼고, repair/maintenance 쪽에서는 `DatastoreRepairEvaluator`를 `Domain/Policies`로, `RuntimeRedisBackupWorkflow`, `RuntimeDatastoreRepairResultWaiter`, `RuntimeDatastoreRepairRunner`, `RuntimeDatastoreRepairWorkflow`, `RuntimeVMDiskRepairRunner`를 `Workflow/RuntimeRepairLifecycle`로 옮겼습니다. watchdog 쪽에서는 `RuntimeRecoveryPlanner`, `RuntimeWatchdogRecoveryPolicy`를 `Domain/Policies`로 옮기고 `RuntimeWatchdogRunner`, `RuntimeManagedOperationGuard`을 `Workflow/RuntimeWatchdog`로 옮겼습니다. shared progress event, process result, guest document load result, proxy nginx PID read result, runtime network mode contract는 `Contracts/RuntimeStepExecutionEvent`, `Contracts/RuntimeProcessResult`, `Contracts/RuntimeGuestDocumentLoadResult`, `Contracts/RuntimeProxyNginxPIDReadResult`, `Contracts/RuntimeNetworkMode`로 이동했고, `RuntimeCommandExecutor`, `RuntimeCommandExecutionError`, `RuntimeWorkflowStatusReporter`, `RuntimeStatusReporter`, `RuntimeStatusWriter`, `RuntimeEventFactory`, `RuntimeObservationRecorder`, `RuntimeEventPublisher`, `RuntimeObservedEventPublisher`, `RuntimeObservedStatusPublisher`, `RuntimeVitalDBObservationProjector`, `writeRuntimeStatusBestEffort`, `writeRuntimeProgressBestEffort`, `recordRuntimeObservedEventBestEffort`는 `Workflow/RuntimeShared`에 있습니다. advertised URL validation과 compatibility endpoint 결정은 `Domain/Policies/RuntimeAdvertisedURLPolicy`로, service lifecycle completion gate는 `Domain/Policies/RuntimeServiceLifecycleCompletionPolicy`로, health evaluator/VM health/status document/event type/provision payload/managed operation/health wait/snapshot/observation 정책은 `Domain`으로 이동했습니다. external state/effect port protocols는 `Application/Ports`로 이동했습니다. filesystem, installed-path, JSON repository/gateway, JSONL/SQLite event repository, SQLite observability/read-model implementation, log rotation, guest log collection/config reading/writing, fresh-install settings/artifact state readers, runtime storage filesystem maintenance, package receipt state reader, install/uninstall state stores, runtime version store, VM lifecycle store, backup store, Redis backup result reader, health snapshot assembly는 `Infrastructure`로 이동했고, 기존 `HostInfrastructure` public API는 typealias shim으로 유지합니다. `Command`, `LauncherError`, `RuntimeConfigFlagReader`, `RuntimeConfigFlagValues`, `RuntimeInstallSettings`, `RuntimeInstallSettingsDefaults`, `RuntimeInstallSettingsError`, `RuntimeServiceControlCommand`, `RuntimeServiceControlRunner`, `RuntimeConfigureCommand`, `RuntimeConfigureChange`, `RuntimeLifecycleCommand`, `RuntimeLifecycleCommandParseError`, `RuntimeStatusPrinter`, `RuntimeHealthCheckRunner`, `RuntimeHealthCheckRunnerError`, `RuntimeHealthWaitRunner`, `RuntimeHealthWaitRunnerError`는 `Interfaces/HostCLI`로, Runtime Control HTTP/API/transport/test-kit implementation은 `Interfaces/RuntimeControlAPI`로 이동했고, 기존 `RuntimeControlAPI` public API는 typealias shim으로 유지합니다. process/HTTP/launchd/timing concrete adapters인 `VMRuntimeConfig`, `NetworkConfig`, `SharedDirectoryConfig`, `VMConfigurationFactory`, `VirtualMachineDelegate`, `VirtualMachineTerminationHandler`, `ProcessState`, `ProcessStateError`, `SystemRuntimeCommandRunner`, `CurlRuntimeHTTPProber`, `RuntimeHostProxyPortCleaner`, `RuntimeHostProxyPortCleanerError`, `RuntimeHostProxyPortStateReader`, `LaunchdRuntimeServiceManager`, `RuntimeServiceController`, `RuntimeServiceControllerError`, `SystemRuntimeClock`, `ThreadRuntimeSleeper`는 `HostAdapters`로 이동했고, 기존 `HostCLI` names는 typealias shim으로 유지합니다. Runtime Control app read-model/selection/test-kit policy인 `RuntimeControlStatusAnnotator`, `RuntimeActiveOperationPolicy`, `RuntimeBackupSelectionPolicy`, `RuntimeViewModelBackupActionPlanner`, `RuntimeViewModelTestKitStatePolicy`, `RuntimeViewModelObservabilityRefresher`, `RuntimeStatusUptimeFormatter`, `RuntimeStatusReachabilityPolicy`, `RuntimeStatusReachabilityLabelPolicy`, `RuntimeStatusServiceValuePolicy`, `RuntimeStatusHTTPValuePolicy`, `RuntimeStatusComposeServiceValuePolicy`, `RuntimeStatusHealthDetailsPolicy`, `RuntimeStatusAdvancedServiceHealthPolicy`, `RuntimeStatusVitalServerAvailabilityPolicy`, `RuntimeStatusRemoteConsoleAvailabilityPolicy`, `RuntimeStatusVMStatePolicy`, `RuntimeStatusOverallHealthPolicy`, `RuntimeStatusActionNeededPolicy`, `RuntimeStatusRecorderSummaryPolicy`, `RuntimeVitalRecorderDisplayPolicy`, `RuntimeProcessMessageFormatter`, `RuntimePresentationFormatter`, `RuntimeLogExportDestinationPolicy`, `RuntimeVitalFilesDirectoryPolicy`, `RuntimeSection`, `RuntimeSettingsValidator`는 `Interfaces/MacRuntimeControlApp`로 이동했고, 기존 `MacRuntimeControlApp` names는 typealias shim으로 유지합니다. start-on-boot와 sleep-prevention 조합이 sleep-prevention service를 enable할지 disable할지 결정하는 규칙은 `Domain/Policies/RuntimeInstallStartOnBootPolicy`로, operation step sequence와 install transition rule은 `Domain/Models/RuntimeOperationPlan` 및 `Domain/StateMachines/RuntimeInstallTransitionPolicy`로 분리했습니다. `Core`의 기존 public API 파일은 compatibility typealias만 남깁니다. transitional `RuntimeWorkflow` target은 제거되었습니다. 기존 `Core`, `HostCLI`, `HostInfrastructure`, `RuntimeControlAPI`, `MacRuntimeControlApp` target은 operation 단위 migration이 끝날 때까지 전환기 target으로 유지합니다.

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
      RuntimeWatchdog/
      RuntimeShared/

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
- `Bootstrap`은 runtime constants/generated version constants, VM runtime config product defaults/read validation composition, runtime managed-service launchd path composition, runtime health checker product context composition, cloud-init seed product composition, service-control runner composition, status-printer composition, health-check runner composition, managed-operation guard composition, runtime lifecycle composition, configure composition, install composition, Redis backup composition, update bundle composition, concrete adapter와 usecase/workflow 조립을 담당합니다.

## Migration Strategy

큰 폴더 rename으로 시작하지 않습니다. 기존 runtime을 유지한 상태에서 skeleton-first + vertical slice 단위로 새 구조를 도입합니다.

1. Ideal layer target/folder skeleton을 먼저 만들고 SwiftPM target graph로 dependency direction을 드러냅니다.
2. Boundary tests를 확장해 skeleton 존재와 import 방향을 고정합니다.
3. operation별 `UseCase + Ports`를 만듭니다.
4. 기존 HostCLI composition을 새 usecase/workflow 조립으로 대체합니다.
5. 기존 workflow와 새 workflow의 parity test를 둡니다.
6. operation path를 새 구현으로 전환합니다.
7. 전환된 기존 구현은 제거하거나 deprecated shim으로 축소합니다.
8. 충분한 operation이 이동한 뒤 `Core -> Domain`, `HostCLI -> Interfaces/HostAdapters/Bootstrap` rename을 진행합니다.

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
- service restart completion은 `Domain` completion policy가 explicit required service observation으로 판단합니다.
- health wait는 `Domain` health wait policy가 service read failure, permission denied, missing, not-loaded를 구분합니다.
- 기존 configure runner와 새 구조 사이 parity test가 있습니다.

### Slice 2: InstallRuntime

- install settings
- VM config mutation
- cloud-init seed
- directory/executable/permission setup
- service start
- health completion gate

완료 기준:

- install workflow의 transition rule은 `Domain/StateMachines/RuntimeInstallTransitionPolicy`에 있습니다.
- operation step sequence와 plan validation은 `Domain/Models/RuntimeOperationPlan`에 있습니다.
- cloud-init access는 explicit SSH key contract만 허용하고 password access를 열지 않습니다.
- Host adapters는 filesystem/process/hdiutil/launchd effect만 구현합니다.

현재 전환 상태:

- `InstallRuntimeUseCase`는 `Application/UseCases/InstallRuntime`에 있습니다. `Bootstrap/Composition/RuntimeInstallComposition`은 install mode intent를 usecase port로 넘긴 뒤 `RuntimeInstallWorkflow` command로 매핑합니다.
- `RuntimeConfigureComposition`과 `RuntimeConfigureRunner`는 `Bootstrap/Composition`에 있으며 `ConfigureRuntimeUseCase`, `RuntimeConfigureWorkflow`, VM config document reader/writer, service restart effects를 조립합니다. HostCLI는 compatibility alias와 concrete closure injection만 유지합니다.
- `RuntimeServiceControlComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeServiceControlRunner`와 start/stop/status/log/service-state ports를 조립합니다. HostCLI는 compatibility alias만 유지합니다.
- `RuntimeStatusPrinterComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeStatusPrinter`와 product executable paths, proxy health URL, explicit status/version/service/file state ports를 조립합니다. HostCLI는 compatibility alias만 유지합니다.
- `RuntimeWorkflowStatusReporterComposition`과 `RuntimeStatusWriterComposition`은 `Bootstrap/Composition`에 있으며 workflow status/progress reporter와 status writer의 concrete writer, timestamp, runtime version, health snapshot, backup ports를 조립합니다. HostCLI는 compatibility alias와 concrete closure injection만 유지합니다.
- `RuntimeHealthCheckRunnerComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeHealthCheckRunner`, health snapshot, status writer, observed-event writer, best-effort status/event recording helpers를 조립합니다. HostCLI는 compatibility alias만 유지합니다.
- `RuntimeHealthWaitRunnerComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeHealthWaitRunner`, health-wait timeout/polling configuration, service state, health snapshot, best-effort status writer, sleep, log ports를 조립합니다. HostCLI는 compatibility alias와 concrete closure injection만 유지합니다.
- `RuntimeManagedOperationGuardComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeManagedOperationGuard`, status reporter, guest bootstrap read ports, VM lifecycle boot identity, watchdog managed-operation grace window를 조립합니다. HostCLI는 compatibility alias만 유지합니다.
- `RuntimeWatchdogRunnerComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeWatchdogRunner`, log preparation, proxy liveness URL, VM lifecycle store write, status/event recording, recovery sleep, and host restart ports를 조립합니다. HostCLI는 compatibility alias와 concrete closure injection만 유지합니다.
- `RuntimeGuestCapabilityCheckerComposition`은 `Bootstrap/Composition`에 있으며 `RuntimeGuestCapabilityChecker`와 Guest Control capability read port를 조립합니다. HostCLI는 compatibility alias와 concrete Guest Control gateway injection만 유지합니다.
- `RuntimeInstallDirectoryPreparer`, `RuntimeInstallSettingsCleaner`, `RuntimeInstallServiceStarter`, `RuntimeInstallVMRuntimeConfigurator`, `RuntimeInstallStepExecutor`는 `Workflow/RuntimeInstallLifecycle`에 있습니다.
- `RuntimeInstallWorkflow`는 `Workflow/RuntimeInstallLifecycle`에 있으며 Domain transition decision을 실행하고 explicit writer ports로 persisted state/status/progress를 기록합니다.
- `RuntimeFreshInstallPreflightRunner`는 `Workflow/RuntimeInstallLifecycle`에 있으며 Domain preflight policy로 explicit Host-provided settings/artifact/service/receipt/proxy-port state를 조립합니다. `RuntimeFreshInstallPreflightComposition`은 `Bootstrap/Composition`에서 install settings path/default proxy port, product artifact paths, package receipt identifiers, lsof path, and concrete state-reader ports를 조립합니다.
- `RuntimeFreshInstallPreflightPolicy`와 `RuntimeUninstallReadinessPolicy`는 `Domain/Policies`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeUninstallTransitionPolicy`는 `Domain/StateMachines`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeProcessResult`는 workflow와 host adapter가 공유하는 explicit process result contract이므로 `Contracts`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeCommandRunner`, `RuntimeGuestGateway`, `RuntimeFileStore`, `RuntimeStorageUsageProviding`, `RuntimeClock`, `RuntimeSleeper`, `RuntimeHTTPProber`, `RuntimeServiceManager`, `RuntimeStatusArtifactSink`, `RuntimeEventRepository` port protocol은 `Application/Ports`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeUninstallWorkflow`는 `Workflow/RuntimeUninstallLifecycle`에 있으며 Domain transition decision과 explicit Host-provided state/effect ports만 소비합니다. `RuntimeUninstallComposition`은 `Bootstrap/Composition`에서 product/runtime paths, package receipt readers, cleanup artifact state readers, VM process reader, uninstall state writer, filesystem/service/package effects, and diagnostics를 조립합니다.
- `RuntimeBackupStore`와 `RuntimeVersionStore`는 `Infrastructure/Repositories`에 있으며 backup/version document persistence를 소유합니다. `RuntimeBackupStoreComposition`과 `RuntimeVersionStoreComposition`은 `Bootstrap/Composition`에서 installed runtime paths, product artifact names, runtime tool paths, file-store ports, timestamp, chmod command를 조립합니다.
- Redis backup은 Guest Control maintenance API와 `RuntimeGuestControlServiceOperation`을 통해 실행합니다. Host는 VM/shared data staging, Guest Control operation 호출, Host backup manifest 기록만 소유하고 Redis archive 생성과 operation result state는 Guest/Postgres가 소유합니다.
- Datastore repair는 Guest Control maintenance API와 `RuntimeGuestControlServiceOperation`을 통해 실행합니다. `RuntimeDatastoreRepairWorkflow`는 `Workflow/RuntimeRepairLifecycle`에 있으며 VM start/restart selection, proxy/watchdog restart, runtime health gate, status/progress writes를 Host-provided ports로 실행합니다. `RuntimeDatastoreRepairComposition`은 Host aftercare와 Guest Control maintenance API consumer를 조립합니다.
- `RuntimeVMDiskRepairRunner`는 `Workflow/RuntimeRepairLifecycle`에 있으며 rootfs-to-disk replacement order, current disk archive gate, replacement disk completion gate, service restart, and health wait sequencing을 explicit Host-provided filesystem/process/service/status ports로 실행합니다. `RuntimeVMDiskRepairComposition`은 `Bootstrap/Composition`에서 installed runtime paths, rootfs/disk artifact names, disk size/free-space defaults, gunzip/truncate command paths, filesystem/process/service/status ports를 조립합니다.
- `RuntimeRecoveryPlanner`와 `RuntimeWatchdogRecoveryPolicy`는 `Domain/Policies`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeWatchdogRunner`와 `RuntimeManagedOperationGuard`는 `Workflow/RuntimeWatchdog`에 있으며 active operation guard, health observation, recovery suppression/deferral, recovery action dispatch, lifecycle/status/event writes를 explicit Host-provided ports로 실행합니다.
- `UpdateBundleVerifier`와 `UpdateBundleArchiveVerifier`는 `Domain/Policies`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- Guest activation/shutdown은 Guest Control maintenance API와 Guest operation documents를 사용합니다. legacy guest request/result evaluators는 Runtime v2 source에서 제거되었습니다.
- `RuntimeUpdateCompatibilityChecker`, `RuntimeUpdatePreflightPolicy`, `ApplyBundlePreflightContext`, `RollbackPreflightContext`, `RuntimeOperationPlanRunner`는 `Domain`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeHealthEvaluator`, `RuntimeVMHealthPolicy`, `RuntimeStatusDocumentBuilder`, `RuntimeObservedEventTypePolicy`, `RuntimeInstallProvisionPayloadPolicy`, `RuntimeManagedOperationPolicy`, `UpdateBundleChecksumFileParser`는 `Domain`에 있고, 기존 `Core` API는 typealias shim으로 유지합니다. Guest bootstrap result evaluator는 product current-state 입력에서 제거되었고 bootstrap result는 smoke/diagnostics proof artifact로만 남습니다.
- `RuntimeApplyBundlePreflightRunner`, `RuntimeApplyBundleRunner`, `RuntimeApplyBundleStepExecutor`, `RuntimeApplyBundleWorkflow`, `RuntimeRollbackPreflightRunner`, `RuntimeRollbackRunner`, `RuntimeRollbackStepExecutor`, `RuntimeRollbackWorkflow`, `RuntimeBundlePreparationWorkflow`, `RuntimeBundleStager`, `RuntimeBundleDigestVerifier`, `RuntimeBundleDirectoryVerifier`, `RuntimeBundleMaterializer`, `RuntimeArtifactReplacer`, `RuntimeMigrationRunner`, `RuntimeGuestCapabilityChecker`, `RuntimeGuestActivationRunner`, `RuntimeGuestActivationWorkflow`, `RuntimeGuestShutdownRunner`, `RuntimeGuestShutdownWorkflow`는 `Workflow/RuntimeUpdateLifecycle`에 있으며 materialize, verify, stage, cleanup order, managed bundle staging, preflight storage/capability gates, apply/rollback plan execution, rollback/degraded/critical handling, digest checks, directory verification, archive extraction order, migration executable gate/dispatch, artifact payload validation/replacement, Guest Control capability gate, guest shutdown/activation wait orchestration을 explicit operation ports로 실행합니다. `RuntimeBundleComposition`은 `Bootstrap/Composition`에서 update bundle workflow들과 host file/process/storage/status ports를 조립하고, `RuntimeGuestActivationComposition`과 `RuntimeGuestShutdownComposition`은 Guest Control maintenance API consumer, VM service gate, status, sleep, timestamp ports를 조립하며, `RuntimeRollbackComposition`은 rollback workflow와 installed runtime paths, file-store reads, backup restore ports, service/status/progress ports를 조립합니다.
- `RuntimeInstallStartOnBootPolicy`는 `Domain/Policies`에 있고, `RuntimeInstallStartOnBootPolicyApplier`와 `RuntimeInstallPermissionConfigurator`는 `HostAdapters/Launchd`에 있습니다. `RuntimeInstallComposition`은 `Bootstrap/Composition`에서 persisted setting write, concrete service-manager command port, ownership/plist command port를 조립합니다.
- `RuntimeInstallExecutablePreparer`와 `RuntimeInstallVMDiskProvisioner`는 `HostAdapters/Process`에 있습니다.
- `RuntimeCloudInitSeedWriter`는 `HostAdapters/CloudInit`에 있습니다. `RuntimeCloudInitSeedComposition`은 `Bootstrap/Composition`에서 seed image name, volume name, hdiutil path, file-store/process ports, instance-id generation을 조립합니다.
- `RuntimeGuestConfigWriter`는 `Infrastructure/FileSystem`에 있으며 Bootstrap install composition이 명시적으로 만든 guest runtime config document만 파일로 씁니다.
- `LauncherPaths`, `Constants`, generated helper version constants, `VMRuntimeConfigComposition`, `RuntimeManagedServicePaths`, `RuntimeHealthCheckerComposition`, `RuntimeCloudInitSeedComposition`, `RuntimeServiceControlComposition`, `RuntimeStatusPrinterComposition`, `RuntimeWorkflowStatusReporterComposition`, `RuntimeStatusWriterComposition`, `RuntimeHealthCheckRunnerComposition`, `RuntimeHealthWaitRunnerComposition`, `RuntimeManagedOperationGuardComposition`, `RuntimeWatchdogRunnerComposition`, `RuntimeGuestCapabilityCheckerComposition`, `RuntimeGuestActivationComposition`, `RuntimeGuestShutdownComposition`, `RuntimeLifecycleComposition`, `RuntimeUninstallComposition`, `RuntimeRedisBackupComposition`, `RuntimeDatastoreRepairComposition`, `RuntimeVMDiskRepairComposition`, `RuntimeRollbackComposition`, `RuntimeFreshInstallPreflightComposition`, `RuntimeBackupStoreComposition`, `RuntimeVersionStoreComposition`은 `Bootstrap/Composition`에 있으며 HostCLI는 compatibility alias 또는 extension shim만 유지합니다.
- `RuntimeInstallComposition`은 `Bootstrap/Composition`에 있으며 concrete path, file-store, process runner, storage guard, status/progress writer wiring을 소유합니다. HostCLI는 compatibility alias만 유지합니다.
- `RuntimeWorkflow` target은 제거되었고 `Sources/RuntimeWorkflow`에는 더 이상 Swift 구현 파일이 없습니다.

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
- transition rule은 `Domain/StateMachines/RuntimeUninstallTransitionPolicy`에 있습니다.

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

## Current Branch Scope

이 branch에서는 #47 구현을 skeleton-first 방식으로 시작합니다.

- 새 ideal layer target/folder root를 만들고 boundary test로 고정합니다.
- `ConfigureRuntimeUseCase`를 첫 Application boundary로 추가합니다.
- `RuntimeConfigureWorkflow`를 `Workflow/RuntimeConfigureLifecycle`로 이동해 최종 Workflow target의 첫 실제 operation으로 둡니다.
- advertised URL validation과 public host/port compatibility endpoint 결정은 `Domain` pure policy로 둡니다.
- `RuntimeServiceLifecycleWorkflow`를 `Workflow/RuntimeServiceLifecycle`로 이동하고, service loaded/stopped completion gate는 `Domain` pure policy로 둡니다.
- `RuntimeHealthWaitWorkflow`와 `RuntimeHealthRefreshWorkflow`를 `Workflow/RuntimeHealth`로 이동하고, health wait/snapshot/observation policy는 `Domain` pure policy로 둡니다.
- install lifecycle의 `RuntimeInstallDirectoryPreparer`, `RuntimeInstallSettingsCleaner`, `RuntimeInstallServiceStarter`, `RuntimeInstallVMRuntimeConfigurator`, `RuntimeInstallStepExecutor`를 `Workflow/RuntimeInstallLifecycle`로 이동합니다. 이들은 concrete host effect를 직접 호출하지 않고 explicit operation closures만 실행하므로 final Workflow target의 dependency direction을 깨지 않습니다.
- `RuntimeInstallWorkflow` orchestration을 `Workflow/RuntimeInstallLifecycle`로 이동합니다.
- `RuntimeStepExecutionEvent`를 `Contracts`로 이동해 progress event shape가 `Core`에 묶이지 않게 합니다.
- `RuntimeProcessResult`를 `Contracts`로 이동해 process command result shape가 `Core`에 묶이지 않게 합니다.
- `RuntimeOperationPlan`과 `RuntimeInstallTransitionPolicy`를 `Domain`으로 이동하고 기존 `Core` API는 typealias shim으로만 유지합니다.
- `RuntimeUninstallWorkflow` orchestration을 `Workflow/RuntimeUninstallLifecycle`로 이동합니다.
- `RuntimeRedisBackupWorkflow` orchestration을 `Workflow/RuntimeRepairLifecycle`로 이동합니다.
- `RuntimeBundlePreparationWorkflow` orchestration을 `Workflow/RuntimeUpdateLifecycle`로 이동합니다.
- `RuntimeBundleStager` staging orchestration을 `Workflow/RuntimeUpdateLifecycle`로 이동합니다.
- update bundle verification policy를 `Domain/Policies`로 이동하고 기존 `Core` API는 typealias shim으로 유지합니다.
- `RuntimeBundleDigestVerifier`, `RuntimeBundleDirectoryVerifier`, `RuntimeBundleMaterializer`, `RuntimeArtifactReplacer`, `RuntimeMigrationRunner` orchestration을 `Workflow/RuntimeUpdateLifecycle`로 이동합니다.
- `Application` target에서 전환기 `Core` dependency를 제거합니다.
- external state/effect port protocol은 `Application/Ports`에 둡니다. 전환기 `Core`는 기존 import 경로를 위해 이 port를 re-export하는 typealias shim만 갖습니다.
- filesystem/repository/observability infrastructure 구현은 `Infrastructure`에 둡니다. 전환기 `HostInfrastructure`는 기존 import 경로를 위해 `Infrastructure` typealias shim만 갖습니다.
- Runtime Control HTTP/API/transport/test-kit 구현은 `Interfaces/RuntimeControlAPI`에 둡니다. 전환기 `RuntimeControlAPI`는 기존 import 경로를 위해 `Interfaces` typealias shim만 갖습니다.
- Runtime Control app read-model annotation, status refresh orchestration, status uptime/reachability/reachability-label/service-value/http-value/compose-service-value/health-details/advanced-service-health/vital-server-availability/remote-console availability/VM-state display/overall-health calculation, health notification state classification, event display projection, command result/presentation message formatting, log export destination rule validation, Vital files directory input validation, settings validation, section grouping, selection, action planning, observability refresh, status action-needed decision, status recorder summary projection, recorder activity chart data, VitalDB recorder/bed display projection 같은 API/UI boundary policy는 `Interfaces/MacRuntimeControlApp`에 둡니다. 전환기 `MacRuntimeControlApp`은 기존 내부 이름을 위해 `Interfaces` typealias shim을 둘 수 있습니다.
- process state/pid-file handling, process execution, curl HTTP probing, launchd service management, system clock/sleep 같은 concrete host adapter 구현은 `HostAdapters`에 둡니다. 전환기 `HostCLI`는 기존 내부 이름을 위해 `HostAdapters` typealias shim만 갖습니다.
- HostCLI configure path는 CLI command를 usecase request로 매핑하고 workflow port를 조립하는 역할로 축소합니다.
- 기존 configure workflow behavior와 HostCLI runner parity test는 유지합니다.

아직 하지 않는 일:

- `Core -> Domain` 대규모 rename은 하지 않습니다.
- `HostCLI` 전체를 `Interfaces/HostAdapters/Bootstrap`으로 한 번에 이동하지 않습니다.
- install/apply/uninstall/repair 전체 동작을 한 번에 전환하지 않습니다.

이 branch의 목적은 최종 구조로 수렴하는 되돌리기 어려운 첫 관문을 만드는 것입니다. 새 layer root와 target graph가 존재하고, ConfigureRuntime이 새 Application boundary를 통과하면 이후 operation은 같은 pattern으로 옮깁니다.

## References

- GitHub issue #47: macOS runtime을 이상적 레이어 구조로 수렴
- `docs/troubleshooting/048_hostcli-runtime-workflow-boundary-fragmentation.md`
- `docs/troubleshooting/043_runtime-workflow-state-machine-layer-boundary.md`
- `docs/troubleshooting/045_runtime-install-workflow-state-machine-parity.md`
- `docs/troubleshooting/047_guest-log-sync-stopped-after-restart.md`
- `docs/troubleshooting/032_macos-runtime-explicit-responsibility-review.md`
- `docs/troubleshooting/039_agents-compliance-fallback-audit.md`
