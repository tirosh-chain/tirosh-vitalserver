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
    private let updateRequestID: @Sendable () -> String
    private let platformAgentVerificationInvoker:
        (any PlatformAgentUpdateBootstrapVerificationInvoking)?
    private let platformAgentSelectionOwner:
        (any PlatformAgentUpdateBootstrapSelectionOwning)?
    private var platformAgentUpdateInFlight: PlatformAgentUpdateInFlight?

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
        guestControlBaseURLOverride: String? = nil,
        platformAgentVerificationInvoker:
            (any PlatformAgentUpdateBootstrapVerificationInvoking)? = nil,
        platformAgentSelectionOwner:
            (any PlatformAgentUpdateBootstrapSelectionOwning)? = nil
    ) {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacRuntimeControlLogExporter(),
            guestProductServiceController: guestProductServiceController,
            guestMaintenanceController: guestMaintenanceController,
            guestAddressProvider: guestAddressProvider,
            guestControlBaseURLOverride: guestControlBaseURLOverride,
            platformAgentVerificationInvoker: platformAgentVerificationInvoker,
            platformAgentSelectionOwner: platformAgentSelectionOwner
        )
    }

    init(
        privilegedCommandRunner: any PrivilegedCommandRunning,
        actionEnvironment: any RuntimeActionEnvironment,
        logExporter: any RuntimeLogExporting,
        guestProductServiceController: any RuntimeGuestProductServiceCommandControlling = UnavailableRuntimeGuestProductServiceController(),
        guestMaintenanceController: any RuntimeGuestMaintenanceCommandControlling = UnavailableRuntimeGuestMaintenanceController(),
        guestAddressProvider: any RuntimeGuestAddressProvider,
        guestControlBaseURLOverride: String? = nil,
        updateRequestID: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        },
        platformAgentVerificationInvoker:
            (any PlatformAgentUpdateBootstrapVerificationInvoking)? = nil,
        platformAgentSelectionOwner:
            (any PlatformAgentUpdateBootstrapSelectionOwning)? = nil
    ) {
        self.privilegedCommandRunner = privilegedCommandRunner
        self.actionEnvironment = actionEnvironment
        self.logExporter = logExporter
        self.guestProductServiceController = guestProductServiceController
        self.guestMaintenanceController = guestMaintenanceController
        self.guestAddressProvider = guestAddressProvider
        self.guestControlBaseURLOverride = guestControlBaseURLOverride
        self.updateRequestID = updateRequestID
        self.platformAgentVerificationInvoker = platformAgentVerificationInvoker
        self.platformAgentSelectionOwner = platformAgentSelectionOwner
    }

    public func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try ensureExecutable(.launcher)
        let launcher = RuntimeControlClientConstants.Paths.launcher
        let environment = actionEnvironment
        guard let invoker = platformAgentVerificationInvoker else {
            return await environment.verifyBundle(
                launcher: launcher,
                bundleURL: url,
                verificationInvocationId: nil
            )
        }
        if let inFlight = platformAgentUpdateInFlight {
            return PlatformAgentVerifiedSelectionConsumeMapping.commandResult(
                error: PlatformAgentUpdateInFlightError(inFlight)
            )
        }
        platformAgentUpdateInFlight = .verify
        defer { platformAgentUpdateInFlight = nil }
        return await invoker.invoke(bundleURL: url) { invocationId in
            await environment.verifyBundle(
                launcher: launcher,
                bundleURL: url,
                verificationInvocationId: invocationId
            )
        }
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
        try await applySettings(settings, forceVMRuntimeRestart: false)
    }

    public func restartVMRuntime(applying settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        try await applySettings(settings, forceVMRuntimeRestart: true)
    }

    private func applySettings(
        _ settings: RuntimeSettings,
        forceVMRuntimeRestart: Bool
    ) async throws -> RuntimeCommandResult {
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
                    recorderIngressSettingsFile: recorderIngressSettingsFile.path,
                    forceVMRuntimeRestart: forceVMRuntimeRestart
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
        guard let owner = platformAgentSelectionOwner else {
            return await runPrivileged(RuntimeCommandFactory.shellCommand(
                executable: RuntimeControlClientConstants.Paths.launcher,
                arguments: [
                    RuntimeControlClientConstants.RuntimeCommand.runtime,
                    RuntimeControlClientConstants.RuntimeCommand.applyUpdateBootstrap,
                    url.path,
                    RuntimeControlClientConstants.RuntimeCommand.optionRequestID,
                    updateRequestID(),
                ]
            ))
        }
        if let inFlight = platformAgentUpdateInFlight {
            return PlatformAgentVerifiedSelectionConsumeMapping.commandResult(
                error: PlatformAgentUpdateInFlightError(inFlight)
            )
        }
        platformAgentUpdateInFlight = .apply(requestId: nil)
        defer { platformAgentUpdateInFlight = nil }
        let requestId: String
        do {
            requestId = try owner.bindApply(
                observedBundlePath: url.path,
                mintRequestId: updateRequestID
            )
        } catch {
            return PlatformAgentVerifiedSelectionConsumeMapping
                .commandResult(error: error)
        }
        platformAgentUpdateInFlight = .apply(requestId: requestId)
        let result = await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.applyUpdateBootstrap,
                url.path,
                RuntimeControlClientConstants.RuntimeCommand.optionRequestID,
                requestId,
                RuntimeControlClientConstants.RuntimeCommand
                    .optionRequirePlatformAgentSelection,
            ]
        ))
        if result.exitCode == 0 {
            do {
                try owner.spendApply(requestId: requestId)
            } catch {
                return result.appendingOutputIssue(
                    RuntimeCommandOutputIssue(
                        stream: .stderr,
                        message: PlatformAgentVerifiedSelectionConsumeMapping
                            .message(error)
                    )
                ).failingIfSuccessful()
            }
        }
        return result
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
        query: RuntimeOperationEventQuery
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
        return try await runGuestProductLabCommand {
            try $0.labScenarios()
        }
    }

    public func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        return try await runGuestProductLabCommand {
            try $0.labVitalFiles()
        }
    }

    public func loadLabBeds() async throws -> RuntimeLabBedList {
        return try await runGuestProductLabCommand {
            try $0.labBeds()
        }
    }

    public func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        return try await runGuestProductLabCommand {
            try $0.labRecorders()
        }
    }

    public func loadLabSessions() async throws -> RuntimeLabSessionList {
        return try await runGuestProductLabCommand {
            try $0.labSessions()
        }
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        return try await runGuestProductLabCommand {
            try $0.createLabBeds(request)
        }
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        return try await runGuestProductLabCommand {
            try $0.deleteLabBeds(request)
        }
    }

    public func resetLabBeds() async throws -> RuntimeLabBedList {
        return try await runGuestProductLabCommand {
            try $0.resetLabBeds()
        }
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        return try await runGuestProductLabCommand {
            try $0.createLabRecorders(request)
        }
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        return try await runGuestProductLabCommand {
            try $0.deleteLabRecorders(request)
        }
    }

    public func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        return try await runGuestProductLabCommand {
            try $0.resetLabRecorders()
        }
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            try gateway.hideVitalDBRecorders(request)
        }
    }

    public func applyRecorderObservabilityExpectation(
        _ command: RuntimeRecorderObservabilityExpectationCommand
    ) async throws -> RuntimeRecorderObservabilityExpectationReceipt {
        try await runVitalDBGuestControlCommand { gateway in
            try gateway.applyRecorderObservabilityExpectation(command)
        }
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            try gateway.unhideVitalDBRecorders(request)
        }
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        await runVitalDBVisibilityCommand { gateway in
            try gateway.deleteVitalDBRecorders(request)
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
        return try await runGuestProductLabCommand {
            try $0.createLabSession(request)
        }
    }

    public func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return try await runGuestProductLabCommand {
            try $0.labSession(sessionId)
        }
    }

    public func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return try await runGuestProductLabCommand {
            try $0.startLabSession(sessionId)
        }
    }

    public func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return try await runGuestProductLabCommand {
            try $0.stopLabSession(sessionId)
        }
    }

    public func finishLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        return try await runGuestProductLabCommand {
            try $0.finishLabSession(sessionId)
        }
    }

    public func startLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        return try await runGuestProductLabCommand {
            try $0.startLabRecorder(sessionId: sessionId, recorderId: recorderId)
        }
    }

    public func stopLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        return try await runGuestProductLabCommand {
            try $0.stopLabRecorder(sessionId: sessionId, recorderId: recorderId)
        }
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        return try await runGuestProductLabCommand {
            try $0.replayLabVitalFile(request)
        }
    }

    public func uploadLabVitalFiles(
        _ sources: [RuntimeLabVitalFileUploadSource]
    ) async throws -> RuntimeLabVitalFileLibraryUploadResponse {
        let baseURL = try guestControlBaseURL()
        let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(
            baseURL: baseURL
        )
        return try gateway.uploadLabVitalFiles(sources)
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
    ) async throws -> T {
        let baseURL: String
        do {
            baseURL = try guestControlBaseURL()
        } catch {
            return T.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
        do {
            let gateway: any RuntimeGuestProductLabGateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
            return try command(gateway)
        } catch let error as RuntimeControlOperationInProgressError {
            throw error
        } catch {
            return T.unavailable(readError: "Runtime Lab gateway failed: \(error)")
        }
    }

    private func runVitalDBVisibilityCommand(
        _ command: @escaping @Sendable (any RuntimeVitalDBGuestControlGateway) throws -> RuntimeVitalRecorderHistory
    ) async -> RuntimeVitalRecorderHistory {
        do {
            return try await runVitalDBGuestControlCommand { gateway in
                try command(gateway)
            }
        } catch {
            return RuntimeVitalRecorderHistory(readError: "VitalDB read model command failed: \(error)")
        }
    }

    private func runVitalDBBedVisibilityCommand(
        _ command: @escaping @Sendable (any RuntimeVitalDBGuestControlGateway) throws -> RuntimeVitalBedHistory
    ) async -> RuntimeVitalBedHistory {
        do {
            return try await runVitalDBGuestControlCommand { gateway in
                try command(gateway)
            }
        } catch {
            return .failed(readError: "VitalDB bed read model command failed: \(error)")
        }
    }

    private func runVitalDBGuestControlCommand<T>(
        _ command: @escaping @Sendable (any RuntimeVitalDBGuestControlGateway) throws -> T
    ) async throws -> T {
        let baseURL = try guestControlBaseURL()
        let gateway = try HTTPRuntimeGuestControlGateway(baseURL: baseURL)
        return try command(gateway)
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
    func createPostgresBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

    func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        throw unavailable()
    }

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
extension RuntimeLabSessionList: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabSessionResponse: RuntimeLabResponseUnavailableFactory {}
extension RuntimeLabRecorderResponse: RuntimeLabResponseUnavailableFactory {}

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

private extension RuntimeCommandResult {
    func failingIfSuccessful() -> RuntimeCommandResult {
        RuntimeCommandResult(
            exitCode: exitCode == 0 ? 1 : exitCode,
            stdout: stdout,
            stderr: stderr,
            outputIssues: outputIssues,
            executionIssue: executionIssue
        )
    }
}

enum PlatformAgentUpdateInFlight: Equatable, Sendable {
    case verify
    case apply(requestId: String?)
}

enum PlatformAgentUpdateInFlightError: Error, Equatable, Sendable {
    case verifyInFlight
    case applyInFlight(requestId: String?)

    init(_ inFlight: PlatformAgentUpdateInFlight) {
        switch inFlight {
        case .verify:
            self = .verifyInFlight
        case .apply(let requestId):
            self = .applyInFlight(requestId: requestId)
        }
    }
}

enum PlatformAgentVerifiedSelectionConsumeMapping {
    static func commandResult(error: Error) -> RuntimeCommandResult {
        RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: message(error),
            executionIssue: nil
        )
    }

    static func message(_ error: Error) -> String {
        if let error = error as? PlatformAgentUpdateInFlightError {
            return inFlightMessage(error)
        }
        if let error = error as? BindPlatformAgentUpdateBootstrapApplyError {
            return bindMessage(error)
        }
        if let error = error as? SpendPlatformAgentUpdateBootstrapApplyError {
            return spendMessage(error)
        }
        if let error = error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
        {
            return recordMessage(error)
        }
        return "platform-agent verified selection failed: \(error)"
    }

    private static func inFlightMessage(
        _ error: PlatformAgentUpdateInFlightError
    ) -> String {
        switch error {
        case .verifyInFlight:
            return "platform-agent verify in flight"
        case .applyInFlight(let requestId):
            if let requestId {
                return "platform-agent apply in flight requestId=\(requestId)"
            }
            return "platform-agent apply in flight"
        }
    }

    private static func bindMessage(
        _ error: BindPlatformAgentUpdateBootstrapApplyError
    ) -> String {
        switch error {
        case .missing(let path):
            return "platform-agent verified selection missing: \(path)"
        case .stale:
            return "platform-agent verified selection stale"
        case .conflict(let expectedPath, let actualPath):
            return
                "platform-agent verified selection conflict expectedPath=\(expectedPath) actualPath=\(actualPath)"
        case .invalid(let reason):
            return "platform-agent verified selection invalid: \(reason)"
        case .inspectionFailed(let path, let reason):
            return
                "platform-agent verified selection inspection failed path=\(path) reason=\(reason)"
        case .permissionDenied(let path, let reason):
            return
                "platform-agent verified selection permission denied path=\(path) reason=\(reason)"
        case .readFailed(let path, let reason):
            return
                "platform-agent verified selection read failed path=\(path) reason=\(reason)"
        case .decodeFailed(let path, let reason):
            return
                "platform-agent verified selection decode failed path=\(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return
                "platform-agent verified selection unexpected path state path=\(path) state=\(state)"
        case .persistFailed(let reason):
            return "platform-agent verified selection persist failed: \(reason)"
        }
    }

    private static func spendMessage(
        _ error: SpendPlatformAgentUpdateBootstrapApplyError
    ) -> String {
        switch error {
        case .missing(let path):
            return "platform-agent verified selection missing: \(path)"
        case .invalid(let reason):
            return "platform-agent verified selection invalid: \(reason)"
        case .requestMismatch(let expected, let actual):
            return
                "platform-agent verified selection request mismatch expected=\(expected) actual=\(actual)"
        case .inspectionFailed(let path, let reason):
            return
                "platform-agent verified selection inspection failed path=\(path) reason=\(reason)"
        case .permissionDenied(let path, let reason):
            return
                "platform-agent verified selection permission denied path=\(path) reason=\(reason)"
        case .readFailed(let path, let reason):
            return
                "platform-agent verified selection read failed path=\(path) reason=\(reason)"
        case .decodeFailed(let path, let reason):
            return
                "platform-agent verified selection decode failed path=\(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return
                "platform-agent verified selection unexpected path state path=\(path) state=\(state)"
        case .persistFailed(let reason):
            return "platform-agent verified selection persist failed: \(reason)"
        }
    }

    private static func recordMessage(
        _ error: RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
    ) -> String {
        switch error {
        case .inFlight(let requestId):
            return
                "platform-agent verified selection in flight requestId=\(requestId)"
        case .persistFailed(let reason):
            return "platform-agent verified selection persist failed: \(reason)"
        default:
            return "platform-agent verified selection invalid: \(error)"
        }
    }
}
