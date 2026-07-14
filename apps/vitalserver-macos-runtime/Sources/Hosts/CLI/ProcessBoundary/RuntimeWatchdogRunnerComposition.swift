import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import Workflow

public struct RuntimeWatchdogRunnerCompositionContext {
    let installedPaths: InstalledRuntimePaths

    public init(
        installedPaths: InstalledRuntimePaths
    ) {
        self.installedPaths = installedPaths
    }
}

public struct RuntimeWatchdogRunnerCompositionOperations {
    let fileStore: RuntimeFileStore
    let now: () -> Date
    let activeManagedOperation: () -> RuntimeOperation?
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let httpStatusCode: (String) -> String
    let proxyLivenessURL: (Int) -> String
    let automaticRecoveryEnabled: () throws -> Bool
    let restartVMRuntime: () throws -> Void
    let restartService: (RuntimeManagedService) throws -> Void
    let createLogsDirectory: () -> RuntimeBestEffortOperationResult
    let rotateRuntimeLogs: () -> RuntimeBestEffortOperationResult
    let collectGuestLogs: () -> RuntimeBestEffortOperationResult
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let recordObservedStatus: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot
    ) -> Void
    let recordObservedEvent: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) -> Void
    let recordLifecycleEvent: (RuntimeOperation, String, RuntimeEventType) -> Void
    let recoveryWaitSeconds: TimeInterval
    let sleep: (TimeInterval) -> Void
    let log: (String) -> Void
    let printLine: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        now: @escaping () -> Date,
        activeManagedOperation: @escaping () -> RuntimeOperation?,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        httpStatusCode: @escaping (String) -> String,
        proxyLivenessURL: @escaping (Int) -> String,
        automaticRecoveryEnabled: @escaping () throws -> Bool,
        restartVMRuntime: @escaping () throws -> Void,
        restartService: @escaping (RuntimeManagedService) throws -> Void,
        createLogsDirectory: @escaping () -> RuntimeBestEffortOperationResult,
        rotateRuntimeLogs: @escaping () -> RuntimeBestEffortOperationResult,
        collectGuestLogs: @escaping () -> RuntimeBestEffortOperationResult,
        writeRuntimeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        recordObservedStatus: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot
        ) -> Void,
        recordObservedEvent: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) -> Void,
        recordLifecycleEvent: @escaping (RuntimeOperation, String, RuntimeEventType) -> Void,
        recoveryWaitSeconds: TimeInterval,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.fileStore = fileStore
        self.now = now
        self.activeManagedOperation = activeManagedOperation
        self.healthSnapshot = healthSnapshot
        self.httpStatusCode = httpStatusCode
        self.proxyLivenessURL = proxyLivenessURL
        self.automaticRecoveryEnabled = automaticRecoveryEnabled
        self.restartVMRuntime = restartVMRuntime
        self.restartService = restartService
        self.createLogsDirectory = createLogsDirectory
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.collectGuestLogs = collectGuestLogs
        self.writeRuntimeStatus = writeRuntimeStatus
        self.recordObservedStatus = recordObservedStatus
        self.recordObservedEvent = recordObservedEvent
        self.recordLifecycleEvent = recordLifecycleEvent
        self.recoveryWaitSeconds = recoveryWaitSeconds
        self.sleep = sleep
        self.log = log
        self.printLine = printLine
    }
}

public struct RuntimeWatchdogRunnerComposition {
    private let context: RuntimeWatchdogRunnerCompositionContext
    private let operations: RuntimeWatchdogRunnerCompositionOperations

