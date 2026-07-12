import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

private protocol RuntimeLabResponseUnavailableFactory {
    static func unavailable(readError: String) -> Self
}

/// Owns host mutations and privileged runtime commands.
/// SwiftUI and the development API call through this actor so MainActor only coordinates UI state.
public actor MacRuntimeControlCommandWorker {
    private let privilegedCommandRunner: any PrivilegedCommandRunning
    private let actionEnvironment: any RuntimeActionEnvironment
    private let logExporter: any RuntimeLogExporting
    private let guestProductServiceController: any RuntimeGuestProductServiceCommandControlling
    private let guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling
    private let guestAddressProvider: any RuntimeGuestAddressProvider
    private let guestControlBaseURLOverride: String?

    public init() {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacRuntimeControlLogExporter(),
            guestProductServiceController: UnavailableRuntimeGuestProductServiceController(),
            guestMaintenanceController: UnavailableRuntimeGuestMaintenanceController(),
            guestAddressProvider: UnavailableRuntimeGuestAddressProvider(
                reason: "runtime Guest address owner unavailable for default command worker"
            )
        )
    }

    public init(
        guestProductServiceController: any RuntimeGuestProductServiceCommandControlling,
        guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling,
        guestAddressProvider: any RuntimeGuestAddressProvider,
        guestControlBaseURLOverride: String? = nil
    ) {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacRuntimeControlLogExporter(),
            guestProductServiceController: guestProductServiceController,
            guestMaintenanceController: guestMaintenanceController,
            guestAddressProvider: guestAddressProvider,
            guestControlBaseURLOverride: guestControlBaseURLOverride
        )
    }

    init(
        privilegedCommandRunner: any PrivilegedCommandRunning,
        actionEnvironment: any RuntimeActionEnvironment,
        logExporter: any RuntimeLogExporting,
        guestProductServiceController: any RuntimeGuestProductServiceCommandControlling = UnavailableRuntimeGuestProductServiceController(),
        guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling = UnavailableRuntimeGuestMaintenanceController(),
        guestAddressProvider: any RuntimeGuestAddressProvider,
        guestControlBaseURLOverride: String? = nil
    ) {
        self.privilegedCommandRunner = privilegedCommandRunner
        self.actionEnvironment = actionEnvironment
        self.logExporter = logExporter
        self.guestProductServiceController = guestProductServiceController
        self.guestMaintenanceController = guestMaintenanceController
        self.guestAddressProvider = guestAddressProvider
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

            let result = await runPrivileged(RuntimeCommandFactory.shellCommand(
                executable: RuntimeControlClientConstants.Paths.launcher,
                arguments: RuntimeCommandFactory.configureRuntimeArguments(
                    settings: settings,
                    adminPasswordFile: adminPasswordFile?.path,
                    recorderIngressSettingsFile: recorderIngressSettingsFile.path
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
        let controller = guestMaintenanceController
        let archive = backupURL.path
        return try await runGuestControlCommand { gateway in
            let operation = try controller.restoreRedisBackup(
                archive: archive,
                gateway: gateway
            )
            return RuntimeCommandResult(guestControlOperation: operation)
        }
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

    /// Delivers the Guest operation unchanged for the Runtime Control HTTP API.
    public func requestDatastoreRepair() async throws -> RuntimeGuestControlServiceOperation {
        let controller = guestMaintenanceController
        return try await runGuestControlCommand { gateway in
            try controller.requestDatastoreRepair(gateway: gateway)
        }
    }

    /// Retains the Host command result used by native command consumers.
    public func repairDatastore() async throws -> RuntimeCommandResult {
        let controller = guestMaintenanceController
        return try await runGuestControlCommand { gateway in
            let operation = try controller.repairDatastore(gateway: gateway)
            return RuntimeCommandResult(guestControlOperation: operation)
        }
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

    public func controlRuntimeProvider(
        _ action: RuntimeProviderCommandAction
    ) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        return await runPrivileged(RuntimeCommandFactory.runtimeProviderCommand(action: action))
    }

    public func createRedisBackup() async throws -> RuntimeCommandResult {
        let controller = guestMaintenanceController
        return try await runGuestControlCommand { gateway in
            let operation = try controller.createRedisBackup(gateway: gateway)
            return RuntimeCommandResult(guestControlOperation: operation)
        }
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
        return try await runGuestControlCommand { gateway in
            try gateway.listServices()
        }
    }

    public func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        return try await runGuestControlCommand { gateway in
            try gateway.stackStatus()
        }
    }

    public func runtimeCapabilities() async throws -> RuntimeCapabilities {
        return try await runGuestControlCommand { gateway in
            RuntimeCapabilities(try gateway.capabilities())
        }
    }

    public func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        try await runGuestControlCommand { gateway in
            try gateway.runtimeSettings()
        }
    }

    public func applyRuntimeProductSettings(
        _ settings: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await runGuestControlCommand { gateway in
            try gateway.applyRuntimeSettings(settings)
        }
    }

    public func applyRuntimeAdminPassword(
        _ password: String
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await runGuestControlCommand { gateway in
            try gateway.applyAdminPassword(password)
        }
    }

    public func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        try await runGuestControlCommand { gateway in
            try gateway.redisRelaySettings()
        }
    }

    public func applyRuntimeRedisRelaySettings(
        _ settings: RuntimeRedisRelaySettingsApplyRequest
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await runGuestControlCommand { gateway in
            try gateway.applyRedisRelaySettings(settings)
        }
    }

    public func loadRuntimeOperationEvents(
        query: RuntimeEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        try await runGuestControlCommand { gateway in
            try gateway.runtimeEvents(query: query)
        }
    }

    public func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        return try await runGuestControlCommand { gateway in
            try gateway.serviceStatus(service)
        }
    }

    public func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        return try await runGuestControlCommand { gateway in
            try gateway.serviceResource(service)
        }
    }

    public func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        return try await runGuestControlCommand { gateway in
            try gateway.redisRelayStatus()
        }
    }

    public func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        let controller = guestProductServiceController
        let baseURLOverride = request.guestControlBaseURL
        let service = request.service
        return try await runGuestControlCommand(override: baseURLOverride) { gateway in
            try controller.startService(service, gateway: gateway)
        }
    }

    public func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        let controller = guestProductServiceController
        let baseURLOverride = request.guestControlBaseURL
        let service = request.service
        return try await runGuestControlCommand(override: baseURLOverride) { gateway in
            try controller.stopService(service, gateway: gateway)
        }
    }

    public func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        let controller = guestProductServiceController
        let baseURLOverride = request.guestControlBaseURL
        let service = request.service
        return try await runGuestControlCommand(override: baseURLOverride) { gateway in
            try controller.restartService(service, gateway: gateway)
        }
    }

    public func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        return await runGuestProductLabCommand {
            try $0.labScenarios()
        }
    }

    public func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        return await runGuestProductLabCommand {
            try $0.labVitalFiles()
        }
    }

    public func loadLabBeds() async throws -> RuntimeLabBedList {
        return await runGuestProductLabCommand {
            try $0.labBeds()
        }
    }

    public func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        return await runGuestProductLabCommand {
            try $0.labRecorders()
        }
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        return await runGuestProductLabCommand {
            try $0.createLabBeds(request)
        }
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        return await runGuestProductLabCommand {
            try $0.deleteLabBeds(request)
        }
    }

    public func resetLabBeds() async throws -> RuntimeLabBedList {
        return await runGuestProductLabCommand {
            try $0.resetLabBeds()
        }
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        return await runGuestProductLabCommand {
            try $0.createLabRecorders(request)
        }
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        return await runGuestProductLabCommand {
            try $0.deleteLabRecorders(request)
        }
    }

    public func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        return await runGuestProductLabCommand {
            try $0.resetLabRecorders()
        }
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

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        await runVitalDBBedVisibilityCommand { gateway in
            try gateway.hideVitalDBBeds(request)
        }
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        await runVitalDBBedVisibilityCommand { gateway in
            try gateway.unhideVitalDBBeds(request)
        }
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        await runVitalDBBedVisibilityCommand { gateway in
            try gateway.deleteVitalDBBeds(request)
        }
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        return await runGuestProductLabCommand {
            try $0.createLabSession(request)
        }
    }

    public func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return await runGuestProductLabCommand {
            try $0.labSession(sessionId)
        }
    }

    public func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return await runGuestProductLabCommand {
            try $0.startLabSession(sessionId)
        }
    }

    public func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return await runGuestProductLabCommand {
            try $0.stopLabSession(sessionId)
        }
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        return await runGuestProductLabCommand {
            try $0.replayLabVitalFile(request)
        }
    }

    public func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) async throws -> RuntimeLabVitalFileUploadResponse {
        return await runGuestProductLabCommand {
            try $0.uploadLabVitalFile(request)
        }
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
        let backupsRoot = InstalledRuntimePaths.defaultInstalled.backupsDirectory
        let runtimeDataBackupsRoot = InstalledRuntimePaths.defaultInstalled.vitalServerHelperBackupsDirectory
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
        let guestAddressRead = guestAddressProvider.readGuestAddress()
        if let vmIP = guestAddressRead.loadedAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !vmIP.isEmpty {
            return RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)
        }
        if guestAddressRead.state != .notReported {
            throw RuntimeClientError.guestControlUnavailable(
                "guest address is unavailable: \(guestAddressRead.failureStatusText)"
            )
        }
        throw RuntimeClientError.guestControlUnavailable(
            "guest address was not read"
        )
    }

    private func runGuestControlCommand<T>(
        override: String? = nil,
        _ command: @escaping @Sendable (any RuntimeGuestControlGateway) throws -> T
    ) async throws -> T {
        let baseURL = try guestControlBaseURL(override: override)
        let gateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
        return try command(gateway)
    }

    private func runGuestProductLabCommand<T: RuntimeLabResponseUnavailableFactory>(
        _ command: @escaping @Sendable (any RuntimeGuestProductLabGateway) throws -> T
    ) async -> T {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return T.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        do {
            let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
            return try command(gateway)
        } catch {
            return T.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
    }

    private func runVitalDBVisibilityCommand(
        _ command: @escaping @Sendable (any RuntimeGuestControlGateway) throws -> (
            RuntimeGuestControlVitalDBRecorderRead,
            RuntimeGuestControlVitalDBBedRead
        )
    ) async -> RuntimeVitalRecorderHistory {
        do {
            let reads = try await runGuestControlCommand { gateway in
                try command(gateway)
            }
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
    }

    private func runVitalDBBedVisibilityCommand(
        _ command: @escaping @Sendable (any RuntimeGuestControlGateway) throws -> RuntimeGuestControlVitalDBBedRead
    ) async -> RuntimeVitalBedHistory {
        do {
            let read = try await runGuestControlCommand { gateway in
                try command(gateway)
            }
            return RuntimeVitalDBBedHistoryAssembler.makeHistory(read: read)
        } catch {
            return .failed(readError: "VitalDB bed read model command failed: \(error)")
        }
    }

    private func runPrivileged(_ shellCommand: String) async -> RuntimeCommandResult {
        await privilegedCommandRunner.run(shellCommand: shellCommand)
    }
}

private struct UnavailableRuntimeGuestProductServiceController: RuntimeGuestProductServiceCommandControlling {
    func startService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func stopService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func restartService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    private func unavailable() -> RuntimeClientError {
        .guestControlUnavailable("guest product service controller unavailable")
    }
}

private struct UnavailableRuntimeGuestMaintenanceController: RuntimeGuestMaintenanceCommandControlling {
    func createRedisBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func restoreRedisBackup(
        archive: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func requestDatastoreRepair(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func repairDatastore(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func activateUpdate(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func prepareUpdateShutdown(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func requestGuestPoweroff(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    private func unavailable() -> RuntimeClientError {
        .guestControlUnavailable("guest maintenance controller unavailable")
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

extension RuntimeLabScenarioList: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabVitalFileList: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabBedList: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabRecorderList: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabSessionResponse: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabVitalFileUploadResponse: RuntimeLabResponseUnavailableFactory {}

extension MacRuntimeControlCommandWorker: RuntimeGuestMaintenanceOperationClient {}

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
