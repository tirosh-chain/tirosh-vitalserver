import Contracts
import Core
import Foundation

public struct RuntimeRollbackWorkflowContext {
    public let rootfsBase: URL
    public let runtimeVersion: URL
    public let vmDisk: URL
    public let managerAppPath: URL
    public let nginxDirectory: URL
    public let deployDirectory: URL

    public init(
        rootfsBase: URL,
        runtimeVersion: URL,
        vmDisk: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) {
        self.rootfsBase = rootfsBase
        self.runtimeVersion = runtimeVersion
        self.vmDisk = vmDisk
        self.managerAppPath = managerAppPath
        self.nginxDirectory = nginxDirectory
        self.deployDirectory = deployDirectory
    }
}

public struct RuntimeRollbackWorkflowOperations {
    public let requireLatestBackup: () throws -> URL
    public let directoryExists: (URL) -> Bool
    public let fileExists: (URL) -> Bool
    public let readData: (URL) throws -> Data
    public let isLaunchdLoaded: (RuntimeManagedService) -> Bool
    public let stopRuntimeServices: () throws -> Void
    public let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let replaceFile: (URL, URL) throws -> Void
    public let writeRuntimeVersion: (String, URL) throws -> Void
    public let restoreBackupPathIfExists: (URL, URL) throws -> Void
    public let restoreRuntimeToolsIfExists: (URL) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public let log: (String) -> Void

    public init(
        requireLatestBackup: @escaping () throws -> URL,
        directoryExists: @escaping (URL) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        readData: @escaping (URL) throws -> Data,
        isLaunchdLoaded: @escaping (RuntimeManagedService) -> Bool,
        stopRuntimeServices: @escaping () throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        replaceFile: @escaping (URL, URL) throws -> Void,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        restoreBackupPathIfExists: @escaping (URL, URL) throws -> Void,
        restoreRuntimeToolsIfExists: @escaping (URL) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireLatestBackup = requireLatestBackup
        self.directoryExists = directoryExists
        self.fileExists = fileExists
        self.readData = readData
        self.isLaunchdLoaded = isLaunchdLoaded
        self.stopRuntimeServices = stopRuntimeServices
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
        self.replaceFile = replaceFile
        self.writeRuntimeVersion = writeRuntimeVersion
        self.restoreBackupPathIfExists = restoreBackupPathIfExists
        self.restoreRuntimeToolsIfExists = restoreRuntimeToolsIfExists
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
        self.log = log
    }
}

public struct RuntimeRollbackWorkflow {
    public let context: RuntimeRollbackWorkflowContext
    public let operations: RuntimeRollbackWorkflowOperations

    public init(
        context: RuntimeRollbackWorkflowContext,
        operations: RuntimeRollbackWorkflowOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func rollback(_ command: RuntimeRollbackCommand) throws {
        try runtimeRollbackRunner().run(command)
    }

    private func runtimeRollbackRunner() -> RuntimeRollbackRunner<RuntimeRollbackCommand> {
        RuntimeRollbackRunner(
            preparePreflight: prepareRollbackPreflight,
            executeStep: executeRollbackStep,
            writeStatus: operations.writeStatus,
            writeProgress: operations.writeProgress,
            vmDiskPath: { context.vmDisk.path },
            log: operations.log
        )
    }

    private func prepareRollbackPreflight(_ command: RuntimeRollbackCommand) throws -> RollbackPreflightContext {
        try RuntimeRollbackPreflightRunner(
            requireLatestBackup: operations.requireLatestBackup,
            directoryExists: operations.directoryExists,
            fileExists: operations.fileExists,
            loadManifest: { backup in
                let manifestURL = backup.appendingPathComponent(RuntimeFileNames.backupManifest)
                guard operations.fileExists(manifestURL) else {
                    throw RuntimeWorkflowError.operationFailed("missing file: \(manifestURL.path)")
                }
                let data = try operations.readData(manifestURL)
                return try JSONDecoder().decode(BackupManifest.self, from: data)
            },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(
                    restartVM: operations.isLaunchdLoaded(.vm),
                    restartGuestLogSync: operations.isLaunchdLoaded(.guestLogSync),
                    restartProxy: operations.isLaunchdLoaded(.proxy),
                    restartWatchdog: operations.isLaunchdLoaded(.watchdog)
                )
            },
            log: operations.log
        ).prepare(command)
    }

    private func executeRollbackStep(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext
    ) throws {
        let executor = RuntimeRollbackStepExecutor(
            stopRuntimeServices: operations.stopRuntimeServices,
            replaceFile: operations.replaceFile,
            fileExists: operations.fileExists,
            writeRuntimeVersion: operations.writeRuntimeVersion,
            restoreBackupPathIfExists: operations.restoreBackupPathIfExists,
            restoreRuntimeToolsIfExists: operations.restoreRuntimeToolsIfExists,
            startRuntimeServices: operations.startRuntimeServices,
            waitForHealth: operations.waitForHealth
        )
        try executor.execute(
            step,
            preflight: preflight,
            rootfsBase: context.rootfsBase,
            runtimeVersion: context.runtimeVersion,
            managerAppPath: context.managerAppPath,
            nginxDirectory: context.nginxDirectory,
            deployDirectory: context.deployDirectory
        )
    }
}