    public init(
        context: RuntimeWatchdogRunnerCompositionContext,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func run() throws {
        projectHostDiagnostics(stage: "before-watchdog")
        do {
            try runWatchdog()
        } catch {
            projectHostDiagnostics(stage: "after-watchdog-failure")
            throw error
        }
        projectHostDiagnostics(stage: "after-watchdog")
    }

    private func runWatchdog() throws {
        try RuntimeWatchdogRunner().run(
            operations: RuntimeWatchdogActions(
                createLogsDirectory: operations.createLogsDirectory,
                rotateRuntimeLogs: operations.rotateRuntimeLogs,
                collectGuestLogs: operations.collectGuestLogs,
                activeManagedOperation: operations.activeManagedOperation,
                healthSnapshot: operations.healthSnapshot,
                proxyLivenessHTTP: { port in
                    guard let port else {
                        return RuntimeHTTPStatusText.missingProxyPort
                    }
                    return operations.httpStatusCode(operations.proxyLivenessURL(port))
                },
                automaticRecoveryEnabled: operations.automaticRecoveryEnabled,
                restartVMRuntime: operations.restartVMRuntime,
                restartService: operations.restartService,
                writeRuntimeStatus: operations.writeRuntimeStatus,
                recordObservedStatus: operations.recordObservedStatus,
                recordObservedEvent: operations.recordObservedEvent,
                recordLifecycleEvent: operations.recordLifecycleEvent,
                markVMLifecycleRunning: { lifecycle, message in
                    let timestamp = operations.now()
                    _ = try SQLiteRuntimeVMLifecycleResourceStore(
                        databaseURL: context.installedPaths.runtimeStateDatabase,
                        transitionDecider: RuntimeVMLifecycleTransitionUseCase()
                    ).putVMLifecycleResource(RuntimeVMLifecycleDocument(
                        state: .running,
                        operation: lifecycle.operation,
                        operationID: lifecycle.operationID,
                        bootID: lifecycle.bootID,
                        startedAt: lifecycle.startedAt,
                        updatedAt: ISO8601DateFormatter().string(from: timestamp),
                        deadlineAt: nil,
                        terminalReason: nil,
                        message: message
                    ))
                    let settingsRepository = SQLiteRuntimeHostSettingsRepository(
                        databaseURL: context.installedPaths.runtimeStateDatabase,
                        transitionDecider: RuntimeHostSettingsActivationUseCase()
                    )
                    let settings: RuntimeHostSettingsRecord
                    switch settingsRepository.loadHostSettings() {
                    case .loaded(let record):
                        settings = record
                    case .missing:
                        throw RuntimeHostSettingsStateTransitionError.missingState
                    case .failed(let reason):
                        throw SQLiteRuntimeHostSettingsRepositoryError.writeFailed(
                            path: context.installedPaths.runtimeStateDatabase.path,
                            reason: reason
                        )
                    }
                    guard settings.bootRunID == lifecycle.bootID,
                          let bootRevision = settings.bootRevision,
                          let runID = settings.bootRunID else {
                        throw SQLiteRuntimeHostSettingsRepositoryError.lifecycleProofFailed(
                            reason: "watchdog lifecycle/settings boot identity mismatch"
                        )
                    }
                    let applied = try settingsRepository.markHostSettingsApplied(
                        revision: bootRevision,
                        runID: runID,
                        appliedAt: ISO8601DateFormatter().string(from: timestamp)
                    )
                    guard let appliedPayload = applied.appliedPayload else {
                        throw SQLiteRuntimeHostSettingsRepositoryError.lifecycleProofFailed(
                            reason: "applied Host settings payload is missing revision=\(bootRevision)"
                        )
                    }
                    do {
                        try operations.fileStore.writeData(
                            appliedPayload.vmConfigJSON,
                            to: context.installedPaths.appliedVMConfig,
                            options: .atomic
                        )
                        guard try operations.fileStore.readData(context.installedPaths.appliedVMConfig)
                            == appliedPayload.vmConfigJSON else {
                            throw SQLiteRuntimeHostSettingsRepositoryError.writeFailed(
                                path: context.installedPaths.appliedVMConfig.path,
                                reason: "applied settings projection verification failed"
                            )
                        }
                    } catch {
                        operations.log(
                            "Host settings applied projection failed revision=\(bootRevision) "
                                + "path=\(context.installedPaths.appliedVMConfig.path) reason=\(error)"
                        )
                    }
                },
                recoveryWaitSeconds: operations.recoveryWaitSeconds,
                sleep: operations.sleep
            ),
            log: operations.log,
            printLine: operations.printLine
        )
    }

    private func projectHostDiagnostics(stage: String) {
        do {
            let repository = SQLiteRuntimeHostDiagnosticOutboxRepository(
                databaseURL: context.installedPaths.runtimeStateDatabase
            )
            let result = try RuntimeHostDiagnosticsProjectionWorkflow(
                repository: repository,
                eventSink: JSONLRuntimeHostDiagnosticEventSink(
                    url: context.installedPaths.hostRuntimeStateEvents,
                    fileStore: operations.fileStore
                ),
                snapshotSink: JSONRuntimeHostStateDiagnosticSnapshotSink(
                    url: context.installedPaths.hostRuntimeStateSnapshot,
                    fileStore: operations.fileStore
                ),
                timestamp: {
                    ISO8601DateFormatter().string(from: operations.now())
                },
                describeError: RuntimeErrorDescription.describe
            ).run()
            operations.log(
                "Host diagnostics projected stage=\(stage) events=\(result.projectedEventCount) sourceSequence=\(result.snapshotSourceSequence)"
            )
        } catch {
            operations.log(
                "Host diagnostics projection failed stage=\(stage) error=\(RuntimeErrorDescription.describe(error))"
            )
        }
    }
}
