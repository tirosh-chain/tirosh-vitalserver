import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func runtimeStatusPrinter() -> RuntimeStatusPrinter {
        RuntimeStatusPrinterComposition.make(
            context: RuntimeStatusPrinterCompositionContext(
                productRoot: productRoot,
                installedPaths: installedPaths,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk
            ),
            operations: RuntimeStatusPrinterCompositionOperations(
                latestBackupPath: { latestBackup()?.path },
                runtimeStatusValue: runtimeStatusValue,
                runtimeVersionValue: runtimeVersionValue,
                vmIP: { statusReporter.loadStatus()?.vmIP ?? "not reported" },
                installedProxyPort: healthChecker.installedProxyPort,
                hostProxyHTTPStatus: { url in
                    httpProber.statusCode(url: url)
                },
                isExecutableFile: { path in
                    fileStore.isExecutableFile(atPath: path)
                },
                fileExists: fileExists,
                serviceState: { label in
                    healthChecker.launchdState(label)
                }
            )
        )
    }

    func runtimeCloudInitSeedWriter() -> RuntimeCloudInitSeedWriter {
        RuntimeCloudInitSeedComposition.make(
            runtimeDirectory: installedPaths.runtimeDirectory,
            fileStore: fileStore,
            buildSeedImage: buildCloudInitSeedImage
        )
    }

    func runtimeHealthCheckRunner() -> RuntimeHealthCheckRunner {
        RuntimeHealthCheckRunnerComposition.make(
            operations: RuntimeHealthCheckRunnerCompositionOperations(
                printStatus: printStatus,
                healthSnapshot: runtimeHealthSnapshot,
                writeStatus: runtimeStatusWriterAction(),
                recordObservedEvent: { status, operation, message, snapshot, eventType in
                    try runtimeObservedEventPublisher().recordObservedEvent(
                        status,
                        operation: operation,
                        message: message,
                        snapshot: snapshot,
                        defaultEventType: eventType
                    )
                },
                log: log
            )
        )
    }

    func automaticRecoveryEnabled() -> Bool {
        runtimeConfigFlagReader().automaticRecoveryEnabled()
    }

    func runtimeManagedOperationGuard() -> RuntimeManagedOperationGuardComposition {
        RuntimeManagedOperationGuardComposition.make(
            statusReporter: statusReporter,
            operationLeaseRepository: JSONFileRuntimeOperationLeaseRepository(url: installedPaths.runtimeOperationLease),
            guestGateway: guestGateway,
            now: { clock.now },
            log: log
        )
    }

    func runtimeWatchdogRunner() -> RuntimeWatchdogRunnerComposition {
        RuntimeWatchdogRunnerComposition(
            context: RuntimeWatchdogRunnerCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeWatchdogRunnerCompositionOperations(
                fileStore: fileStore,
                now: { clock.now },
                activeManagedOperation: {
                    runtimeManagedOperationGuard().activeOperation()
                },
                healthSnapshot: {
                    runtimeHealthSnapshot()
                },
                httpStatusCode: { url in
                    httpProber.statusCode(url: url)
                },
                proxyLivenessURL: { port in
                    Constants.Runtime.proxyLivenessURL(port: port)
                },
                automaticRecoveryEnabled: {
                    automaticRecoveryEnabled()
                },
                restartVMRuntime: {
                    try restartVMRuntimeServices()
                },
                restartService: { service in
                    try restartOrStartLaunchdService(service)
                },
                createLogsDirectory: {
                    runtimeBestEffortResult {
                        try fileStore.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                    }
                },
                rotateRuntimeLogs: {
                    runtimeBestEffortResult {
                        try rotateRuntimeLogs()
                    }
                },
                collectGuestLogs: {
                    runtimeBestEffortResult {
                        try collectGuestLogs()
                    }
                },
                writeRuntimeStatus: runtimeStatusWriterAction(),
                recordObservedStatus: { status, operation, message, snapshot in
                    runtimeObservedEventPublisher().recordObservedEventBestEffort(
                        status,
                        operation: operation,
                        message: message,
                        snapshot: snapshot
                    )
                },
                recordObservedEvent: { status, operation, message, snapshot, eventType in
                    runtimeObservedEventPublisher().recordObservedEventBestEffort(
                        status,
                        operation: operation,
                        message: message,
                        snapshot: snapshot,
                        eventType: eventType
                    )
                },
                recordLifecycleEvent: { operation, message, eventType in
                    runtimeEventPublisher().recordLifecycleEventBestEffort(
                        operation: operation,
                        message: message,
                        eventType: eventType
                    )
                },
                recoveryWaitSeconds: Constants.Runtime.watchdogRecoveryWaitSeconds,
                sleep: { interval in
                    sleeper.sleep(forTimeInterval: interval)
                },
                log: log
            )
        )
    }

    func runtimeConfigureRunner() -> RuntimeConfigureRunner {
        RuntimeConfigureComposition.make(
            context: RuntimeConfigureCompositionContext(
                installedPaths: installedPaths,
                configURL: paths.config,
                maximumAllowedCPUCount: Constants.Defaults.maximumAllowedCPUCount(
                    systemCPUCount: ProcessInfo.processInfo.processorCount
                ),
                maximumAllowedMemoryGiB: Constants.Defaults.maximumAllowedMemoryGiB(
                    physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
                )
            ),
            operations: RuntimeConfigureCompositionOperations(
                fileStore: fileStore,
                resizeVMDiskIfNeeded: { diskGiB in
                    try resizeVMDiskIfNeeded(diskGiB: diskGiB)
                },
                setInstalledProxyPort: { port in
                    try setInstalledProxyPort(port)
                },
                readSecretFile: { url in
                    try readSecretFile(url)
                },
                restrictSecretFile: { url in
                    try restrictSecretFile(url)
                },
                setStartOnBoot: { enabled in
                    try setStartOnBoot(enabled)
                },
                setSystemSleepPrevention: { enabled in
                    try setSystemSleepPrevention(enabled)
                },
                restartRuntimeServices: {
                    try restartVMRuntimeServices()
                    try restartOrStartLaunchdService(.proxy)
                    try restartOrStartLaunchdService(.watchdog)
                },
                log: log
            )
        )
    }
}
