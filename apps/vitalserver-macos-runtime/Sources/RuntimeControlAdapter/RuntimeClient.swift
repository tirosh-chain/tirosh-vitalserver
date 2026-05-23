import Foundation
import RuntimeControl

@MainActor
public struct LocalRuntimeClient: RuntimeClient {
    public let capabilities = RuntimeClientCapabilities()

    private let releaseInfo: RuntimeReleaseInfo
    private let statusReader: RuntimeStatusReading
    private let fileReader: RuntimeManagerFileReading
    private let settingsReader: RuntimeSettingsReading
    private let privilegedCommandRunner: PrivilegedCommandRunning
    private let actionEnvironment: RuntimeActionEnvironment
    private let logExporter: RuntimeLogExporting

    public init(
        releaseInfo: RuntimeReleaseInfo
    ) {
        self.init(
            releaseInfo: releaseInfo,
            statusReader: SystemRuntimeStatusReader(paths: RuntimePaths()),
            fileReader: SystemRuntimeManagerFileReader(),
            settingsReader: SystemRuntimeSettingsReader(),
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: LocalRuntimeLogExporter()
        )
    }

    init(
        releaseInfo: RuntimeReleaseInfo,
        statusReader: RuntimeStatusReading = SystemRuntimeStatusReader(paths: RuntimePaths()),
        fileReader: RuntimeManagerFileReading = SystemRuntimeManagerFileReader(),
        settingsReader: RuntimeSettingsReading = SystemRuntimeSettingsReader(),
        privilegedCommandRunner: PrivilegedCommandRunning = SystemPrivilegedCommandRunner(),
        actionEnvironment: RuntimeActionEnvironment = SystemRuntimeActionEnvironment(),
        logExporter: RuntimeLogExporting = LocalRuntimeLogExporter()
    ) {
        self.releaseInfo = releaseInfo
        self.statusReader = statusReader
        self.fileReader = fileReader
        self.settingsReader = settingsReader
        self.privilegedCommandRunner = privilegedCommandRunner
        self.actionEnvironment = actionEnvironment
        self.logExporter = logExporter
    }

    public func loadSettings() -> RuntimeSettings {
        settingsReader.load()
    }

    public func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        statusReader.loadStatus(settings: settings)
    }

    public func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        await statusReader.loadHealthStatus(settings: settings)
    }

    public func loadBackups(latestBackupPath: String?) -> [RuntimeBackup] {
        fileReader.backups(latestBackupPath: latestBackupPath)
    }

    public func updateBundleSummary(url: URL) -> String {
        fileReader.updateBundleSummary(url: url)
    }

    public func logText(sourceID: LogSourceID, helperMessage: String, lineLimit: Int) -> String {
        fileReader.logText(sourceID: sourceID, helperMessage: helperMessage, lineLimit: lineLimit)
    }

    public func preferredLogsPath() -> String {
        fileReader.preferredLogsPath()
    }

    public func vitalFileFolders(root: String) -> [VitalFileFolder] {
        fileReader.vitalFileFolders(root: root)
    }

    public func legacyCommandProgressLine() -> String? {
        statusReader.legacyCommandProgressLine()
    }

    public func createDirectory(at url: URL) {
        actionEnvironment.createDirectory(at: url)
    }

    public func verifyUpdateBundle(url: URL) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await actionEnvironment.verifyBundle(launcher: RuntimeAdapterConstants.Paths.launcher, bundleURL: url)
    }

    public func uninstallRuntime(clean: Bool) async throws -> ProcessResult {
        guard actionEnvironment.isExecutable(atPath: RuntimeAdapterConstants.Paths.uninstaller) else {
            throw RuntimeClientError.missingUninstaller
        }
        return await runPrivileged(RuntimeCommandFactory.uninstallCommand(
            uninstaller: RuntimeAdapterConstants.Paths.uninstaller,
            clean: clean
        ))
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> ProcessResult {
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
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: settings.configureArguments(adminPasswordFile: adminPasswordFile?.path)
        ))
    }

    public func applyUpdateBundle(url: URL) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.applyBundle,
                url.path,
            ]
        ))
    }

    public func rollbackRuntime(backupURL: URL) async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.rollback,
                backupURL.path,
            ]
        ))
    }

    public func deleteBackup(url: URL) async throws -> ProcessResult {
        await runPrivileged(RuntimeCommandFactory.deleteBackupCommand(url: url))
    }

    public func repairProxy(proxyPort: Int) async throws -> ProcessResult {
        await runPrivileged(RuntimeCommandFactory.proxyRepairCommand(proxyPort: proxyPort))
    }

    public func repairDatastore() async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.repairDatastore,
            ]
        ))
    }

    public func startRuntimeServices() async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .start))
    }

    public func stopRuntimeServices() async throws -> ProcessResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .stop))
    }

    public func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        return try await logExporter.exportLogs(to: destination)
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        releaseInfo
    }

    public func loadInstallationInfo() -> RuntimeInstallationInfo {
        RuntimeInstallationInfo(
            runtimeHomePath: RuntimeAdapterConstants.Paths.vmHome,
            backupsPath: RuntimeAdapterConstants.Paths.backups
        )
    }

    private func ensureLauncherIsAvailable() throws {
        guard actionEnvironment.isExecutable(atPath: RuntimeAdapterConstants.Paths.launcher) else {
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
    case logExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingLauncher:
            return RuntimeAdapterConstants.StatusText.missingLauncher
        case .missingUninstaller:
            return RuntimeAdapterConstants.StatusText.missingUninstaller
        case .logExportFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? RuntimeAdapterConstants.StatusText.logExportFailed : trimmed
        }
    }
}
