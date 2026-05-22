import Foundation

struct RuntimeClientCapabilities: Equatable {
    var canInstallRuntime = true
    var canUninstallRuntime = true
    var canApplyBundle = true
    var canRollback = true
    var canEditVMResources = true
    var canEditNetworkExposure = true
    var canResetAdminPassword = true
    var canOpenLocalFiles = true
    var canStreamLogs = true
}

@MainActor
protocol RuntimeClient {
    var capabilities: RuntimeClientCapabilities { get }

    func loadSettings() -> RuntimeSettings
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadBackups(latestBackupPath: String?) -> [RuntimeBackup]
    func updateBundleSummary(url: URL) -> String
    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFileFolder]
    func legacyCommandProgressLine() -> String?
    func createDirectory(at url: URL)
    func verifyUpdateBundle(path: String) async throws -> ProcessResult
    func uninstallRuntime(clean: Bool) async throws -> ProcessResult
    func applySettings(_ settings: RuntimeSettings) async throws -> ProcessResult
    func applyUpdateBundle(path: String) async throws -> ProcessResult
    func rollbackRuntime(backupPath: String) async throws -> ProcessResult
    func deleteBackup(path: String) async throws -> ProcessResult
    func repairProxy(proxyPort: Int) async throws -> ProcessResult
    func repairDatastore() async throws -> ProcessResult
    func startRuntimeServices() async throws -> ProcessResult
    func stopRuntimeServices() async throws -> ProcessResult
}

@MainActor
struct LocalRuntimeClient: RuntimeClient {
    let capabilities = RuntimeClientCapabilities()

    private let statusReader: RuntimeStatusReading
    private let fileReader: RuntimeManagerFileReading
    private let settingsReader: RuntimeSettingsReading
    private let privilegedCommandRunner: PrivilegedCommandRunning
    private let actionEnvironment: RuntimeActionEnvironment

    init(
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        fileReader: RuntimeManagerFileReading = SystemRuntimeManagerFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        privilegedCommandRunner: PrivilegedCommandRunning = SystemPrivilegedCommandRunner(),
        actionEnvironment: RuntimeActionEnvironment = SystemRuntimeActionEnvironment()
    ) {
        self.statusReader = statusReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
        self.privilegedCommandRunner = privilegedCommandRunner
        self.actionEnvironment = actionEnvironment
    }

    func loadSettings() -> RuntimeSettings {
        settingsReader.load()
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        statusReader.loadStatus(settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        await statusReader.loadHealthStatus(settings: settings)
    }

    func loadBackups(latestBackupPath: String?) -> [RuntimeBackup] {
        fileReader.backups(latestBackupPath: latestBackupPath)
    }

    func updateBundleSummary(url: URL) -> String {
        fileReader.updateBundleSummary(url: url)
    }

    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String {
        fileReader.logText(sourceID: sourceID, helperMessage: helperMessage, lineLimit: lineLimit)
    }

    func preferredLogsPath() -> String {
        fileReader.preferredLogsPath()
    }

    func vitalFileFolders(root: String) -> [VitalFileFolder] {
        fileReader.vitalFileFolders(root: root)
    }

    func legacyCommandProgressLine() -> String? {
        statusReader.legacyCommandProgressLine()
    }

    func createDirectory(at url: URL) {
        actionEnvironment.createDirectory(at: url)
    }

    func verifyUpdateBundle(path: String) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await actionEnvironment.verifyBundle(launcher: AppConstants.Paths.launcher, bundlePath: path)
    }

    func uninstallRuntime(clean: Bool) async throws -> ProcessResult {
        guard actionEnvironment.isExecutable(atPath: AppConstants.Paths.uninstaller) else {
            throw RuntimeClientError.missingUninstaller
        }
        return await runPrivileged(RuntimeCommandFactory.uninstallCommand(
            uninstaller: AppConstants.Paths.uninstaller,
            clean: clean
        ))
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        var adminPasswordFile: URL?
        if settings.changeAdminPassword {
            adminPasswordFile = try actionEnvironment.writeAdminPasswordFile(settings.adminPassword)
        }
        defer {
            if let adminPasswordFile {
                actionEnvironment.removeItem(at: adminPasswordFile)
            }
        }
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: AppConstants.Paths.launcher,
            arguments: settings.configureArguments(adminPasswordFile: adminPasswordFile?.path)
        ))
    }

    func applyUpdateBundle(path: String) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: AppConstants.Paths.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.applyBundle,
                path,
            ]
        ))
    }

    func rollbackRuntime(backupPath: String) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: AppConstants.Paths.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.rollback,
            ] + (backupPath.isEmpty ? [] : [backupPath])
        ))
    }

    func deleteBackup(path: String) async throws -> ProcessResult {
        await runPrivileged(RuntimeCommandFactory.deleteBackupCommand(path: path))
    }

    func repairProxy(proxyPort: Int) async throws -> ProcessResult {
        await runPrivileged(RuntimeCommandFactory.proxyRepairCommand(proxyPort: proxyPort))
    }

    func repairDatastore() async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: AppConstants.Paths.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.repairDatastore,
            ]
        ))
    }

    func startRuntimeServices() async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .start))
    }

    func stopRuntimeServices() async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .stop))
    }

    private func ensureLauncherIsAvailable() throws {
        guard actionEnvironment.isExecutable(atPath: AppConstants.Paths.launcher) else {
            throw RuntimeClientError.missingLauncher
        }
    }

    private func runPrivileged(_ shellCommand: String) async -> ProcessResult {
        await privilegedCommandRunner.run(shellCommand: shellCommand)
    }
}

enum RuntimeClientError: LocalizedError {
    case missingLauncher
    case missingUninstaller

    var errorDescription: String? {
        switch self {
        case .missingLauncher:
            return AppConstants.StatusText.missingLauncher
        case .missingUninstaller:
            return AppConstants.StatusText.missingUninstaller
        }
    }
}
