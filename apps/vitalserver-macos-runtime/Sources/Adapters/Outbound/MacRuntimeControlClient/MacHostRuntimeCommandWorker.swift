import Foundation
import RuntimeControl
import Errors

/// Owns host mutations and privileged runtime commands.
/// SwiftUI and the development API call through this actor so MainActor only coordinates UI state.
public actor MacHostRuntimeCommandWorker {
    private let privilegedCommandRunner: any PrivilegedCommandRunning
    private let actionEnvironment: any RuntimeActionEnvironment
    private let logExporter: any RuntimeLogExporting

    public init() {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacHostRuntimeLogExporter()
        )
    }

    init(
        privilegedCommandRunner: any PrivilegedCommandRunning,
        actionEnvironment: any RuntimeActionEnvironment,
        logExporter: any RuntimeLogExporting
    ) {
        self.privilegedCommandRunner = privilegedCommandRunner
        self.actionEnvironment = actionEnvironment
        self.logExporter = logExporter
    }

    public func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await actionEnvironment.verifyBundle(launcher: RuntimeAdapterConstants.Paths.launcher, bundleURL: url)
    }

    public func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult {
        guard actionEnvironment.isExecutable(atPath: RuntimeAdapterConstants.Paths.uninstaller) else {
            throw RuntimeClientError.missingUninstaller
        }
        return await runPrivileged(RuntimeCommandFactory.uninstallCommand(
            uninstaller: RuntimeAdapterConstants.Paths.uninstaller,
            clean: clean
        ))
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
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
            arguments: RuntimeCommandFactory.configureRuntimeArguments(
                settings: settings,
                adminPasswordFile: adminPasswordFile?.path
            )
        ))
    }

    public func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
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

    public func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
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

    public func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        await runPrivileged(RuntimeCommandFactory.deleteBackupCommand(url: url))
    }

    public func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult {
        await runPrivileged(RuntimeCommandFactory.proxyRepairCommand(proxyPort: proxyPort))
    }

    public func repairDatastore() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.repairDatastore,
            ]
        ))
    }

    public func repairVMDisk() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.repairVMDisk,
            ]
        ))
    }

    public func repairRuntimeServices() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .repair))
    }

    public func createRedisBackup() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeAdapterConstants.Paths.launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.redisBackup,
            ]
        ))
    }

    public func startRuntimeServices() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .start))
    }

    public func stopRuntimeServices() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.runtimeServicesCommand(action: .stop))
    }

    public func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        try await logExporter.exportLogs(to: destination)
    }

    private func ensureLauncherIsAvailable() throws {
        guard actionEnvironment.isExecutable(atPath: RuntimeAdapterConstants.Paths.launcher) else {
            throw RuntimeClientError.missingLauncher
        }
    }

    private func runPrivileged(_ shellCommand: String) async -> RuntimeCommandResult {
        await privilegedCommandRunner.run(shellCommand: shellCommand)
    }
}
