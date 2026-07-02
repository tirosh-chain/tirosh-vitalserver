import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

/// Owns host mutations and privileged runtime commands.
/// SwiftUI and the development API call through this actor so MainActor only coordinates UI state.
public actor MacRuntimeControlCommandWorker {
    private let privilegedCommandRunner: any PrivilegedCommandRunning
    private let actionEnvironment: any RuntimeActionEnvironment
    private let logExporter: any RuntimeLogExporting
    private let guestProductServiceController: any RuntimeGuestProductServiceCommandControlling
    private let guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling
    private let guestControlBaseURLOverride: String?

    public init() {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacRuntimeControlLogExporter(),
            guestProductServiceController: RuntimeGuestProductServiceControlUseCase(),
            guestMaintenanceController: RuntimeGuestMaintenanceControlUseCase()
        )
    }

    public init(
        guestProductServiceController: any RuntimeGuestProductServiceCommandControlling,
        guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling = RuntimeGuestMaintenanceControlUseCase(),
        guestControlBaseURLOverride: String? = nil
    ) {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacRuntimeControlLogExporter(),
            guestProductServiceController: guestProductServiceController,
            guestMaintenanceController: guestMaintenanceController,
            guestControlBaseURLOverride: guestControlBaseURLOverride
        )
    }

    init(
        privilegedCommandRunner: any PrivilegedCommandRunning,
        actionEnvironment: any RuntimeActionEnvironment,
        logExporter: any RuntimeLogExporting,
        guestProductServiceController: any RuntimeGuestProductServiceCommandControlling = RuntimeGuestProductServiceControlUseCase(),
        guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling = RuntimeGuestMaintenanceControlUseCase(),
        guestControlBaseURLOverride: String? = nil
    ) {
        self.privilegedCommandRunner = privilegedCommandRunner
        self.actionEnvironment = actionEnvironment
        self.logExporter = logExporter
        self.guestProductServiceController = guestProductServiceController
        self.guestMaintenanceController = guestMaintenanceController
        self.guestControlBaseURLOverride = guestControlBaseURLOverride
    }

    public func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await actionEnvironment.verifyBundle(launcher: RuntimeControlClientConstants.Paths.launcher, bundleURL: url)
    }

    public func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult {
        try ensureExecutable(.uninstaller)
        return await runPrivileged(RuntimeCommandFactory.uninstallCommand(
            uninstaller: RuntimeControlClientConstants.Paths.uninstaller,
            clean: mode.clean,
            forceClean: mode.forceClean
        ))
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        var temporaryFiles: [RuntimeTemporarySettingsFile] = []
        var adminPasswordFile: URL?

        do {
            if settings.changeAdminPassword {
                adminPasswordFile = try actionEnvironment.writeAdminPasswordFile(settings.adminPassword)
                if let adminPasswordFile {
                    temporaryFiles.append(RuntimeTemporarySettingsFile(
                        url: adminPasswordFile,
                        label: "admin password file"
                    ))
                }
            }

            let recorderIngressSettingsFile = try actionEnvironment.writeRecorderIngressSettingsFile(settings.recorderIngress)
            temporaryFiles.append(RuntimeTemporarySettingsFile(
                url: recorderIngressSettingsFile,
                label: "recorder ingress settings file"
            ))

            let redisRelaySettingsFile = try actionEnvironment.writeRedisRelaySettingsFile(settings.redisRelay)
            temporaryFiles.append(RuntimeTemporarySettingsFile(
                url: redisRelaySettingsFile,
                label: "Redis relay settings file"
            ))

            let result = await runPrivileged(RuntimeCommandFactory.shellCommand(
                executable: RuntimeControlClientConstants.Paths.launcher,
                arguments: RuntimeCommandFactory.configureRuntimeArguments(
                    settings: settings,
                    adminPasswordFile: adminPasswordFile?.path,
                    recorderIngressSettingsFile: recorderIngressSettingsFile.path,
                    redisRelaySettingsFile: redisRelaySettingsFile.path
                )
            ))
            let cleanupIssues = cleanupTemporarySettingsFiles(temporaryFiles)
            return cleanupIssues.reduce(result) { partialResult, issue in
                partialResult.appendingOutputIssue(issue)
            }
        } catch {
            _ = cleanupTemporarySettingsFiles(temporaryFiles)
            throw error
        }
    }

    public func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.applyBundle,
                url.path,
            ]
        ))
    }

    public func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.rollback,
                backupURL.path,
            ]
        ))
    }

    public func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        let baseURL = try guestControlBaseURL()
        let controller = guestMaintenanceController
        let archive = backupURL.path
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            let operation = try controller.restoreRedisBackup(
                archive: archive,
                gateway: gateway
            )
            return RuntimeCommandResult(guestControlOperation: operation)
        }.value
    }

    public func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.runtimeDataRestore,
                backupURL.path,
            ]
        ))
    }

    public func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        try ensureManagedBackupDeletionTarget(url)
        return await runPrivileged(RuntimeCommandFactory.deleteBackupCommand(url: url))
    }

    public func repairProxy() async throws -> RuntimeCommandResult {
        return await runPrivileged(RuntimeCommandFactory.proxyRepairCommand())
    }

    public func repairDatastore() async throws -> RuntimeCommandResult {
        let baseURL = try guestControlBaseURL()
        let controller = guestMaintenanceController
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            let operation = try controller.repairDatastore(gateway: gateway)
            return RuntimeCommandResult(guestControlOperation: operation)
        }.value
    }

    public func repairVMDisk() async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.repairVMDisk,
            ]
        ))
    }

    private func cleanupTemporarySettingsFiles(
        _ files: [RuntimeTemporarySettingsFile]
    ) -> [RuntimeCommandOutputIssue] {
        var issues: [RuntimeCommandOutputIssue] = []
        for file in files {
            do {
                try actionEnvironment.removeItem(at: file.url)
            } catch {
                issues.append(RuntimeCommandOutputIssue(
                    stream: .stderr,
                    message: "\(file.label) cleanup failed path=\(file.url.path) reason=\(error.localizedDescription)"
                ))
            }
        }
        return issues
    }

    public func repairRuntimeServices() async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .repair))
    }

    public func createRedisBackup() async throws -> RuntimeCommandResult {
        let baseURL = try guestControlBaseURL()
        let controller = guestMaintenanceController
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            let operation = try controller.createRedisBackup(gateway: gateway)
            return RuntimeCommandResult(guestControlOperation: operation)
        }.value
    }

    public func createRuntimeDataBackup() async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.runtimeDataBackup,
            ]
        ))
    }

    public func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        let baseURL = try guestControlBaseURL()
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            return try gateway.listServices()
        }.value
    }

    public func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        let baseURL = try guestControlBaseURL()
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            return try gateway.stackStatus()
        }.value
    }

    public func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        let baseURL = try guestControlBaseURL()
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            return try gateway.serviceStatus(service)
        }.value
    }

    public func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        let baseURL = try guestControlBaseURL(override: request.guestControlBaseURL)
        let controller = guestProductServiceController
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            return try controller.startService(
                request.service,
                gateway: gateway
            )
        }.value
    }

    public func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        let baseURL = try guestControlBaseURL(override: request.guestControlBaseURL)
        let controller = guestProductServiceController
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            return try controller.stopService(
                request.service,
                gateway: gateway
            )
        }.value
    }

    public func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        let baseURL = try guestControlBaseURL(override: request.guestControlBaseURL)
        let controller = guestProductServiceController
        return try await Task.detached(priority: .userInitiated) {
            let gateway = try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL
            )
            return try controller.restartService(
                request.service,
                gateway: gateway
            )
        }.value
    }

    public func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabScenarioList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.labScenarios()
            } catch {
                return RuntimeLabScenarioList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabVitalFileList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.labVitalFiles()
            } catch {
                return RuntimeLabVitalFileList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func loadLabBeds() async throws -> RuntimeLabBedList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.labBeds()
            } catch {
                return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.labRecorders()
            } catch {
                return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                return try gateway.createLabBeds(request)
            } catch {
                return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                return try gateway.deleteLabBeds(request)
            } catch {
                return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func resetLabBeds() async throws -> RuntimeLabBedList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                return try gateway.resetLabBeds()
            } catch {
                return RuntimeLabBedList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                return try gateway.createLabRecorders(request)
            } catch {
                return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                return try gateway.deleteLabRecorders(request)
            } catch {
                return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                return try gateway.resetLabRecorders()
            } catch {
                return RuntimeLabRecorderList.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            let recorders = try gateway.hideVitalDBRecorders(request)
            let beds = try gateway.vitalDBBeds()
            return (recorders, beds)
        }
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            let recorders = try gateway.unhideVitalDBRecorders(request)
            let beds = try gateway.vitalDBBeds()
            return (recorders, beds)
        }
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            let recorders = try gateway.deleteVitalDBRecorders(request)
            let beds = try gateway.vitalDBBeds()
            return (recorders, beds)
        }
    }

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            let beds = try gateway.hideVitalDBBeds(request)
            let recorders = try gateway.vitalDBRecorders()
            return (recorders, beds)
        }
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            let beds = try gateway.unhideVitalDBBeds(request)
            let recorders = try gateway.vitalDBRecorders()
            return (recorders, beds)
        }
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            let beds = try gateway.deleteVitalDBBeds(request)
            let recorders = try gateway.vitalDBRecorders()
            return (recorders, beds)
        }
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.createLabSession(request)
            } catch {
                return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.labSession(sessionId)
            } catch {
                return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.startLabSession(sessionId)
            } catch {
                return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.stopLabSession(sessionId)
            } catch {
                return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.replayLabVitalFile(request)
            } catch {
                return RuntimeLabSessionResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) async throws -> RuntimeLabVitalFileUploadResponse {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeLabVitalFileUploadResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
                    baseURL: baseURL
                )
                return try gateway.uploadLabVitalFile(request)
            } catch {
                return RuntimeLabVitalFileUploadResponse.unavailable(readError: "Runtime Lab gateway failed: \(error)")
            }
        }.value
    }

    public func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        try await logExporter.exportLogs(to: destination)
    }

    private func ensureExecutable(_ requirement: RuntimeExecutableRequirement) throws {
        try RuntimeExecutableCommandPreflight.requireExecutable(
            state: actionEnvironment.executableState(atPath: requirement.path),
            requirement: requirement
        )
    }

    private func ensureManagedBackupDeletionTarget(_ url: URL) throws {
        let backupsRoot = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.backups)
        let runtimeDataBackupsRoot = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeDataBackups)
        guard RuntimeManagedBackupPolicy.isManagedBackupURL(url, backupsRoot: backupsRoot)
            || RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(url, runtimeDataBackupsRoot: runtimeDataBackupsRoot)
        else {
            throw RuntimeClientError.invalidBackupDeletionTarget(
                path: url.path,
                backupsRoot: "\(backupsRoot.path), \(runtimeDataBackupsRoot.path)"
            )
        }
    }

    private func guestControlBaseURL(override: String? = nil) throws -> String {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        if let override = guestControlBaseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        let read = RuntimeStatusDocumentReader(
            url: URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeStatus),
            fileStore: SystemRuntimeFileStore()
        ).load()
        if let vmIP = read.document?.vmIP?.trimmingCharacters(in: .whitespacesAndNewlines), !vmIP.isEmpty {
            return RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)
        }
        if let error = read.error {
            throw RuntimeClientError.guestControlUnavailable("runtime status read failed: \(error)")
        }
        throw RuntimeClientError.guestControlUnavailable("runtime status vmIP is missing.")
    }

    private func runVitalDBVisibilityCommand(
        _ command: @escaping @Sendable (any RuntimeGuestControlGateway) throws -> (
            RuntimeGuestControlVitalDBRecorderRead,
            RuntimeGuestControlVitalDBBedRead
        )
    ) async -> RuntimeVitalRecorderHistory {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return RuntimeVitalRecorderHistory(readError: "VitalDB read model command failed: \(error)")
        }
        return await Task.detached(priority: .userInitiated) {
            do {
                let gateway: any RuntimeGuestControlGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
                let reads = try command(gateway)
                let current = RuntimeVitalDBGuestReadModelProvider.makeCurrentObservation(
                    recorders: reads.0,
                    beds: reads.1
                )
                guard let observation = current.observation else {
                    return RuntimeVitalRecorderHistory(
                        readError: current.readIssues.joined(separator: "; ")
                    )
                }
                return RuntimeVitalRecorderHistory(observations: [observation])
            } catch {
                return RuntimeVitalRecorderHistory(readError: "VitalDB read model command failed: \(error)")
            }
        }.value
    }

    private func runPrivileged(_ shellCommand: String) async -> RuntimeCommandResult {
        await privilegedCommandRunner.run(shellCommand: shellCommand)
    }
}

