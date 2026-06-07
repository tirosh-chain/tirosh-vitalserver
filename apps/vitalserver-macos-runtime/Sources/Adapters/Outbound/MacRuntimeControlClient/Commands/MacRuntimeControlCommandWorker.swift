import Foundation
import RuntimeControl
import Contracts
import Errors

/// Owns host mutations and privileged runtime commands.
/// SwiftUI and the development API call through this actor so MainActor only coordinates UI state.
public actor MacRuntimeControlCommandWorker {
    private let privilegedCommandRunner: any PrivilegedCommandRunning
    private let actionEnvironment: any RuntimeActionEnvironment
    private let logExporter: any RuntimeLogExporting

    public init() {
        self.init(
            privilegedCommandRunner: SystemPrivilegedCommandRunner(),
            actionEnvironment: SystemRuntimeActionEnvironment(),
            logExporter: MacRuntimeControlLogExporter()
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
        return await actionEnvironment.verifyBundle(launcher: RuntimeControlClientConstants.Paths.launcher, bundleURL: url)
    }

    public func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult {
        try ensureExecutableIsAvailable(
            path: RuntimeControlClientConstants.Paths.uninstaller,
            missing: .missingUninstaller,
            inspectionFailed: RuntimeClientError.uninstallerInspectionFailed,
            notExecutable: RuntimeClientError.uninstallerNotExecutable
        )
        return await runPrivileged(RuntimeCommandFactory.uninstallCommand(
            uninstaller: RuntimeControlClientConstants.Paths.uninstaller,
            clean: clean
        ))
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        var adminPasswordFile: URL?
        if settings.changeAdminPassword {
            adminPasswordFile = try actionEnvironment.writeAdminPasswordFile(settings.adminPassword)
        }
        let result = await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: RuntimeCommandFactory.configureRuntimeArguments(
                settings: settings,
                adminPasswordFile: adminPasswordFile?.path
            )
        ))
        guard let adminPasswordFile else {
            return result
        }
        do {
            try actionEnvironment.removeItem(at: adminPasswordFile)
            return result
        } catch {
            return result.appendingOutputIssue(RuntimeCommandOutputIssue(
                stream: .stderr,
                message: "admin password file cleanup failed path=\(adminPasswordFile.path) reason=\(error.localizedDescription)"
            ))
        }
    }

    public func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
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
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.rollback,
                backupURL.path,
            ]
        ))
    }

    public func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        try ensureManagedBackupDeletionTarget(url)
        return await runPrivileged(RuntimeCommandFactory.deleteBackupCommand(url: url))
    }

    public func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult {
        return await runPrivileged(RuntimeCommandFactory.proxyRepairCommand())
    }

    public func repairDatastore() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.repairDatastore,
            ]
        ))
    }

    public func repairVMDisk() async throws -> RuntimeCommandResult {
        try ensureLauncherIsAvailable()
        return await runPrivileged(RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.repairVMDisk,
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
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.redisBackup,
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
        try ensureExecutableIsAvailable(
            path: RuntimeControlClientConstants.Paths.launcher,
            missing: .missingLauncher,
            inspectionFailed: RuntimeClientError.launcherInspectionFailed,
            notExecutable: RuntimeClientError.launcherNotExecutable
        )
    }

    private func ensureExecutableIsAvailable(
        path: String,
        missing: RuntimeClientError,
        inspectionFailed: (String, String) -> RuntimeClientError,
        notExecutable: (String, String) -> RuntimeClientError
    ) throws {
        switch actionEnvironment.executableState(atPath: path) {
        case .executable:
            return
        case .missing:
            throw missing
        case .inspectFailed(let reason):
            throw inspectionFailed(path, reason)
        case .present:
            throw notExecutable(path, "present")
        case .unknown(let state):
            throw notExecutable(path, state)
        }
    }

    private func ensureManagedBackupDeletionTarget(_ url: URL) throws {
        let backupsRoot = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.backups)
        guard RuntimeManagedBackupPolicy.isManagedBackupURL(url, backupsRoot: backupsRoot) else {
            throw RuntimeClientError.invalidBackupDeletionTarget(
                path: url.path,
                backupsRoot: backupsRoot.path
            )
        }
    }

    private func runPrivileged(_ shellCommand: String) async -> RuntimeCommandResult {
        await privilegedCommandRunner.run(shellCommand: shellCommand)
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