private extension RuntimeCommandResult {
    init(guestControlOperation operation: RuntimeGuestControlServiceOperation) {
        let archive = operation.result?.archive?.trimmingCharacters(in: .whitespacesAndNewlines)
        let restoredArchive = operation.result?.restoredArchive?.trimmingCharacters(in: .whitespacesAndNewlines)
        var stdout = "guest control operation completed operationId=\(operation.operationId)"
        if let archive, !archive.isEmpty {
            stdout += " archive=\(archive)"
        }
        if let restoredArchive, !restoredArchive.isEmpty {
            stdout += " restoredArchive=\(restoredArchive)"
        }
        self.init(
            exitCode: 0,
            stdout: stdout,
            stderr: ""
        )
    }
}

private struct RuntimeTemporarySettingsFile {
    let url: URL
    let label: String
}

private struct UnavailableRuntimeGuestProductServiceCommandController: RuntimeGuestProductServiceCommandControlling {
    func startService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeClientError.guestControlUnavailable("guest product service controller is unavailable.")
    }

    func stopService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeClientError.guestControlUnavailable("guest product service controller is unavailable.")
    }

    func restartService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeClientError.guestControlUnavailable("guest product service controller is unavailable.")
    }
}

private extension RuntimeCommandResult {
    func appendingOutputIssue(_ issue: RuntimeCommandOutputIssue) -> RuntimeCommandResult {
        RuntimeCommandResult(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            outputIssues: outputIssues + [issue],
            executionIssue: executionIssue
        )
    }
}
